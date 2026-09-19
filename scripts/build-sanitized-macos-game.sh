#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
core_dir="$repo_root/source/acgc-64bit"
build_dir="${BELLPAD_BUILD_DIR:-$core_dir/pc/build-bellpad-sanitized}"
sanitizer_flags='-fsanitize=address,undefined -fno-sanitize=float-cast-overflow -fno-omit-frame-pointer -g'

"$script_dir/fetch-desktop-baseline.sh"

cmake -S "$core_dir/pc" -B "$build_dir" -G Ninja \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DCMAKE_C_FLAGS="$sanitizer_flags" \
    -DCMAKE_CXX_FLAGS="$sanitizer_flags" \
    -DCMAKE_EXE_LINKER_FLAGS='-fsanitize=address,undefined' \
    -DBELLPAD_MACOS_BUNDLE=ON
cmake --build "$build_dir" --parallel

app_path="$build_dir/bin/Bellpad.app"
executable="$app_path/Contents/MacOS/Bellpad"
test -x "$executable"
file "$executable"

if [ "${BELLPAD_SANITIZER_RUN:-0}" != 1 ]; then
    echo "Sanitized macOS game built at $app_path"
    echo "Set BELLPAD_SANITIZER_RUN=1 and BELLPAD_DISC_IMAGE to run it."
    exit 0
fi

if [ -z "${BELLPAD_DISC_IMAGE:-}" ] || [ ! -f "$BELLPAD_DISC_IMAGE" ]; then
    echo "BELLPAD_SANITIZER_RUN=1 requires BELLPAD_DISC_IMAGE to name a regular file." >&2
    exit 1
fi

disc_dir=$(CDPATH= cd -- "$(dirname -- "$BELLPAD_DISC_IMAGE")" && pwd)
disc_path="$disc_dir/$(basename -- "$BELLPAD_DISC_IMAGE")"
profile_dir=$(mktemp -d "${TMPDIR:-/tmp}/bellpad-sanitizer.XXXXXX")
trap 'rm -rf -- "$profile_dir"' EXIT HUP INT TERM

# Apple's CoreGraphics theme parser calls strndup across a framework boundary
# that this macOS ASan runtime cannot safely intercept. LeakSanitizer is also
# unavailable on macOS. All Bellpad/game-core memory interceptors remain active.
asan_options="${ASAN_OPTIONS:+$ASAN_OPTIONS:}abort_on_error=1:detect_leaks=0:check_initialization_order=1:strict_string_checks=1:intercept_strndup=0"
ubsan_options="${UBSAN_OPTIONS:+$UBSAN_OPTIONS:}print_stacktrace=1:halt_on_error=1"

echo "Launching the sanitized game with an isolated temporary profile."
echo "Quit the app normally after reaching the scene under test."
env BELLPAD_DATA_HOME="$profile_dir" \
    ASAN_OPTIONS="$asan_options" \
    UBSAN_OPTIONS="$ubsan_options" \
    "$executable" --disc "$disc_path" --verbose
