#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
cd "$repo_root"

for required_file in \
    LICENSE \
    THIRD_PARTY_NOTICES.txt \
    upstreams.lock.json \
    product-dependencies.lock.json \
    docs/LEGAL.md \
    docs/RESEARCH.md \
    patches/aurora/0005-pin-fetched-archive-hashes.patch; do
    if [ ! -s "$required_file" ]; then
        echo "Missing release-compliance file: $required_file" >&2
        exit 1
    fi
done

jq empty upstreams.lock.json
jq empty product-dependencies.lock.json

for component in \
    'ACGC-PC-Port game core' \
    'bc7decomp' \
    'Aurora' \
    'Dawn and Tint' \
    'Abseil' \
    'SDL3' \
    'SDL HIDAPI' \
    'SDL yuv2rgb' \
    'fmt' \
    'FreeType' \
    'libpng' \
    'Dear ImGui' \
    'xxHash' \
    'Tracy'; do
    if ! rg -Fq "LICENSE TEXT — $component" THIRD_PARTY_NOTICES.txt; then
        echo "Third-party notice is missing: $component" >&2
        exit 1
    fi
done

for archive_hash in \
    f50e5ac311a81382da7fa75b97310e4b9006474f9560ac46f54a9967f07d4ae3 \
    03ca9de39e1b534c9a443ede66ce8fcf61521edfa7d526f9356972241cbd957d \
    ada0bafc173152d80eba7c3b2f9609a71185d5809cbd5dd3251b91a0803a7ae2 \
    a9cc9903761e60cf70d7d771bd0c482be1943e273717782d71c33313afeb6080 \
    0dc11d980ba17250200718fa4e28011da293f27ed92f92203afffe396811f307; do
    if ! rg -Fq "$archive_hash" patches/aurora/0005-pin-fetched-archive-hashes.patch; then
        echo "Pinned archive hash is missing: $archive_hash" >&2
        exit 1
    fi
done

if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [/path/to/Bellpad.app]" >&2
    exit 2
fi

if [ "$#" -eq 1 ]; then
    app=$1
    if [ -f "$app/ThirdPartyNotices.txt" ]; then
        bundled_notice="$app/ThirdPartyNotices.txt"
    elif [ -f "$app/Contents/Resources/ThirdPartyNotices.txt" ]; then
        bundled_notice="$app/Contents/Resources/ThirdPartyNotices.txt"
    else
        echo "Bellpad app has no bundled ThirdPartyNotices.txt: $app" >&2
        exit 1
    fi
    cmp -s THIRD_PARTY_NOTICES.txt "$bundled_notice"
fi

printf '%s\n' 'Release-compliance audit passed.'
