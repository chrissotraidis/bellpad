#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
core_dir="$repo_root/ref/upstream/acgc-64bit"
test_dir="$repo_root/build/pc-apple-disc-memory-tests"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "Apple disc-memory tests require macOS; skipping."
    exit 0
fi

"$script_dir/fetch-desktop-baseline.sh"
mkdir -p "$test_dir"
# pc_apple.m carries a pre-existing NSOpenPanel deprecation warning that is out
# of scope for the remembered-disc reference under test.
/usr/bin/clang -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -I"$core_dir/pc/include" \
    "$repo_root/tests/PCAppleDiscMemoryTests.m" \
    "$core_dir/pc/src/pc_apple.m" \
    -framework Foundation -framework AppKit \
    -o "$test_dir/pc_apple_disc_memory_tests"
"$test_dir/pc_apple_disc_memory_tests"
