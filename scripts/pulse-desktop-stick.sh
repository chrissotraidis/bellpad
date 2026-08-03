#!/bin/sh
set -eu

if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
    echo "Usage: $0 <AnimalCrossing-pid> <x:-128..127> <y:-128..127> <PADRead-count> [A|B|X|Y|Start|Z|L|R|DUp|DDown|DLeft|DRight]" >&2
    exit 2
fi

pid=$1
stick_x=$2
stick_y=$3
pad_reads=$4
button=${5-}

case "$pid" in
    ''|*[!0-9]*)
        echo "PID must contain only decimal digits." >&2
        exit 2
        ;;
esac

for value in "$stick_x" "$stick_y"; do
    case "$value" in
        -*) digits=${value#-} ;;
        *) digits=$value ;;
    esac
    case "$digits" in
        ''|*[!0-9]*)
            echo "Stick values must be decimal integers." >&2
            exit 2
            ;;
    esac
    if [ "$value" -lt -128 ] || [ "$value" -gt 127 ]; then
        echo "Stick values must be between -128 and 127." >&2
        exit 2
    fi
done

case "$pad_reads" in
    ''|*[!0-9]*)
        echo "PADRead count must be a decimal integer." >&2
        exit 2
        ;;
esac
if [ "$pad_reads" -lt 1 ] || [ "$pad_reads" -gt 10000 ]; then
    echo "PADRead count must be between 1 and 10000." >&2
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
    '')     ;;
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

attempt=1
while :; do
    if [ -n "$button" ]; then
        output=$(lldb --batch -p "$pid" \
            -o "breakpoint set --name PADRead --ignore-count $pad_reads --one-shot true" \
            -o "expression -- (void)pc_pad_set_virtual_state(0, $stick_x, $stick_y, 0, 0, 0, 0)" \
            -o continue \
            -o "expression -- (void)pc_pad_clear_virtual_state()" \
            -o "expression -- (void)pc_pad_queue_scancode($scancode)" \
            -o detach 2>&1) && succeeded=1 || succeeded=0
    else
        output=$(lldb --batch -p "$pid" \
            -o "breakpoint set --name PADRead --ignore-count $pad_reads --one-shot true" \
            -o "expression -- (void)pc_pad_set_virtual_state(0, $stick_x, $stick_y, 0, 0, 0, 0)" \
            -o continue \
            -o "expression -- (void)pc_pad_clear_virtual_state()" \
            -o detach 2>&1) && succeeded=1 || succeeded=0
    fi

    if [ "$succeeded" -eq 1 ]; then
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
