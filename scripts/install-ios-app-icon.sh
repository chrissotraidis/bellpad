#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 APP_BUNDLE iphonesimulator|iphoneos" >&2
    exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
app=$1
platform=$2
catalog="$repo_root/apple/ios/Assets.xcassets"
source_icon="$catalog/AppIcon.appiconset/AppIcon.png"
plist="$app/Info.plist"

case "$platform" in
    iphonesimulator|iphoneos) ;;
    *)
        echo "Unsupported asset-catalog platform: $platform" >&2
        exit 2
        ;;
esac

test -d "$app"
test -f "$plist"
test -f "$source_icon"

icon_width=$(sips -g pixelWidth "$source_icon" | awk '/pixelWidth:/ { print $2 }')
icon_height=$(sips -g pixelHeight "$source_icon" | awk '/pixelHeight:/ { print $2 }')
icon_alpha=$(sips -g hasAlpha "$source_icon" | awk '/hasAlpha:/ { print $2 }')
if [ "$icon_width" != "1024" ] || [ "$icon_height" != "1024" ] || [ "$icon_alpha" != "no" ]; then
    echo "AppIcon.png must be an opaque 1024x1024 image." >&2
    exit 1
fi

compile_dir=$(mktemp -d)
cleanup_compile() {
    rm -rf "$compile_dir"
}
trap cleanup_compile EXIT HUP INT TERM
partial_plist="$compile_dir/AppIcon-Info.plist"

xcrun actool \
    --compile "$app" \
    --platform "$platform" \
    --minimum-deployment-target 17.0 \
    --target-device iphone \
    --target-device ipad \
    --app-icon AppIcon \
    --output-partial-info-plist "$partial_plist" \
    --warnings \
    --notices \
    "$catalog" >/dev/null

/usr/libexec/PlistBuddy -c "Delete :CFBundleIcons" "$plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :CFBundleIcons~ipad" "$plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Merge $partial_plist" "$plist"
plutil -lint "$plist" >/dev/null
test -f "$app/Assets.car"

icon_name=$(plutil -extract CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName raw "$plist")
if [ "$icon_name" != "AppIcon" ]; then
    echo "Compiled app icon metadata is missing from $plist." >&2
    exit 1
fi
