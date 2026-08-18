#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
aurora_dir="$repo_root/ref/upstream/aurora"
patch_dir="$repo_root/patches/aurora"
upstream_commit=5027ed63a73dfba28de9eceed00481fb09a19c35

"$script_dir/fetch-aurora.sh"

roundtrip_dir=$(mktemp -d "${TMPDIR:-/tmp}/bellpad-aurora-controller.XXXXXX")
test_binary="$roundtrip_dir/controller-reconnect-tests"
cleanup() {
    git -C "$aurora_dir" worktree remove --force "$roundtrip_dir" >/dev/null 2>&1 || true
    rmdir "$roundtrip_dir" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

git -C "$aurora_dir" worktree add --detach "$roundtrip_dir" "$upstream_commit" >/dev/null
for patch_path in "$patch_dir"/*.patch; do
    git -C "$roundtrip_dir" apply --check "$patch_path"
    git -C "$roundtrip_dir" apply "$patch_path"
done

c++ -std=c++20 -Wall -Wextra -Wpedantic -Werror \
    -I"$roundtrip_dir/lib" \
    "$repo_root/tests/BellpadControllerReconnectTests.cpp" \
    -o "$test_binary"
"$test_binary"

printf '%s\n' 'Aurora controller reconnect regression passed.'
