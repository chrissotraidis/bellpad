# Building

Last updated: 2026-08-04

The repository now builds a playable macOS game-core bundle, native Aurora/Metal game targets for macOS, iOS Simulator, and ARM64 iOS devices, an audited unsigned IPA, Bellpad-owned Metal/touch integration shells, and pinned compatibility probes.

For a new checkout, start with:

```sh
brew install cmake ninja ripgrep sdl2
./scripts/verify-release-candidate.sh
./scripts/build-aurora-game-ios-simulator.sh
```

The verification command audits tracked/release content, clones the exact pinned game core into ignored local storage, replays all forty-one patches in an isolated detached worktree, builds and runs the clean native platform tests, exercises the deterministic RTC and NES/GX conversion suites, checks every shell script, and rejects whitespace errors. It requires no retail data. The same command runs on GitHub's Apple ARM64 `macos-15` runner through the pinned [source-release workflow](https://github.com/chrissotraidis/bellpad/actions/workflows/source-release.yml); use that live workflow page as the authoritative clean-checkout result for the current `main`. The simulator build fetches pinned dependencies and may take several minutes on its first Dawn build.

## Host

- Apple Silicon Mac
- Xcode 26.6
- CMake 3.27.1
- Ninja 1.13.2
- ripgrep 15.1.0 (release audits)
- SDL2 compatibility package 2.32.70
- SDL3 3.2.20 for the Aurora target
- Apple Clang 21.0.0 (Xcode default)
- Homebrew GCC 16.1.0 (optional compatibility check)

## Reproducible reference baseline

```sh
brew install sdl2 cmake ninja

./scripts/fetch-desktop-baseline.sh
BELLPAD_DISC_IMAGE="/absolute/path/to/your/Animal Crossing.iso" \
  ./scripts/build-desktop-baseline.sh
```

The fetch script checks out commit `915fb86ba9a6c2144dabda9143d93af7a3f92be7` under ignored `ref/upstream/`, verifies the exact revision, and idempotently applies the ordered compatibility patches. Applied patch hashes are recorded under the ignored checkout's `.git/` directory so later patches may safely modify files introduced by earlier ones; changed historical patches require a clean checkout. The build script uses Apple Clang by default and verifies that the result is an ARM64 Mach-O. Override `BELLPAD_CC`, `BELLPAD_CXX`, and `BELLPAD_BUILD_DIR` for an independent compiler/configuration.

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

The scripts were tested from a fresh ignored checkout on 2026-08-03. The resulting executable indexed the supported local image, loaded 14,495 assets, mounted all three archives, opened 32 kHz stereo audio, and entered the title loop. A later packaged-app run closed normally through its macOS window; mobile lifecycle remains an explicit test item.

### Sanitized Apple Silicon baseline

```sh
./scripts/build-sanitized-macos-game.sh

BELLPAD_SANITIZER_RUN=1 \
BELLPAD_DISC_IMAGE="/absolute/private/path/to/game.iso" \
  ./scripts/build-sanitized-macos-game.sh
```

The first command builds the complete native game with AddressSanitizer and
UndefinedBehaviorSanitizer. The opt-in second command runs it against private
user-owned data with an isolated temporary profile that is deleted at exit.
macOS LeakSanitizer is unavailable, and the script disables only the
`strndup` interceptor at Apple's CoreGraphics theme-parser boundary. It also
excludes `float-cast-overflow`: the original game deliberately wraps many
floating-point angles into signed 16-bit GameCube angle units. Memory, bounds,
alignment, pointer, arithmetic, and the other undefined-behavior checks remain
active.

Observed 2026-08-04: the sanitized build loaded 14,495 assets, started 32 kHz
audio, rendered the complete title, and held it for roughly 1,900 frames without
an AddressSanitizer failure. Patches 33–41 repair the actionable initialization,
native heap alignment, message-width, zero-sized release object, clock-angle,
event sentinel, actor-bank, player-array, and audio-resampler reports found on
the way to that gate. This is a bounded title smoke, not a multi-scene or
multi-hour sanitizer certification.

## Playable macOS app baseline

```sh
./scripts/build-playable-macos-app.sh
open ref/upstream/acgc-64bit/pc/build-bellpad-app/bin/Bellpad.app
```

This opt-in build packages the actual compiled game core as an ARM64 app bundle. If no image was selected with `--disc PATH` and none is found by the legacy search, it presents a native `NSOpenPanel`. The core accepts only GAFE01 disc 0 revision 0 and reads the selected image in place. The bundle contains its clean GLSL shaders, executable, and plist only; it never copies the selected image.

The current bundle is an honest Milestone 1 product baseline, not the final architecture: rendering remains SDL2/OpenGL. On macOS it creates and enters `~/Library/Application Support/Bellpad` before loading settings, keybindings, or `save/card_a`. Set `BELLPAD_DATA_HOME` to an isolated absolute directory for development tests. GCI writes use a durable sibling temp file, three rolling backups, atomic rename, and parent-directory synchronization on Apple/POSIX hosts. An isolated Bell/Cove run created a canonical GCI through the live game-facing routine, closed normally, and loaded it in a fresh process. The tracked button, stick, sequence, and text QA helpers accept either the historical executable name or `Bellpad.app/Contents/MacOS/Bellpad`.

## Native Aurora/Metal game convergence

```sh
./scripts/build-aurora-game-macos.sh
```

This fetches the pinned game and Aurora trees, applies their tracked patches,
builds the complete game at the proven unoptimized core setting, and links an
ARM64 `BellpadAurora` executable against SDL3 and Metal. The script rejects a
binary that links the legacy SDL2 runtime. It contains no game image or extracted
asset; launch it only with a private supported file:

```sh
ref/upstream/acgc-64bit/pc/build-bellpad-aurora-game-macos/bin/BellpadAurora \
  --disc /absolute/private/path/to/game.iso
```

Observed 2026-08-03: a clean target completes 4,258 build actions, selects the Apple
M2 Metal adapter, loads 14,495 assets, opens 32 kHz stereo audio, and reaches an
interactive 60 FPS title menu. Explicit host EFB clearing prevents moving frames
from accumulating; palette, winding, color-channel, and polygon-font fixes produce
the complete title and correctly placed multi-line K.K. dialogue. A later iPhone
product runs also rendered a saved-player train/station sequence on iPhone and
iPad; iPhone continued into the outdoor town and Tom Nook's greeting. The standalone
macOS Aurora target remains an integration target until broader scenes and product services pass.
It also uses the launch working directory rather than the product's Application
Support policy and requires the explicit `--disc` path.

## Aurora game-core compatibility audits

After building the playable app and the macOS Aurora probe, run:

```sh
./scripts/audit-aurora-gx-coverage.sh
./scripts/audit-aurora-gx-abi.sh
```

The coverage audit derives requirements from the compiled game-core objects,
not from a hand-maintained list, and fails if patched `libaurora_gx.a` lacks any
GX/GD import. The ABI audit compiles the same probe once against each header
set; value types must match exactly, while opaque texture/palette storage must
be at least as large and aligned as Aurora's implementation. Observed result:
3,905 objects, 112 required symbols, zero missing; all value types match, with
core/Aurora opaque sizes of 88/64 bytes for `GXTexObj` and 40/40 bytes for
`GXTlutObj`.

## Metal/touch integration shells

The current clean shell build contains only Bellpad-authored platform code and Apple frameworks. It creates ROM-free macOS and universal iOS/iPadOS bundles:

```sh
./scripts/build-apple-shell.sh macos
./scripts/build-apple-shell.sh ios-simulator
```

The macOS command also runs the normalized-input unit test. The simulator command verifies an ARM64 `IOSSIMULATOR` Mach-O and validates the product Info.plist. Build products remain under ignored `build/` unless `BELLPAD_APP_BUILD_DIR` selects another ignored directory.

To install the simulator bundle, use `xcrun simctl install <device-uuid> build/ios-simulator-arm64/Bellpad.app` and launch bundle ID `dev.bellpad.app`. Run iPhone first, terminate it, shut that simulator down, and only then boot/run iPad. The intended final build will additionally fetch only pinned source dependencies and introduce retail data only after the app launches and the user selects it through Files.

## Native Aurora/Metal iOS game bundle

```sh
./scripts/build-aurora-game-ios-simulator.sh
```

This applies the pinned forty-one-patch game series and five-patch Aurora series,
builds Dawn and SDL3 for ARM64 iOS Simulator, and links the complete game core,
Aurora GX/Metal renderer, SDL3 audio, normalized input bridge, and UIKit GameCube
overlay into `Bellpad.app`. The script verifies the Mach-O platform, plist,
Metal linkage, absence of SDL2, and absence of disc/save formats in the bundle.

For automated development, launch may still accept
`--disc /absolute/private/path.iso`; this bypasses the picker and must point into
local private storage. A normal launch with no argument now presents the native
Files import screen. A supported raw ISO/GCM is security-scoped while it is read,
validated, copied to a staging file under private Application Support, validated
again, atomically installed, and then supplied to the real Aurora disc reader.
The app reuses that retained copy on subsequent launches.

Patches 30 and 31 keep Animal Crossing's local-time clock synchronized after long sessions and mobile suspension. The game clock combines a subsecond host wall clock with an overflow-safe monotonic performance counter, checks drift periodically, and rebases on iOS activation, significant-time-change, and timezone-change notifications. `./scripts/test-pc-rtc-clock.sh` covers epoch conversion, timezone offsets, development time overrides, large counters, zero-frequency defense, and nanosecond conversion without using retail data.

Patch 32 presents fixNES output through Aurora GX instead of the excluded OpenGL renderer. `./scripts/test-pc-nes-gx-frame.sh` verifies the visible-row crop, RGB565 red/blue field conversion, big-endian byte order, 4×4 tile ordering, buffer rejection, and final-pixel placement without a retail ROM. The complete macOS, iOS Simulator, and iOS device targets compile and link this path; an actual NES-furniture session remains required runtime evidence.

The top-right gear panel's `Game Data & Saves…` menu can request a replacement
image or removal on the next launch without deleting saves. It also exports a
validated immutable GCI snapshot through Files and stages a validated GCI import
for installation before the next core startup. The previous canonical save is
retained as `DobutsunomoriP_MURA.gci.pre-import`. Dolphin 5.0-17995 has read the
same canonical GCI through an isolated GCI Folder, and Bellpad has installed and
loaded that Dolphin-managed file before startup. Real Files exports pass on both
simulator families. A fully UI-driven iPhone Files import also selected,
validated, staged, and installed a 467,008-byte GCI before normal startup.

Patch 22 connects the core's SDL-independent editor API to Bellpad's native
UIKit text proxy. The proxy is shown only while the game reports an active
editor; UTF-8, intercepted paste, Backspace, and explicit Done are queued from
UIKit and consumed by the game thread. Runtime gates cover exact player and
town names on iPhone plus the same editor lifecycle on iPad. Letters, large
paste backpressure, and editor-specific keyboard configuration remain.

The shared validator checks `.iso` and `.gcm` for the GameCube header, `GAFE01`,
disc 0, revision 0, the exact supported full/trimmed size, and a streamed SHA-256
of the complete meaningful payload. Invalid input remains on the import screen
and cannot replace valid retained data. Nod indexing and compressed-container
support remain intentionally unavailable until their readers and validation
rules are linked and tested.

### Native iOS device bundle and unsigned IPA

```sh
./scripts/build-aurora-game-ios-device.sh
./scripts/package-unsigned-ipa.sh
```

The device build uses Aurora's pinned prebuilt `dawn-ios-arm64` package and
vendored SDL3, then compiles the same complete game core and Bellpad UIKit
adapter for iOS 17 or newer. It compiles the original universal icon source with
Apple `actool`, merges the generated primary-icon metadata, and verifies an
ARM64 Mach-O with platform `IOS`, Metal linkage, a valid product plist, no SDL2,
no non-system dynamic libraries or build-directory `LC_RPATH`, and no disc,
save, or provisioning files in `Bellpad.app`. Mobile third-party libraries are
linked statically; Apple system frameworks and `/usr/lib` libraries remain
dynamic. This is an unsigned build; installation still requires a user-owned
signing identity and provisioning profile outside the repository.

Direct Abseil, SDL3, Dawn source, and Apple Dawn package downloads are now
SHA-256 verified in addition to their exact version/commit pins; the remaining
fetched archives were already hash-pinned. `product-dependencies.lock.json`
records every linked non-system component and `THIRD_PARTY_NOTICES.txt`
reproduces its license. The build installs that notice byte-for-byte into the
app, and `scripts/audit-release-compliance.sh` verifies it independently.

The package script accepts only an iOS device app, removes any incidental code
signature and provisioning profile from its private staging copy, audits both
the staging tree and final archive, normalizes timestamps, and writes the ignored
`dist/Bellpad-unsigned.ipa`. It rejects disc images, known extracted assets,
saves, credentials, certificates, keys, and provisioning material. It never
reads or packages the ignored development disc image. Set
`BELLPAD_SKIP_IOS_DEVICE_BUILD=1` to repackage an already audited device build.

Observed 2026-08-04: the output contains exactly the executable, plist,
`Assets.car`, `AppIcon60x60@2x.png`, `AppIcon76x76@2x~ipad.png`, and the tracked
`ThirdPartyNotices.txt`; it is 13 MiB compressed and targets ARM64 iOS 17.0
through Metal. Source-prefix mapping keeps the checkout location out of
Bellpad-built objects. Two final save-recovery packages produced identical bytes with
SHA-256
`63752da02aeed92f925d2494a49a1537308bdea2a8a0a4af6cd1e4d8a5bffb7a`.

Run the tracked-content safety check before every commit and package build:

```sh
./scripts/audit-tracked-content.sh
```

That command includes the release-compliance audit. It validates both JSON lock
files, required full license sections, archive-hash pins, and (when given an app
path directly) the bundled notice bytes.

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
Bellpad product now owns its Info.plist, safe-area/window policy, original icon
source, asset compilation, and unsigned packaging rather than post-processing
this upstream example. Distribution signing remains intentionally user-owned.

Observed 2026-08-03: macOS selected the Apple M2 Metal adapter and rendered the
GX example. The ARM64 `IOSSIMULATOR` executable selected the Apple iOS simulator
GPU through Metal and rendered on an iPhone 17 Pro simulator, then an iPad Pro
13-inch simulator after the phone was stopped. The iPad used a resizable window,
which correctly exposes product window/layout work still to be implemented.
