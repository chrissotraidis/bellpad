#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 /path/to/Bellpad.app ios|macos" >&2
    exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
app=$1
platform=$2
source_notice="$repo_root/THIRD_PARTY_NOTICES.txt"

test -d "$app"
test -s "$source_notice"

case "$platform" in
    ios)
        resource_dir="$app"
        ;;
    macos)
        resource_dir="$app/Contents/Resources"
        ;;
    *)
        echo "Unknown Bellpad notice platform: $platform" >&2
        exit 2
        ;;
esac

mkdir -p "$resource_dir"
install -m 0644 "$source_notice" "$resource_dir/ThirdPartyNotices.txt"
cmp -s "$source_notice" "$resource_dir/ThirdPartyNotices.txt"

python3 "$script_dir/build-provenance.py" "$resource_dir/SourceProvenance.json"
