#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
aurora_dir="$repo_root/ref/upstream/aurora"
platform=${1:-}

usage() {
    echo "usage: $0 macos|ios-simulator" >&2
}

if [ "$platform" != "macos" ] && [ "$platform" != "ios-simulator" ]; then
    usage
    exit 2
fi

"$script_dir/fetch-aurora.sh"

common_args="
    -DCMAKE_BUILD_TYPE=RelWithDebInfo
    -DCMAKE_OSX_ARCHITECTURES=arm64
    -DAURORA_ENABLE_GX=ON
    -DAURORA_ENABLE_DVD=OFF
    -DAURORA_ENABLE_CARD=ON
    -DAURORA_CACHE_USE_ZSTD=OFF
"

if [ "$platform" = "macos" ]; then
    build_dir=${BELLPAD_AURORA_BUILD_DIR:-"$aurora_dir/build-bellpad-macos-arm64"}
    # shellcheck disable=SC2086
    cmake -S "$aurora_dir" -B "$build_dir" -G Ninja $common_args
    cmake --build "$build_dir" --target simple --parallel
    executable="$build_dir/examples/simple"
    file "$executable"
    if ! file "$executable" | grep -q 'arm64'; then
        echo "Expected an arm64 macOS probe executable." >&2
        exit 1
    fi
    echo "Built macOS Aurora Metal probe: $executable"
    exit 0
fi

build_dir=${BELLPAD_AURORA_BUILD_DIR:-"$aurora_dir/build-bellpad-ios-simulator-arm64"}

# Aurora's pinned release provides an iOS-device Dawn archive, not an
# iOS-Simulator archive. Build Dawn from its pinned source dependency. Ninja
# emits the final Dawn static archives correctly; Xcode's object-library path
# at this revision does not.
# shellcheck disable=SC2086
cmake -S "$aurora_dir" -B "$build_dir" -G Ninja $common_args \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_BUILD_TYPE=Release \
    -DAURORA_SDL3_PROVIDER=vendor \
    -DAURORA_DAWN_PROVIDER=vendor \
    -DAURORA_DAWN_LINKAGE=static \
    -DDAWN_BUILD_PROTOBUF=OFF \
    -DTINT_BUILD_IR_BINARY=OFF
cmake --build "$build_dir" --target simple --parallel

app="$build_dir/examples/simple.app"
executable="$app/simple"
plist="$app/Info.plist"
file "$executable"
if ! file "$executable" | grep -q 'arm64'; then
    echo "Expected an arm64 iOS Simulator probe executable." >&2
    exit 1
fi
if ! xcrun vtool -show-build "$executable" | grep -q 'platform IOSSIMULATOR'; then
    echo "Probe is not linked for the iOS Simulator platform." >&2
    exit 1
fi

# Upstream's generic CMake example leaves these generated fields empty. They
# are probe-only metadata and do not define Bellpad's eventual product bundle.
plutil -replace CFBundleIdentifier -string dev.bellpad.aurora-probe "$plist"
plutil -replace CFBundleName -string "Aurora Probe" "$plist"
plutil -replace CFBundleShortVersionString -string 0.1 "$plist"
plutil -replace CFBundleVersion -string 1 "$plist"

echo "Built iOS Simulator Aurora Metal probe: $app"
echo "Install it sequentially on iPhone and iPad with xcrun simctl."
