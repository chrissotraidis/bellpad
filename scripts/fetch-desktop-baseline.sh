#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
baseline_dir="$repo_root/ref/upstream/acgc-64bit"
baseline_url="https://github.com/birabittoh/ACGC-PC-Port.git"
baseline_commit="915fb86ba9a6c2144dabda9143d93af7a3f92be7"

if [ ! -d "$baseline_dir/.git" ]; then
    mkdir -p "$(dirname -- "$baseline_dir")"
    git clone --filter=blob:none --no-checkout "$baseline_url" "$baseline_dir"
    git -C "$baseline_dir" checkout --detach "$baseline_commit"
fi

actual_commit=$(git -C "$baseline_dir" rev-parse HEAD)
if [ "$actual_commit" != "$baseline_commit" ]; then
    echo "Desktop baseline is at $actual_commit; expected $baseline_commit." >&2
    echo "Move or clean $baseline_dir, then retry." >&2
    exit 1
fi

for patch_path in "$repo_root"/patches/pc-port/*.patch; do
    if git -C "$baseline_dir" apply --unidiff-zero --reverse --check "$patch_path" 2>/dev/null; then
        :
    elif git -C "$baseline_dir" apply --unidiff-zero --check "$patch_path" 2>/dev/null; then
        git -C "$baseline_dir" apply --unidiff-zero "$patch_path"
    else
        echo "Patch does not apply cleanly: $patch_path" >&2
        exit 1
    fi
done

echo "Desktop baseline ready at $baseline_dir"
