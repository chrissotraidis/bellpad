#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
core_dir="$repo_root/ref/upstream/acgc-64bit"
aurora_dir="$repo_root/ref/upstream/aurora"
build_dir=${BELLPAD_AURORA_GAME_IOS_BUILD_DIR:-"$core_dir/pc/build-bellpad-aurora-game-ios-simulator"}
dependency_dir=${BELLPAD_AURORA_IOS_DEPENDENCY_DIR:-"$aurora_dir/build-bellpad-ios-sim-ninja/_deps"}

"$script_dir/fetch-desktop-baseline.sh"
"$script_dir/fetch-aurora.sh"

cmake -S "$core_dir/pc" -B "$build_dir" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_BUILD_TYPE=Release \
    -DBELLPAD_AURORA_LINK_PROBE=ON \
    -DBELLPAD_AURORA_SOURCE_DIR="$aurora_dir" \
    -DBELLPAD_IOS_INFO_PLIST="$repo_root/apple/ios/Info.plist" \
    -DBELLPAD_PRODUCT_SOURCE_DIR="$repo_root" \
    -DFETCHCONTENT_BASE_DIR="$dependency_dir"
cmake --build "$build_dir" --target ac_aurora --parallel

app="$build_dir/bin/Bellpad.app"
binary="$app/Bellpad"
plist="$app/Info.plist"

test -x "$binary"
file "$binary" | grep -q 'Mach-O 64-bit executable arm64'
xcrun vtool -show-build "$binary" | grep -q 'platform IOSSIMULATOR'
plutil -lint "$plist"

linked_libraries=$(otool -L "$binary")
printf '%s\n' "$linked_libraries" | grep -q 'Metal.framework'
if printf '%s\n' "$linked_libraries" | grep -q 'SDL2'; then
    echo "iOS game target unexpectedly links the legacy SDL2 runtime." >&2
    exit 1
fi

if find "$app" -type f \( \
    -iname '*.iso' -o -iname '*.gcm' -o -iname '*.ciso' -o -iname '*.rvz' -o \
    -iname '*.gci' -o -iname '*.raw' \) -print -quit | grep -q .; then
    echo "Bellpad.app contains prohibited retail or save data." >&2
    exit 1
fi

echo "Native Aurora/Metal iOS Simulator game bundle: $app"
echo "The bundle contains no disc image; launch only with private supported data."
