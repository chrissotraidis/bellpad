# Building

Last updated: 2026-08-03

The repository is not yet buildable as an iOS application. These are the current reproducible research/baseline steps.

## Host

- Apple Silicon Mac
- Xcode 26.6
- CMake 3.27.1
- Ninja 1.13.2
- SDL2 compatibility package 2.32.70
- Apple Clang 21.0.0 (Xcode default)
- Homebrew GCC 16.1.0 (optional compatibility check)

## Reproducible reference baseline

```sh
brew install sdl2 cmake ninja

./scripts/fetch-desktop-baseline.sh
BELLPAD_DISC_IMAGE="/absolute/path/to/your/Animal Crossing.iso" \
  ./scripts/build-desktop-baseline.sh
```

The fetch script checks out commit `915fb86ba9a6c2144dabda9143d93af7a3f92be7` under ignored `ref/upstream/`, verifies the exact revision, and idempotently applies the tracked compatibility patches. The build script uses Apple Clang by default and verifies that the result is an ARM64 Mach-O. Override `BELLPAD_CC`, `BELLPAD_CXX`, and `BELLPAD_BUILD_DIR` for an independent compiler/configuration.

Optional GCC compatibility build:

```sh
brew install gcc
BELLPAD_CC="$(command -v gcc-16)" \
BELLPAD_CXX="$(command -v g++-16)" \
BELLPAD_BUILD_DIR="$PWD/ref/upstream/acgc-64bit/pc/build-macos-arm64-gcc" \
  ./scripts/build-desktop-baseline.sh
```

`BELLPAD_DISC_IMAGE` is optional at build time. When present, the script resolves the local path and creates an ignored symlink in `bin/rom/`; it does not copy the image. Do not place retail data in source, documentation, an app bundle, an archive, or an IPA.

Observed result on 2026-08-03: both Apple Clang 21.0.0 and GCC 16.1.0 compile all 4,000 build units and link ARM64 Mach-O executables from independent build directories. The Apple Clang executable reaches a correctly rendered 60 FPS title screen. The binaries use SDL2 and macOS OpenGL/Cocoa/IOKit; GCC additionally uses libstdc++. This is a development baseline, not a distributable bundle and not the intended Metal production path.

The tracked DVD patch handles trimmed images correctly: JSystem requests aligned reads, so the compatibility layer reads through the declared file length and zero-fills only the request tail. Without that correction, boot stalls forever while loading the last 56-byte file. A second patch preserves short keyboard button-down edges until `PADRead`, matching the event/state separation required by mobile input. A third patch removes the blanket 64-bit Clang ban and repairs compiler-diagnosed native-width callback, task-copy, heap, archive, ARAM, retrace-message, allocation, and Famicom pointer paths without widening serialized formats. A fourth ports current upstream's padded structure-actor pool design with a 64-bit-safe slot: `STRUCTURE_ACTOR` is 832 bytes on this host while `SHRINE_ACTOR` is 840 bytes, so the former array stride corrupts the next actor during title scenes.

The scripts were tested from a fresh ignored checkout on 2026-08-03. The resulting executable indexed the supported local image, loaded 14,495 assets, mounted all three archives, opened 32 kHz stereo audio, and entered the title loop. Shutdown behavior is still harness-dependent and remains an explicit lifecycle test item.

## Planned product build

The intended clean-checkout build will fetch only pinned source dependencies and create a ROM-free macOS/iOS/iPadOS project. Retail data is introduced only after the app launches and the user selects it through Files.

Run the tracked-content safety check before every commit and package build:

```sh
./scripts/audit-tracked-content.sh
```
