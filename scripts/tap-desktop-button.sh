#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <Bellpad-pid> <A|B|X|Y|Start|Z|L|R|DUp|DDown|DLeft|DRight>" >&2
    exit 2
fi

pid=$1
button=$2

case "$pid" in
    ''|*[!0-9]*)
        echo "PID must contain only decimal digits." >&2
        exit 2
        ;;
esac

command_line=$(ps -p "$pid" -o command= 2>/dev/null || true)
case "$command_line" in
    *AnimalCrossing*|*Bellpad.app/Contents/MacOS/Bellpad*) ;;
    *)
        echo "PID $pid is not a running Bellpad desktop game." >&2
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

attempt=1
while :; do
    if output=$(lldb --batch -p "$pid" \
        -o "expression -- (void)pc_pad_queue_scancode($scancode)" \
        -o detach 2>&1); then
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
