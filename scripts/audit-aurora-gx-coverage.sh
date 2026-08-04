#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
core_build=${BELLPAD_CORE_BUILD_DIR:-"$repo_root/ref/upstream/acgc-64bit/pc/build-bellpad-app"}
aurora_build=${BELLPAD_AURORA_BUILD_DIR:-"$repo_root/ref/upstream/aurora/build-bellpad-macos-arm64"}
object_root=${BELLPAD_CORE_OBJECT_DIR:-"$core_build/CMakeFiles/ac_pc.dir"}
aurora_gx="$aurora_build/libaurora_gx.a"

if [ ! -d "$object_root" ]; then
    echo "Game-core objects not found at $object_root" >&2
    echo "Build the playable app or Aurora core probe first." >&2
    exit 1
fi

if [ ! -f "$aurora_gx" ]; then
    echo "Aurora GX library not found at $aurora_gx" >&2
    echo "Run ./scripts/build-aurora-platform-probe.sh macos first." >&2
    exit 1
fi

object_count=$(find "$object_root" -path '*/acgc-64bit/src/*' -name '*.o' | wc -l | tr -d ' ')
if [ "$object_count" -eq 0 ]; then
    echo "No compiled game-core objects found under $object_root" >&2
    exit 1
fi

audit_dir=$(mktemp -d "${TMPDIR:-/tmp}/bellpad-gx-audit.XXXXXX")
trap 'rm -r "$audit_dir"' EXIT HUP INT TERM

find "$object_root" -path '*/acgc-64bit/src/*' -name '*.o' -print0 |
    xargs -0 nm -u |
    awk '{ symbol=$NF; if (symbol ~ /^_(GX|__GX|GD)/) { sub(/^_/, "", symbol); print symbol } }' |
    LC_ALL=C sort -u > "$audit_dir/required"

nm -gjU "$aurora_gx" |
    awk '{ symbol=$NF; if (symbol ~ /^_(GX|__GX|GD)/) { sub(/^_/, "", symbol); print symbol } }' |
    LC_ALL=C sort -u > "$audit_dir/provided"

comm -23 "$audit_dir/required" "$audit_dir/provided" > "$audit_dir/missing"

required_count=$(wc -l < "$audit_dir/required" | tr -d ' ')
provided_count=$(wc -l < "$audit_dir/provided" | tr -d ' ')
missing_count=$(wc -l < "$audit_dir/missing" | tr -d ' ')

echo "Game-core objects inspected: $object_count"
echo "GX/GD symbols required: $required_count"
echo "GX/GD symbols Aurora provides: $provided_count"
echo "Required symbols missing from Aurora: $missing_count"

if [ "$missing_count" -ne 0 ]; then
    echo "Missing symbols:"
    sed 's/^/  /' "$audit_dir/missing"
    exit 1
fi
