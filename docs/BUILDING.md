# Building

Last updated: 2026-08-03

The repository now builds a playable macOS game-core bundle, Bellpad-owned Metal/touch integration shells, and pinned Aurora Metal/GX probes. The mobile shell does not yet link the game core.

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

The tracked DVD patch handles trimmed images correctly: JSystem requests aligned reads, so the compatibility layer reads through the declared file length and zero-fills only the request tail. Without that correction, boot stalls forever while loading the last 56-byte file. A second patch queues short keyboard button-down edges in the `SDL_KEYDOWN` case and retains them across the JUT and pad-manager reads that make up one game input update. A third patch removes the blanket 64-bit Clang ban and repairs compiler-diagnosed native-width callback, task-copy, heap, archive, ARAM, retrace-message, allocation, and Famicom pointer paths without widening serialized formats. A fourth ports current upstream's padded structure-actor pool design with a 64-bit-safe slot: `STRUCTURE_ACTOR` is 832 bytes on this host while `SHRINE_ACTOR` is 840 bytes, so the former array stride corrupts the next actor during title scenes. A fifth separates editor begin/end, UTF-8 commit, and editor commands from SDL events so UIKit can target a narrow native text API. A sixth adds persistent normalized virtual-pad state and merges it with physical input using ORed buttons, strongest axes, and maximum analog triggers. A seventh validates the optional e-Reader payload and handles scene-arena allocation failure safely. An eighth restores the NPC-house door approach on the host with a narrow, north-facing fallback rather than widening global interaction distance. A ninth replaces speculative macOS executable bounds with the exact loaded Mach-O range and rejects unrecoverable low texture/TLUT pointers before they can be dereferenced.

The scripts were tested from a fresh ignored checkout on 2026-08-03. The resulting executable indexed the supported local image, loaded 14,495 assets, mounted all three archives, opened 32 kHz stereo audio, and entered the title loop. Shutdown behavior is still harness-dependent and remains an explicit lifecycle test item.

## Playable macOS app baseline

```sh
./scripts/build-playable-macos-app.sh
open ref/upstream/acgc-64bit/pc/build-bellpad-app/bin/Bellpad.app
```

This opt-in build packages the actual compiled game core as an ARM64 app bundle. If no image was selected with `--disc PATH` and none is found by the legacy search, it presents a native `NSOpenPanel`. The core accepts only GAFE01 disc 0 revision 0 and reads the selected image in place. The bundle contains its clean GLSL shaders, executable, and plist only; it never copies the selected image.

The current bundle is an honest Milestone 1 product baseline, not the final architecture: rendering remains SDL2/OpenGL, and settings/saves currently resolve relative to the process working directory instead of Application Support. The latter must be fixed before save/relaunch evidence is considered product evidence.

## Metal/touch integration shells

The current clean shell build contains only Bellpad-authored platform code and Apple frameworks. It creates ROM-free macOS and universal iOS/iPadOS bundles:

```sh
./scripts/build-apple-shell.sh macos
./scripts/build-apple-shell.sh ios-simulator
```

The macOS command also runs the normalized-input unit test. The simulator command verifies an ARM64 `IOSSIMULATOR` Mach-O and validates the product Info.plist. Build products remain under ignored `build/` unless `BELLPAD_APP_BUILD_DIR` selects another ignored directory.

To install the simulator bundle, use `xcrun simctl install <device-uuid> build/ios-simulator-arm64/Bellpad.app` and launch bundle ID `dev.bellpad.app`. Run iPhone first, terminate it, shut that simulator down, and only then boot/run iPad. The intended final build will additionally fetch only pinned source dependencies and introduce retail data only after the app launches and the user selects it through Files.

The built shells include native “Choose Game Data…” buttons. They currently
perform validation only: `.iso` and `.gcm` are checked for the GameCube header,
`GAFE01`, and revision 0, then immediately closed. The selection is not copied,
bookmarked, indexed, or launched. Compressed formats remain intentionally
rejected until the nod-backed reader is linked.

Run the tracked-content safety check before every commit and package build:

```sh
./scripts/audit-tracked-content.sh
```

## Aurora Apple-platform probes

These game-data-free probes validate the selected compatibility layer on Apple
ARM64. They are not Bellpad product targets and do not run Animal Crossing.

```sh
./scripts/build-aurora-platform-probe.sh macos
./scripts/build-aurora-platform-probe.sh ios-simulator
```

Both commands verify pinned Aurora commit
`5027ed63a73dfba28de9eceed00481fb09a19c35`. The macOS probe uses Aurora's
prebuilt Darwin ARM64 Dawn package. The iOS Simulator probe builds Dawn and SDL3
from pinned source dependencies with Ninja because Aurora's released iOS Dawn
archive is device-only. A first simulator build compiles roughly 1,100 units and
can take several minutes; subsequent builds are incremental. Set
`BELLPAD_AURORA_BUILD_DIR` to isolate or reuse a build directory.

The generated upstream example has only probe metadata. Install it with
`xcrun simctl install` and launch `dev.bellpad.aurora-probe`; always terminate
and shut down the iPhone simulator before booting the iPad simulator. The
eventual Bellpad product will own its Info.plist, scenes, safe areas, windowing,
icons, signing, and packaging rather than post-processing an upstream example.

Observed 2026-08-03: macOS selected the Apple M2 Metal adapter and rendered the
GX example. The ARM64 `IOSSIMULATOR` executable selected the Apple iOS simulator
GPU through Metal and rendered on an iPhone 17 Pro simulator, then an iPad Pro
13-inch simulator after the phone was stopped. The iPad used a resizable window,
which correctly exposes product window/layout work still to be implemented.
