#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
aurora_dir="$repo_root/ref/upstream/aurora"
aurora_url="https://github.com/encounter/aurora.git"
aurora_commit="5027ed63a73dfba28de9eceed00481fb09a19c35"

if [ ! -d "$aurora_dir/.git" ]; then
    mkdir -p "$(dirname -- "$aurora_dir")"
    git clone --filter=blob:none --no-checkout "$aurora_url" "$aurora_dir"
    git -C "$aurora_dir" checkout --detach "$aurora_commit"
fi

actual_commit=$(git -C "$aurora_dir" rev-parse HEAD)
if [ "$actual_commit" != "$aurora_commit" ]; then
    echo "Aurora is at $actual_commit; expected $aurora_commit." >&2
    echo "Move or clean $aurora_dir, then retry." >&2
    exit 1
fi

if ! git -C "$aurora_dir" diff --quiet || ! git -C "$aurora_dir" diff --cached --quiet; then
    echo "Aurora has local tracked changes; the platform probe requires the pinned clean tree." >&2
    exit 1
fi

echo "Aurora ready at $aurora_dir"
