#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
core_dir="$repo_root/ref/upstream/acgc-64bit"
patch_dir="$repo_root/patches/pc-port"
upstream_commit=915fb86ba9a6c2144dabda9143d93af7a3f92be7

"$script_dir/fetch-desktop-baseline.sh"

roundtrip_dir=$(mktemp -d "${TMPDIR:-/tmp}/bellpad-patch-series.XXXXXX")
cleanup() {
    git -C "$core_dir" worktree remove --force "$roundtrip_dir" >/dev/null 2>&1 || true
    rmdir "$roundtrip_dir" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

git -C "$core_dir" worktree add --detach "$roundtrip_dir" "$upstream_commit" >/dev/null

patch_count=0
for patch_path in "$patch_dir"/*.patch; do
    git -C "$roundtrip_dir" apply --unidiff-zero --check "$patch_path"
    git -C "$roundtrip_dir" apply --unidiff-zero "$patch_path"
    patch_count=$((patch_count + 1))
done

test "$patch_count" -gt 0
awk '
    /^void emu64::draw_rectangle/ { in_draw_rectangle = 1; next }
    in_draw_rectangle && /if \(\(\(this->othermode_high & G_CYC_COPY\) == 0/ { in_normal_branch = 1; next }
    in_normal_branch && /GXSetNumTexGens\(2\)/ { restored_two_texgens = 1; next }
    in_normal_branch && /GXSetTexCoordGen\(GX_TEXCOORD1/ {
        if (!restored_two_texgens) exit 1
        verified = 1
        exit
    }
    END { exit(verified ? 0 : 1) }
' "$roundtrip_dir/src/static/libforest/emu64/emu64.c"
printf 'PC patch-series replay passed (%s patches).\n' "$patch_count"
