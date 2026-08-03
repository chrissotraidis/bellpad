# Building

Last updated: 2026-08-03

The repository is not yet buildable as an iOS application. These are the current reproducible research/baseline steps.

## Host

- Apple Silicon Mac
- Xcode 26.6
- CMake 3.27.1
- Ninja 1.13.2
- SDL2 compatibility package 2.32.70
- Homebrew GCC 16.1.0

## Reference baseline

```sh
brew install gcc sdl2 cmake ninja

cmake -S ref/upstream/acgc-64bit/pc \
  -B ref/upstream/acgc-64bit/pc/build-macos-arm64 \
  -G Ninja \
  -DCMAKE_C_COMPILER=/opt/homebrew/bin/gcc-16 \
  -DCMAKE_CXX_COMPILER=/opt/homebrew/bin/g++-16

cmake --build ref/upstream/acgc-64bit/pc/build-macos-arm64
```

Adjust the GCC suffix to the installed Homebrew version. The local retail image must be referenced by an ignored symlink in the output `bin/rom/` directory. Do not copy it into source, documentation, an app bundle, an archive, or an IPA.

Observed result on 2026-08-03: successful ARM64 Mach-O build. `file` and `lipo` both report `arm64`. The executable links Homebrew SDL2 compatibility and libstdc++, plus macOS OpenGL/Cocoa/IOKit. This is a development baseline, not a distributable bundle and not the intended Metal production path.

The locally trimmed image also needs the DVD alignment-tail correction recorded in `WORKLOG.md`: JSystem requests aligned reads, so the compatibility layer must read through the declared file length and zero-fill only the request tail. Without that correction, boot stalls forever while loading the last 56-byte file.

## Planned product build

The intended clean-checkout build will fetch only pinned source dependencies and create a ROM-free macOS/iOS/iPadOS project. Retail data is introduced only after the app launches and the user selects it through Files.

Run the tracked-content safety check before every commit and package build:

```sh
./scripts/audit-tracked-content.sh
```
