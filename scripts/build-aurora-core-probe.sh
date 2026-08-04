#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
core_dir="$repo_root/ref/upstream/acgc-64bit"
aurora_dir="$repo_root/ref/upstream/aurora"
core_build=${BELLPAD_AURORA_CORE_BUILD_DIR:-"$core_dir/pc/build-bellpad-aurora-core-probe"}
aurora_build=${BELLPAD_AURORA_BUILD_DIR:-"$aurora_dir/build-bellpad-macos-arm64"}
object_root="$core_build/CMakeFiles/ac_aurora_core_probe.dir"
aurora_gx="$aurora_build/libaurora_gx.a"

"$script_dir/fetch-desktop-baseline.sh"
"$script_dir/fetch-aurora.sh"

cmake -S "$core_dir/pc" -B "$core_build" -G Ninja \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DBELLPAD_AURORA_CORE_PROBE=ON
cmake --build "$core_build" --target ac_aurora_core_probe --parallel

if [ ! -f "$aurora_gx" ]; then
    echo "Aurora GX library not found at $aurora_gx" >&2
    echo "Run ./scripts/build-aurora-platform-probe.sh macos first." >&2
    exit 1
fi

audit_dir=$(mktemp -d "${TMPDIR:-/tmp}/bellpad-aurora-core.XXXXXX")
trap 'rm -r "$audit_dir"' EXIT HUP INT TERM

find "$object_root" -type f -name '*.o' -print0 |
    xargs -0 nm -u 2>/dev/null |
    awk '{ print $NF }' |
    LC_ALL=C sort -u > "$audit_dir/undefined"

grep -E '^_?(pc_gx|pc_emu64_frame|s_tlut)' "$audit_dir/undefined" > "$audit_dir/legacy-hooks" || true
if [ -s "$audit_dir/legacy-hooks" ]; then
    echo "Aurora core still imports legacy OpenGL renderer hooks:" >&2
    sed 's/^/  /' "$audit_dir/legacy-hooks" >&2
    exit 1
fi

if ! grep -Eq '^_?AuroraInitTlutObjHost$' "$audit_dir/undefined"; then
    echo "Aurora core did not exercise the host-endian TLUT boundary." >&2
    exit 1
fi
if ! nm -gjU "$aurora_gx" | grep -q '^_AuroraInitTlutObjHost$'; then
    echo "Aurora GX does not provide AuroraInitTlutObjHost." >&2
    exit 1
fi

BELLPAD_CORE_OBJECT_DIR="$object_root" \
BELLPAD_AURORA_BUILD_DIR="$aurora_build" \
    "$script_dir/audit-aurora-gx-coverage.sh"

object_count=$(find "$object_root" -type f -name '*.o' | wc -l | tr -d ' ')
echo "Aurora-defined game core compiled: $object_count objects"
echo "Legacy OpenGL renderer hooks imported: 0"
echo "Host-endian TLUT bridge: resolved by Aurora GX"
