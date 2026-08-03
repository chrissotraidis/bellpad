#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
platform=${1:-}

case "$platform" in
    macos)
        build_dir=${BELLPAD_APP_BUILD_DIR:-"$repo_root/build/macos-arm64"}
        cmake -S "$repo_root" -B "$build_dir" -G Ninja \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DCMAKE_OSX_ARCHITECTURES=arm64
        cmake --build "$build_dir" --parallel
        ctest --test-dir "$build_dir" --output-on-failure
        app="$build_dir/Bellpad.app"
        executable="$app/Contents/MacOS/Bellpad"
        plist="$app/Contents/Info.plist"
        ;;
    ios-simulator)
        build_dir=${BELLPAD_APP_BUILD_DIR:-"$repo_root/build/ios-simulator-arm64"}
        cmake -S "$repo_root" -B "$build_dir" -G Ninja \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DCMAKE_SYSTEM_NAME=iOS \
            -DCMAKE_OSX_SYSROOT=iphonesimulator \
            -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0
        cmake --build "$build_dir" --parallel
        app="$build_dir/Bellpad.app"
        executable="$app/Bellpad"
        plist="$app/Info.plist"
        if ! xcrun vtool -show-build "$executable" | grep -q 'platform IOSSIMULATOR'; then
            echo "Bellpad executable is not linked for iOS Simulator." >&2
            exit 1
        fi
        ;;
    *)
        echo "usage: $0 macos|ios-simulator" >&2
        exit 2
        ;;
esac

file "$executable"
if ! file "$executable" | grep -q 'arm64'; then
    echo "Expected an Apple ARM64 Bellpad executable." >&2
    exit 1
fi
plutil -lint "$plist"
echo "Built Bellpad native shell: $app"
