#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
core_dir="$repo_root/source/acgc-64bit"
build_dir=${BELLPAD_AURORA_GAME_IOS_DEVICE_BUILD_DIR:-"$core_dir/pc/build-bellpad-aurora-game-ios-device-package"}
app=${BELLPAD_IOS_DEVICE_APP:-"$build_dir/bin/Bellpad.app"}
output=${BELLPAD_UNSIGNED_IPA_OUTPUT:-"$repo_root/dist/Bellpad-unsigned.ipa"}

if [ "${BELLPAD_SKIP_IOS_DEVICE_BUILD:-0}" != "1" ]; then
    "$script_dir/build-aurora-game-ios-device.sh"
fi

binary="$app/Bellpad"
test -x "$binary"
python3 "$script_dir/audit-ios-deployment.py" "$app"
python3 "$script_dir/build-provenance.py" --verify "$app/SourceProvenance.json"
cmp -s "$repo_root/THIRD_PARTY_NOTICES.txt" "$app/ThirdPartyNotices.txt"
platform=$(xcrun vtool -show-build "$binary" | awk '$1 == "platform" { print $2; exit }')
if [ "$platform" != "IOS" ]; then
    echo "Unsigned IPA input must be an iOS device app, not '$platform'." >&2
    exit 1
fi
linked_libraries=$(otool -L "$binary")
unexpected_runtime=$(printf '%s\n' "$linked_libraries" | awk 'NR > 1 { print $1 }' | rg -v '^(/System/Library/|/usr/lib/)' || true)
if [ -n "$unexpected_runtime" ]; then
    echo "Unsigned IPA input has unbundled runtime dependencies:" >&2
    printf '%s\n' "$unexpected_runtime" >&2
    exit 1
fi
if otool -l "$binary" | grep -q 'cmd LC_RPATH'; then
    echo "Unsigned IPA input contains a build-directory runtime search path." >&2
    exit 1
fi

package_dir=$(mktemp -d)
cleanup_package() {
    rm -rf "$package_dir"
}
trap cleanup_package EXIT HUP INT TERM

mkdir -p "$package_dir/Payload"
ditto "$app" "$package_dir/Payload/Bellpad.app"
package_app="$package_dir/Payload/Bellpad.app"
package_binary="$package_app/Bellpad"

codesign --remove-signature "$package_app" 2>/dev/null || true
rm -f "$package_app/embedded.mobileprovision"
rm -rf "$package_app/_CodeSignature"

forbidden_path_pattern='(^|/)(aram\.bin|audiorom\.img|famicom\.arc|foresta\.map|foresta\.rel\.szs|forest_1st\.arc|forest_2nd\.arc|opening\.bnr|static\.map|static\.str)$|\.(iso|gcm|ciso|rvz|wia|wbfs|gcz|gci|raw|sav|srm|p12|mobileprovision|provisionprofile|cer|key|pem)$|(^|/)\.env($|\.)'
package_matches=$(find "$package_app" -type f -print | sed "s#^$package_dir/##" | rg -i "$forbidden_path_pattern" || true)
if [ -n "$package_matches" ]; then
    echo "Unsigned IPA staging contains prohibited data:" >&2
    printf '%s\n' "$package_matches" >&2
    exit 1
fi

if otool -l "$package_binary" | rg -q 'LC_CODE_SIGNATURE'; then
    echo "Unsigned IPA staging binary still contains a code signature." >&2
    exit 1
fi
cmp -s "$repo_root/THIRD_PARTY_NOTICES.txt" "$package_app/ThirdPartyNotices.txt"
python3 "$script_dir/audit-ios-deployment.py" "$package_app"

find "$package_dir/Payload" -exec touch -h -t 202001010000 {} +
mkdir -p "$(dirname -- "$output")"
archive_tmp="$package_dir/Bellpad-unsigned.ipa"
(
    cd "$package_dir"
    export COPYFILE_DISABLE=1
    find Payload -print | LC_ALL=C sort | zip -X -q "$archive_tmp" -@
)

archive_matches=$(unzip -Z1 "$archive_tmp" | rg -i "$forbidden_path_pattern" || true)
if [ -n "$archive_matches" ]; then
    echo "Unsigned IPA archive contains prohibited data:" >&2
    printf '%s\n' "$archive_matches" >&2
    exit 1
fi
unzip -p "$archive_tmp" Payload/Bellpad.app/ThirdPartyNotices.txt | \
    cmp -s "$repo_root/THIRD_PARTY_NOTICES.txt" -

mv -f "$archive_tmp" "$output"
echo "Audited unsigned IPA: $output"
shasum -a 256 "$output"
