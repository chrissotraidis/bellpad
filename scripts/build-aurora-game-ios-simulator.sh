#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
core_dir="$repo_root/ref/upstream/acgc-64bit"
aurora_dir="$repo_root/ref/upstream/aurora"
build_dir=${BELLPAD_AURORA_GAME_IOS_BUILD_DIR:-"$core_dir/pc/build-bellpad-aurora-game-ios-simulator"}
dependency_dir=${BELLPAD_AURORA_IOS_DEPENDENCY_DIR:-"$aurora_dir/build-bellpad-ios-sim-ninja/_deps"}
prefix_map="-ffile-prefix-map=$repo_root=/bellpad -fdebug-prefix-map=$repo_root=/bellpad -fmacro-prefix-map=$repo_root=/bellpad"
case "$repo_root" in
    /private/*)
        repo_root_alias=${repo_root#/private}
        prefix_map="$prefix_map -ffile-prefix-map=$repo_root_alias=/bellpad -fdebug-prefix-map=$repo_root_alias=/bellpad -fmacro-prefix-map=$repo_root_alias=/bellpad"
        ;;
esac

"$script_dir/fetch-desktop-baseline.sh"
"$script_dir/fetch-aurora.sh"

cmake -S "$core_dir/pc" -B "$build_dir" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$prefix_map" \
    -DCMAKE_CXX_FLAGS="$prefix_map" \
    -DCMAKE_OBJC_FLAGS="$prefix_map" \
    -DCMAKE_OBJCXX_FLAGS="$prefix_map" \
    -DBUILD_SHARED_LIBS=OFF \
    -DPNG_SHARED=OFF \
    -DPNG_STATIC=ON \
    -DPNG_FRAMEWORK=OFF \
    -DPNG_TESTS=OFF \
    -DPNG_TOOLS=OFF \
    -DBELLPAD_AURORA_LINK_PROBE=ON \
    -DBELLPAD_AURORA_SOURCE_DIR="$aurora_dir" \
    -DBELLPAD_IOS_INFO_PLIST="$repo_root/apple/ios/Info.plist" \
    -DBELLPAD_PRODUCT_SOURCE_DIR="$repo_root" \
    -DFETCHCONTENT_BASE_DIR="$dependency_dir"
cmake --build "$build_dir" --target ac_aurora --parallel

app="$build_dir/bin/Bellpad.app"
binary="$app/Bellpad"
plist="$app/Info.plist"

"$script_dir/install-ios-app-icon.sh" "$app" iphonesimulator

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
unexpected_runtime=$(printf '%s\n' "$linked_libraries" | awk 'NR > 1 { print $1 }' | rg -v '^(/System/Library/|/usr/lib/)' || true)
if [ -n "$unexpected_runtime" ]; then
    echo "iOS Simulator game target has unbundled runtime dependencies:" >&2
    printf '%s\n' "$unexpected_runtime" >&2
    exit 1
fi
if otool -l "$binary" | grep -q 'cmd LC_RPATH'; then
    echo "iOS Simulator game target contains a build-directory runtime search path." >&2
    exit 1
fi

if find "$app" -type f \( \
    -iname '*.iso' -o -iname '*.gcm' -o -iname '*.ciso' -o -iname '*.rvz' -o \
    -iname '*.gci' -o -iname '*.raw' \) -print -quit | grep -q .; then
    echo "Bellpad.app contains prohibited retail or save data." >&2
    exit 1
fi

echo "Native Aurora/Metal iOS Simulator game bundle: $app"
echo "The bundle contains no disc image; launch normally to choose private supported data through Files."
