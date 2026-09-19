#!/bin/sh
set -eu
# Pass a disposable booted Simulator ID. Never targets a hardware app/container.
: "${BELLPAD_TEST_SIMULATOR:?Set BELLPAD_TEST_SIMULATOR to an isolated booted Simulator}"
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir="$repo_root/build/overlay-tests"
app="$build_dir/BellpadOverlayTests.app"
sdl_headers=${BELLPAD_SDL_HEADERS:-"$repo_root/source/aurora/build-bellpad-ios-device-package-ninja/_deps/sdl-src/include"}
mkdir -p "$app"
python3 - "$app/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='dev.bellpad.overlaytests', CFBundleExecutable='OverlayTests', CFBundleName='Bellpad Overlay Tests', CFBundlePackageType='APPL', CFBundleVersion='1', CFBundleShortVersionString='1.0', MinimumOSVersion='17.0', LSRequiresIPhoneOS=True, UIDeviceFamily=[1,2], UILaunchScreen={}, UISupportedInterfaceOrientations=['UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight']),f)
PY
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun clang++ -target arm64-apple-ios17.0-simulator -isysroot "$sdk" \
    -std=c++20 -fobjc-arc -I"$sdl_headers" -I"$repo_root/src/platform" \
    "$repo_root/tests/BellpadOverlayTests.mm" "$repo_root/apple/ios/BellpadDiagnostics.mm" \
    "$repo_root/src/platform/BellpadInput.cpp" "$repo_root/src/platform/BellpadDiscValidator.cpp" \
    "$repo_root/src/platform/BellpadSaveData.cpp" \
    -framework Foundation -framework UIKit -framework GameController -framework UniformTypeIdentifiers \
    -framework AVFAudio -framework CoreGraphics -framework QuartzCore -o "$app/OverlayTests"
codesign --force --sign - "$app"
xcrun simctl install "$BELLPAD_TEST_SIMULATOR" "$app"
container=$(xcrun simctl get_app_container "$BELLPAD_TEST_SIMULATOR" dev.bellpad.overlaytests data)
rm -f "$container/Documents/overlay-tests.json"
xcrun simctl launch --terminate-running-process "$BELLPAD_TEST_SIMULATOR" dev.bellpad.overlaytests
python3 - "$container/Documents/overlay-tests.json" <<'PY'
import json,pathlib,sys,time
p=pathlib.Path(sys.argv[1])
for _ in range(30):
    if p.exists(): break
    time.sleep(1)
assert p.exists(), 'Overlay tests did not finish; inspect Simulator crash log'
result=json.loads(p.read_text()); assert result['passed']; print(result['checks'])
PY
