#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
core_include="$repo_root/source/acgc-64bit/include"
aurora_include="$repo_root/source/aurora/include"
probe_source="$repo_root/tests/GXAbiProbe.cpp"

if [ ! -f "$core_include/dolphin/gx/GXStruct.h" ]; then
    echo "Playable core headers not found; run ./scripts/fetch-desktop-baseline.sh first." >&2
    exit 1
fi
if [ ! -f "$aurora_include/dolphin/gx/GXStruct.h" ]; then
    echo "Aurora headers not found; run ./scripts/fetch-aurora.sh first." >&2
    exit 1
fi

audit_dir=$(mktemp -d "${TMPDIR:-/tmp}/bellpad-gx-abi.XXXXXX")
trap 'rm -r "$audit_dir"' EXIT HUP INT TERM

c++ -std=c++17 -DTARGET_PC -I"$core_include" "$probe_source" -o "$audit_dir/core-probe"
c++ -std=c++17 -DTARGET_PC -I"$aurora_include" "$probe_source" -o "$audit_dir/aurora-probe"
"$audit_dir/core-probe" > "$audit_dir/core"
"$audit_dir/aurora-probe" > "$audit_dir/aurora"

exact_types="GXRenderModeObj GXColor GXLightObj GXColorS10 GXFogAdjTable GXVtxDescList GXVtxAttrFmtList"
opaque_types="GXTexObj GXTlutObj"
failed=0

for type_name in $exact_types; do
    core_row=$(awk -v type_name="$type_name" '$1 == type_name { print $2 " " $3 }' "$audit_dir/core")
    aurora_row=$(awk -v type_name="$type_name" '$1 == type_name { print $2 " " $3 }' "$audit_dir/aurora")
    if [ "$core_row" != "$aurora_row" ]; then
        echo "$type_name differs: core [$core_row], Aurora [$aurora_row]" >&2
        failed=1
    fi
done

for type_name in $opaque_types; do
    core_size=$(awk -v type_name="$type_name" '$1 == type_name { print $2 }' "$audit_dir/core")
    core_align=$(awk -v type_name="$type_name" '$1 == type_name { print $3 }' "$audit_dir/core")
    aurora_size=$(awk -v type_name="$type_name" '$1 == type_name { print $2 }' "$audit_dir/aurora")
    aurora_align=$(awk -v type_name="$type_name" '$1 == type_name { print $3 }' "$audit_dir/aurora")
    if [ "$core_size" -lt "$aurora_size" ] || [ "$core_align" -lt "$aurora_align" ]; then
        echo "$type_name storage is insufficient: core [$core_size/$core_align], Aurora [$aurora_size/$aurora_align]" >&2
        failed=1
    fi
done

echo "Core GX ABI:"
sed 's/^/  /' "$audit_dir/core"
echo "Aurora GX ABI:"
sed 's/^/  /' "$audit_dir/aurora"

if [ "$failed" -ne 0 ]; then
    exit 1
fi

echo "GX value types match; core opaque-object storage can hold Aurora's implementations."
