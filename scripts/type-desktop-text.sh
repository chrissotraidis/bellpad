#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <AnimalCrossing-pid> <ASCII-alphanumeric-text>" >&2
    exit 2
fi

pid=$1
value=$2

case "$pid" in
    ''|*[!0-9]*)
        echo "PID must contain only decimal digits." >&2
        exit 2
        ;;
esac

case "$value" in
    ''|*[!A-Za-z0-9]*)
        echo "The desktop QA helper accepts non-empty ASCII letters and digits only." >&2
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

attempt=1
while :; do
    if output=$(lldb --batch -p "$pid" \
        -o "expression -- (int)pc_typing_begin()" \
        -o "expression -- (int)pc_typing_commit_utf8(\"$value\")" \
        -o "expression -- (int)pc_typing_command(261)" \
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
