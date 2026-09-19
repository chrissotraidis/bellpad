#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
core_dir="$repo_root/source/acgc-64bit"
# Historical name retained for callers; validate maintained production source.
"$script_dir/fetch-desktop-baseline.sh"
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
' "$core_dir/src/static/libforest/emu64/emu64.c"
printf '%s\n' 'Maintained PC source invariant passed.'
