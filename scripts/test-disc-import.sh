#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir="$repo_root/build/disc-import-tests"
mkdir -p "$build_dir"
xcrun clang++ -std=c++20 -fobjc-arc -Wall -Wextra \
    -I"$repo_root/src/platform" "$repo_root/tests/BellpadDiscImportTests.mm" \
    "$repo_root/src/platform/BellpadDiscValidator.cpp" -framework Foundation \
    -o "$build_dir/disc-import-tests"
"$build_dir/disc-import-tests"
