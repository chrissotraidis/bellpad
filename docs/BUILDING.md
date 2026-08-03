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

## Reproducible reference baseline

```sh
brew install gcc sdl2 cmake ninja

./scripts/fetch-desktop-baseline.sh
BELLPAD_DISC_IMAGE="/absolute/path/to/your/Animal Crossing.iso" \
  ./scripts/build-desktop-baseline.sh
```

The fetch script checks out commit `915fb86ba9a6c2144dabda9143d93af7a3f92be7` under ignored `ref/upstream/`, verifies the exact revision, and idempotently applies the tracked compatibility patches. The build script verifies that the result is an ARM64 Mach-O. Set `BELLPAD_CC` and `BELLPAD_CXX` only when the Homebrew compiler names differ.

`BELLPAD_DISC_IMAGE` is optional at build time. When present, the script resolves the local path and creates an ignored symlink in `bin/rom/`; it does not copy the image. Do not place retail data in source, documentation, an app bundle, an archive, or an IPA.

Observed result on 2026-08-03: successful ARM64 Mach-O build. `file` and `lipo` both report `arm64`. The executable links Homebrew SDL2 compatibility and libstdc++, plus macOS OpenGL/Cocoa/IOKit. This is a development baseline, not a distributable bundle and not the intended Metal production path.

The tracked DVD patch handles trimmed images correctly: JSystem requests aligned reads, so the compatibility layer reads through the declared file length and zero-fills only the request tail. Without that correction, boot stalls forever while loading the last 56-byte file. A second patch preserves short keyboard button-down edges until `PADRead`, matching the event/state separation required by mobile input.

The scripts were tested from a fresh ignored checkout on 2026-08-03. The resulting executable indexed the supported local image, loaded 14,495 assets, mounted all three archives, opened 32 kHz stereo audio, and entered the title loop. `SIGTERM` terminated the clean process.

## Planned product build

The intended clean-checkout build will fetch only pinned source dependencies and create a ROM-free macOS/iOS/iPadOS project. Retail data is introduced only after the app launches and the user selects it through Files.

Run the tracked-content safety check before every commit and package build:

```sh
./scripts/audit-tracked-content.sh
```
