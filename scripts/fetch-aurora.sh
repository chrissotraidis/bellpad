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

aurora_git_dir=$(git -C "$aurora_dir" rev-parse --absolute-git-dir)
patch_state="$aurora_git_dir/bellpad-applied-patches"
patch_lock="$aurora_git_dir/bellpad-patch-lock"
lock_attempt=0
while ! mkdir "$patch_lock" 2>/dev/null; do
    lock_attempt=$((lock_attempt + 1))
    if [ "$lock_attempt" -ge 300 ]; then
        echo "Timed out waiting for the Aurora patch lock: $patch_lock" >&2
        echo "If no fetch/build is running, remove that stale lock directory and retry." >&2
        exit 1
    fi
    sleep 0.1
done
trap 'exit 1' HUP INT TERM
trap 'rmdir "$patch_lock" 2>/dev/null || true' EXIT

applied_count=0

set -- "$repo_root"/patches/aurora/*.patch

# Upgrade an older checkout where the complete patch series was applied before
# Bellpad started recording ordered patch hashes.
if [ ! -f "$patch_state" ]; then
    last_patch=""
    for patch_path in "$@"; do
        last_patch="$patch_path"
    done
    if [ -n "$last_patch" ] &&
       git -C "$aurora_dir" apply --reverse --check "$last_patch" 2>/dev/null; then
        for patch_path in "$@"; do
            git hash-object "$patch_path"
        done > "$patch_state"
    fi
fi

if [ -f "$patch_state" ]; then
    applied_count=$(wc -l < "$patch_state" | tr -d ' ')
    patch_index=0
    for patch_path in "$@"; do
        patch_index=$((patch_index + 1))
        if [ "$patch_index" -le "$applied_count" ]; then
            expected_hash=$(sed -n "${patch_index}p" "$patch_state")
            actual_hash=$(git hash-object "$patch_path")
            if [ "$expected_hash" != "$actual_hash" ]; then
                echo "Previously applied Aurora patch changed: $patch_path" >&2
                echo "Move or clean $aurora_dir, then retry." >&2
                exit 1
            fi
        fi
    done
    if [ "$applied_count" -gt "$patch_index" ]; then
        echo "Recorded Aurora patch series is longer than the current series." >&2
        echo "Move or clean $aurora_dir, then retry." >&2
        exit 1
    fi
fi

patch_index=0
for patch_path in "$@"; do
    patch_index=$((patch_index + 1))
    if [ "$patch_index" -le "$applied_count" ]; then
        continue
    fi
    if git -C "$aurora_dir" apply --check "$patch_path" 2>/dev/null; then
        git -C "$aurora_dir" apply "$patch_path"
        git hash-object "$patch_path" >> "$patch_state"
    elif git -C "$aurora_dir" apply --reverse --check "$patch_path" 2>/dev/null; then
        git hash-object "$patch_path" >> "$patch_state"
    else
        echo "Aurora patch does not apply cleanly: $patch_path" >&2
        exit 1
    fi
done

echo "Aurora ready at $aurora_dir"
