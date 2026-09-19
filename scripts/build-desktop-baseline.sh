#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
source_dir="$repo_root/source/acgc-64bit/pc"

"$script_dir/fetch-desktop-baseline.sh"

if [ -n "${BELLPAD_CC:-}" ]; then
    c_compiler=$BELLPAD_CC
else
    c_compiler=$(command -v clang || true)
fi
if [ -n "${BELLPAD_CXX:-}" ]; then
    cxx_compiler=$BELLPAD_CXX
else
    cxx_compiler=$(command -v clang++ || true)
fi

if [ -z "$c_compiler" ] || [ -z "$cxx_compiler" ]; then
    echo "Apple Clang is required for the default macOS baseline." >&2
    echo "Install Xcode command-line tools, or set BELLPAD_CC and BELLPAD_CXX." >&2
    exit 1
fi

build_dir=${BELLPAD_BUILD_DIR:-"$source_dir/build-macos-arm64-clang"}

cmake -S "$source_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_C_COMPILER="$c_compiler" \
    -DCMAKE_CXX_COMPILER="$cxx_compiler"
cmake --build "$build_dir"

executable="$build_dir/bin/AnimalCrossing"
file "$executable"
if ! file "$executable" | grep -q 'arm64'; then
    echo "Expected an arm64 desktop executable." >&2
    exit 1
fi

if [ -n "${BELLPAD_DISC_IMAGE:-}" ]; then
    if [ ! -f "$BELLPAD_DISC_IMAGE" ]; then
        echo "BELLPAD_DISC_IMAGE is not a regular file." >&2
        exit 1
    fi
    disc_dir=$(CDPATH= cd -- "$(dirname -- "$BELLPAD_DISC_IMAGE")" && pwd)
    disc_path="$disc_dir/$(basename -- "$BELLPAD_DISC_IMAGE")"
    rom_dir="$build_dir/bin/rom"
    mkdir -p "$rom_dir"
    ln -sfn "$disc_path" "$rom_dir/Animal Crossing.iso"
    echo "Linked local development image outside the build product. It was not copied."
fi

echo "Built $executable"
