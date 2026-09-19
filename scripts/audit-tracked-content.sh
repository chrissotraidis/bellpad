#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

"$repo_root/scripts/fetch-desktop-baseline.sh"
"$repo_root/scripts/fetch-aurora.sh"

forbidden_path_pattern='(^|/)(aram\.bin|audiorom\.img|famicom\.arc|foresta\.map|foresta\.rel\.szs|forest_1st\.arc|forest_2nd\.arc|opening\.bnr|static\.map|static\.str)$|\.(iso|gcm|ciso|rvz|wia|wbfs|gcz|gci|raw|sav|srm|ipa|xcarchive|p12|mobileprovision|provisionprofile|cer|key|pem)$|(^|/)\.env($|\.)'

tracked_matches=$(git ls-files --recurse-submodules | rg -i "$forbidden_path_pattern" || true)
if [ -n "$tracked_matches" ]; then
  printf '%s\n' 'ERROR: forbidden game data, save, package, signing, or secret paths are tracked:' >&2
  printf '%s\n' "$tracked_matches" >&2
  exit 1
fi

symlink_matches=$(git ls-files -s | awk '$1 == "120000" { print $4 }' | while IFS= read -r tracked_link; do
  link_target=$(git show ":$tracked_link")
  if printf '%s\n' "$link_target" | rg -qi '\.(iso|gcm|ciso|rvz|wia|wbfs|gcz|gci|raw|sav|srm)$'; then
    printf '%s -> %s\n' "$tracked_link" "$link_target"
  fi
done)

if [ -n "$symlink_matches" ]; then
  printf '%s\n' 'ERROR: tracked symlinks target forbidden local data:' >&2
  printf '%s\n' "$symlink_matches" >&2
  exit 1
fi

"$repo_root/scripts/audit-release-compliance.sh"

printf '%s\n' 'Tracked-content audit passed.'
