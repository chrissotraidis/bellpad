#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
core_dir="$repo_root/source/acgc-64bit"
test_dir="$repo_root/build/pc-rtc-clock-tests"

"$script_dir/fetch-desktop-baseline.sh"
mkdir -p "$test_dir"
/usr/bin/clang -std=c11 -Wall -Wextra -Werror \
    -I"$core_dir/pc/include" \
    "$repo_root/tests/PCRTCClockTests.c" \
    "$core_dir/pc/src/pc_rtc_clock.c" \
    -o "$test_dir/pc_rtc_clock_tests"
"$test_dir/pc_rtc_clock_tests"
