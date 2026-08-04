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

baseline_git_dir=$(git -C "$baseline_dir" rev-parse --absolute-git-dir)
patch_state="$baseline_git_dir/bellpad-applied-patches"
patch_lock="$baseline_git_dir/bellpad-patch-lock"
lock_attempt=0
while ! mkdir "$patch_lock" 2>/dev/null; do
    lock_attempt=$((lock_attempt + 1))
    if [ "$lock_attempt" -ge 300 ]; then
        echo "Timed out waiting for the desktop patch lock: $patch_lock" >&2
        echo "If no fetch/build is running, remove that stale lock directory and retry." >&2
        exit 1
    fi
    sleep 0.1
done
trap 'exit 1' HUP INT TERM
trap 'rmdir "$patch_lock" 2>/dev/null || true' EXIT

applied_count=0

set -- "$repo_root"/patches/pc-port/*.patch

# Older Bellpad checkouts predate the state file. If the newest patch can be
# reversed, the complete ordered series is already present; record that state
# without touching the worktree. This also upgrades this repository in place.
if [ ! -f "$patch_state" ]; then
    last_patch=""
    for patch_path in "$@"; do
        last_patch="$patch_path"
    done
    if [ -n "$last_patch" ] &&
       git -C "$baseline_dir" apply --unidiff-zero --reverse --check "$last_patch" 2>/dev/null; then
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
                echo "Previously applied patch changed: $patch_path" >&2
                echo "Move or clean $baseline_dir, then retry." >&2
                exit 1
            fi
        fi
    done
    if [ "$applied_count" -gt "$patch_index" ]; then
        echo "Recorded patch series is longer than the current series." >&2
        echo "Move or clean $baseline_dir, then retry." >&2
        exit 1
    fi
fi

patch_index=0
for patch_path in "$@"; do
    patch_index=$((patch_index + 1))
    if [ "$patch_index" -le "$applied_count" ]; then
        continue
    fi
    if git -C "$baseline_dir" apply --unidiff-zero --check "$patch_path" 2>/dev/null; then
        git -C "$baseline_dir" apply --unidiff-zero "$patch_path"
        git hash-object "$patch_path" >> "$patch_state"
    elif git -C "$baseline_dir" apply --unidiff-zero --reverse --check "$patch_path" 2>/dev/null; then
        git hash-object "$patch_path" >> "$patch_state"
    else
        echo "Patch does not apply cleanly: $patch_path" >&2
        exit 1
    fi
done

echo "Desktop baseline ready at $baseline_dir"
