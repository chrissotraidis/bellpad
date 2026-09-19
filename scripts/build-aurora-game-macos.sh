#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
core_dir="$repo_root/source/acgc-64bit"
aurora_dir="$repo_root/source/aurora"
build_dir=${BELLPAD_AURORA_GAME_BUILD_DIR:-"$core_dir/pc/build-bellpad-aurora-game-macos"}

"$script_dir/fetch-desktop-baseline.sh"
"$script_dir/fetch-aurora.sh"

cmake -S "$core_dir/pc" -B "$build_dir" -G Ninja \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DBELLPAD_AURORA_LINK_PROBE=ON \
    -DBELLPAD_AURORA_SOURCE_DIR="$aurora_dir"
cmake --build "$build_dir" --target ac_aurora --parallel

binary="$build_dir/bin/BellpadAurora"
test -x "$binary"
file "$binary" | grep -q 'Mach-O 64-bit executable arm64'

linked_libraries=$(otool -L "$binary")
printf '%s\n' "$linked_libraries" | grep -q 'SDL3'
printf '%s\n' "$linked_libraries" | grep -q 'Metal.framework'
if printf '%s\n' "$linked_libraries" | grep -q 'SDL2'; then
    echo "Aurora game target unexpectedly links the legacy SDL2 runtime." >&2
    exit 1
fi

echo "Native Aurora/Metal game executable: $binary"
echo "Run with a private supported image: $binary --disc /path/to/game.iso"
