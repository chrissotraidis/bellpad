#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir="$repo_root/build/diagnostics-tests"
mkdir -p "$build_dir"
xcrun clang++ -std=c++17 -fobjc-arc -Wall -Wextra -framework Foundation \
    "$repo_root/tests/BellpadDiagnosticsTests.mm" -o "$build_dir/diagnostics-tests"
"$build_dir/diagnostics-tests"
