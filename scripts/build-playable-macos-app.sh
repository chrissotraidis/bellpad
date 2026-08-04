#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
core_dir="$repo_root/ref/upstream/acgc-64bit"
build_dir="${BELLPAD_BUILD_DIR:-$core_dir/pc/build-bellpad-app}"

"$script_dir/fetch-desktop-baseline.sh"

cmake -S "$core_dir/pc" -B "$build_dir" -G Ninja \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_BUILD_TYPE= \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DBELLPAD_MACOS_BUNDLE=ON
cmake --build "$build_dir" --parallel

app_path="$build_dir/bin/Bellpad.app"
"$script_dir/install-macos-app-icon.sh" "$app_path"
test -x "$app_path/Contents/MacOS/Bellpad"
file "$app_path/Contents/MacOS/Bellpad"
plutil -lint "$app_path/Contents/Info.plist"
echo "Playable macOS baseline: $app_path"
