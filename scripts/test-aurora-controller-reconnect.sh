#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
aurora_dir="$repo_root/source/aurora"
"$script_dir/fetch-aurora.sh"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bellpad-controller.XXXXXX")
test_binary="$test_dir/controller-reconnect-tests"
trap 'rm -f "$test_binary"; rmdir "$test_dir"' EXIT HUP INT TERM

c++ -std=c++20 -Wall -Wextra -Wpedantic -Werror \
    -I"$aurora_dir/lib" \
    "$repo_root/tests/BellpadControllerReconnectTests.cpp" \
    -o "$test_binary"
"$test_binary"

printf '%s\n' 'Aurora controller reconnect regression passed.'
