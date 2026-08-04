#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 APP_BUNDLE" >&2
    exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
app=$1
source_icon="$repo_root/apple/ios/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
resources="$app/Contents/Resources"
plist="$app/Contents/Info.plist"

test -f "$source_icon"
test -f "$plist"

icon_width=$(sips -g pixelWidth "$source_icon" | awk '/pixelWidth:/ { print $2 }')
icon_height=$(sips -g pixelHeight "$source_icon" | awk '/pixelHeight:/ { print $2 }')
icon_alpha=$(sips -g hasAlpha "$source_icon" | awk '/hasAlpha:/ { print $2 }')
if [ "$icon_width" != "1024" ] || [ "$icon_height" != "1024" ] || [ "$icon_alpha" != "no" ]; then
    echo "AppIcon.png must be an opaque 1024x1024 image." >&2
    exit 1
fi

mkdir -p "$resources"

compile_dir=$(mktemp -d)
cleanup_compile() {
    rm -rf "$compile_dir"
}
trap cleanup_compile EXIT HUP INT TERM
iconset="$compile_dir/Bellpad.iconset"
mkdir -p "$iconset"

make_icon() {
    name=$1
    size=$2
    sips --resampleHeightWidth "$size" "$size" "$source_icon" \
        --out "$iconset/$name" >/dev/null
}

make_icon icon_16x16.png 16
make_icon icon_16x16@2x.png 32
make_icon icon_32x32.png 32
make_icon icon_32x32@2x.png 64
make_icon icon_128x128.png 128
make_icon icon_128x128@2x.png 256
make_icon icon_256x256.png 256
make_icon icon_256x256@2x.png 512
make_icon icon_512x512.png 512
make_icon icon_512x512@2x.png 1024

iconutil --convert icns --output "$resources/Bellpad.icns" "$iconset"
if ! /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile Bellpad" "$plist" 2>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Bellpad" "$plist"
fi
plutil -lint "$plist" >/dev/null
test -s "$resources/Bellpad.icns"
