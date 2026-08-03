#!/bin/sh
set -eu

if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <AnimalCrossing-pid> <A|B|X|Y|Start|Z|L|R|DUp|DDown|DLeft|DRight> <count> <PADRead-interval>" >&2
    exit 2
fi

pid=$1
button=$2
count=$3
pad_reads=$4

case "$pid" in
    ''|*[!0-9]*)
        echo "PID must contain only decimal digits." >&2
        exit 2
        ;;
esac

for value in "$count" "$pad_reads"; do
    case "$value" in
        ''|*[!0-9]*)
            echo "Count and PADRead interval must be decimal integers." >&2
            exit 2
            ;;
    esac
done

if [ "$count" -lt 1 ] || [ "$count" -gt 100 ]; then
    echo "Count must be between 1 and 100." >&2
    exit 2
fi
if [ "$pad_reads" -lt 1 ] || [ "$pad_reads" -gt 10000 ]; then
    echo "PADRead interval must be between 1 and 10000." >&2
    exit 2
fi

command_line=$(ps -p "$pid" -o command= 2>/dev/null || true)
case "$command_line" in
    *AnimalCrossing*) ;;
    *)
        echo "PID $pid is not a running AnimalCrossing desktop baseline." >&2
        exit 1
        ;;
esac

case "$button" in
    A)      scancode=44 ;;
    B)      scancode=225 ;;
    X)      scancode=27 ;;
    Y)      scancode=28 ;;
    Start)  scancode=40 ;;
    Z)      scancode=29 ;;
    L)      scancode=20 ;;
    R)      scancode=8 ;;
    DUp)    scancode=12 ;;
    DDown)  scancode=14 ;;
    DLeft)  scancode=13 ;;
    DRight) scancode=15 ;;
    *)
        echo "Unsupported button: $button" >&2
        exit 2
        ;;
esac

set -- --batch -p "$pid" \
    -o "expression -- (void)pc_pad_queue_scancode($scancode)"

step=1
while [ "$step" -lt "$count" ]; do
    set -- "$@" \
        -o "breakpoint set --name PADRead --ignore-count $pad_reads --one-shot true" \
        -o continue \
        -o "expression -- (void)pc_pad_queue_scancode($scancode)"
    step=$((step + 1))
done

set -- "$@" -o detach

attempt=1
while :; do
    if output=$(lldb "$@" 2>&1); then
        printf '%s\n' "$output"
        break
    fi

    if [ "$attempt" -ge 5 ]; then
        printf '%s\n' "$output" >&2
        exit 1
    fi
    case "$output" in
        *"already being debugged"*) sleep 2 ;;
        *) printf '%s\n' "$output" >&2; exit 1 ;;
    esac
    attempt=$((attempt + 1))
done
