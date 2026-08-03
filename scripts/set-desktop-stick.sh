#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <AnimalCrossing-pid> <x:-128..127> <y:-128..127>" >&2
    exit 2
fi

pid=$1
stick_x=$2
stick_y=$3

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

command_line=$(ps -p "$pid" -o command= 2>/dev/null || true)
case "$command_line" in
    *AnimalCrossing*) ;;
    *)
        echo "PID $pid is not a running AnimalCrossing desktop baseline." >&2
        exit 1
        ;;
esac

attempt=1
while :; do
    if output=$(lldb --batch -p "$pid" \
        -o "expression -- (void)pc_pad_set_virtual_state(0, $stick_x, $stick_y, 0, 0, 0, 0)" \
        -o detach 2>&1); then
        printf '%s\n' "$output"
        break
    fi

    if [ "$attempt" -ge 3 ]; then
        printf '%s\n' "$output" >&2
        exit 1
    fi
    case "$output" in
        *"already being debugged"*) sleep 1 ;;
        *) printf '%s\n' "$output" >&2; exit 1 ;;
    esac
    attempt=$((attempt + 1))
done
