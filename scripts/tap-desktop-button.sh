#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <AnimalCrossing-pid> <A|B|X|Y|Start|Z|L|R|DUp|DDown|DLeft|DRight>" >&2
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

lldb --batch -p "$pid" \
    -o "expression -- (void)pc_pad_queue_scancode($scancode)" \
    -o detach
