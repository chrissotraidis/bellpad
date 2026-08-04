#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

cd "$repo_root"

"$script_dir/audit-tracked-content.sh"
"$script_dir/test-pc-patch-series.sh"
"$script_dir/build-apple-shell.sh" macos
"$script_dir/test-pc-rtc-clock.sh"
"$script_dir/test-pc-nes-gx-frame.sh"

for script in "$script_dir"/*.sh; do
    /bin/sh -n "$script"
done

git diff --check

printf '%s\n' 'Bellpad release-candidate source checks passed.'
