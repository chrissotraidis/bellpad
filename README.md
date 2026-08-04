# Bellpad

Bellpad is an experimental, native Apple ARM64 source port project for the original US revision of Animal Crossing for Nintendo GameCube. The intended application compiles legally clean reverse-engineered game code for macOS, iOS, and iPadOS. It is not a GameCube emulator and will not embed a WebAssembly/browser port.

<p align="center"><img src="apple/ios/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="160" alt="Bellpad brass handbell app icon"></p>

This repository is ready as a public source release candidate and cross-machine test handoff. The proven ARM64 game core packages as a playable macOS `Bellpad.app`, and the same complete core links through Aurora, SDL3, and Metal as native ARM64 iOS/iPadOS simulator and device apps with Bellpad's UIKit controls. The mobile build imports user-owned raw game data through Files, retains it privately, reaches the title and setup sequence, accepts touch input, connects the real game editor to the native iOS keyboard, persists per-device control and render-resolution settings, and reads/writes Dolphin-compatible GCI saves. The unsigned device IPA is reproducible and audited to contain no retail data. Physical-device runtime, signing, compressed disc formats, broader scene coverage, and multi-hour mobile soak testing remain explicit follow-up work; this is not an App Store release.

## Current status

As of 2026-08-04:

- A pinned 64-bit source-port fork builds locally as a native macOS ARM64 executable.
- The same complete game core now builds as an opt-in ARM64 `Bellpad.app`. It accepts `--disc`, presents a native picker when needed, validates GAFE01 disc 0 revision 0, packages only clean shader resources, and reaches the title loop from an arbitrary working directory.
- The same patched source now builds with both Apple Clang 21 and GCC 16; the Apple Clang binary reaches the correctly rendered 60 FPS title screen.
- The pinned checkout, thirty-one local game-core patches, five Aurora patches, simulator/device builds, and unsigned IPA packaging are reproducible with tracked scripts. Direct product archives are content-hash pinned, and the exact shipped dependency inventory is machine-readable.
- A user-supplied `GAFE01` revision 0 image is validated and read directly without extracting or bundling its assets.
- The desktop baseline renders the title, setup, train, and generated town at 60 FPS and starts 32 kHz stereo audio.
- A trimmed-image aligned-read bug was identified and corrected locally.
- Player and town naming work through the port's native SDL text-input path; a test player entered and moved around a newly generated town.
- A live initialized town created a 467,008-byte GCI through the game's save routine, the macOS app closed cleanly, and a new process reloaded the same Bell/Cove town. iPhone Simulator then loaded that GCI, rewrote it with `.bak1` rotation, and loaded the rewritten file after app relaunch. Bounded repeated app-window lifecycle checks pass; physical-device and long-session validation remain incomplete.
- Aurora is the selected production compatibility layer. The complete game now links natively to Aurora/SDL3, selects Metal on Apple Silicon, validates and reads a private retail image, loads all game archives, starts 32 kHz audio, and reaches the interactive title menu at the fixed 60 Hz simulation rate.
- The initial multi-frame smear was traced to a missing host EFB clear and fixed. Palette/cache repairs and corrected WebGPU front-face winding restore the complete title composition. Explicit N64 color unpacking plus Aurora's polygon-font path now render K.K. and multi-line dialogue with the expected colors and placement. Saved-player iPhone runs rendered returning-player dialogue, the train, Cove station, animated title water, and the title choice UI through Metal; interiors and broader outdoor traversal still require comparison before rendering correctness is claimed broadly.
- The Aurora target has live desktop keyboard mappings and normalized virtual-pad input. The mobile product now links Bellpad's canonical GameCube touch/controller mixer directly; patch 19 pulls its mutex-protected snapshot on the game thread, and short button edges remain latched until one 60 Hz poll consumes them.
- Bellpad-owned clean platform harnesses still build with MetalKit for isolated QA. The production mobile game instead uses SDL3/Aurora's native Metal surface and the same fixed-60-Hz normalized GameCube input boundary.
- The mobile game includes left/C sticks, A/B/X/Y, Z/L/R/Start, D-pad, adaptive compact/expanded layouts, safe-area handling, GameController merging, physical-controller auto-hide on devices, persistent opacity/size/visibility/positions, drag editing/reset, Native/1×/2×/3×/4× render-resolution choices, and the thread-safe game-input snapshot consumed by the Aurora core.
- Native macOS and iOS/iPadOS choosers accept a user-selected file through one shared streamed validator. The current slice recognizes raw ISO/GCM, requires GameCube magic plus `GAFE01` revision 0, accepts only the verified full or exact trimmed size, and SHA-256 checks the complete meaningful payload. On mobile, a valid selection is copied through a staging file to private Application Support, validated again, atomically installed, and used by the real core; the retained copy is reused on relaunch.
- When the real game opens a text editor, the mobile adapter presents a native UIKit first responder and drains UTF-8, Backspace, paste, and Done events on the game thread. The iPhone flow committed exact player name `Bell` and town name `Cove`; iPad also presented and committed through the same native field. Letter writing, dictation/accessibility breadth, and physical-device keyboard behavior remain to be tested.
- The playable macOS bundle still uses the proven SDL2/OpenGL renderer and Application Support. The mobile Aurora game bundle now runs the real core, renderer, audio, touch, persistent control settings, user-facing disc import/change/removal, native-text path, validated GCI import/export, GCI persistence, and compiled original icon on simulator and ARM64 device targets. The audited unsigned IPA contains only the executable, plist, compiled icon renditions, asset catalog, and exact third-party notices. Three-cycle iPhone/iPad Home/resume simulator checks now survive a fixed missing-frame lifecycle race; nod indexing/compressed formats, signing, physical-device runtime, and broader scene/long-session evidence remain.
- The GameCube RTC now derives local time from a subsecond host wall clock plus an overflow-safe monotonic counter, polls for host-clock drift, and rebases on iOS activation, significant-time-change, and timezone-change notifications. Deterministic conversion tests pass and a rebuilt iPhone Home/resume smoke logged a `0.000`-second correction.

See [STATUS.md](docs/STATUS.md), [PLAN.md](docs/PLAN.md), and [WORKLOG.md](docs/WORKLOG.md) for evidence and current blockers.

## Supported platforms

| Platform | Status |
|---|---|
| Apple Silicon macOS | Playable OpenGL `Bellpad.app` reaches a generated town; native Aurora/Metal target renders the full title and correctly displays/advances multi-line K.K. dialogue at 60 Hz |
| iPhone Simulator/device | Simulator pass; native ARM64/Metal device bundle and unsigned IPA build/audit pass; physical-device install/runtime pending |
| iPad Simulator/device | Simulator pass with iPad-specific layout/settings; the same universal device bundle and unsigned IPA build/audit pass; physical-device runtime pending |
| Intel macOS, Windows, Linux | Upstream-reference platforms, not Bellpad release targets |

## Game-data requirements

Bellpad will never include a GameCube image or extracted Nintendo assets. Users must supply their own legally obtained, supported retail data.

The initial compatibility target is:

- Game ID: `GAFE01`
- Region: USA
- Revision: 0

The desktop reference currently recognizes ISO, GCM, and CISO. The intended Aurora/nod-backed application flow also targets RVZ and other formats only after each format has validation and test evidence.

Never add game data to this repository. Root ignore rules cover common disc, extracted-data, and save formats, and `scripts/audit-tracked-content.sh` rejects dangerous tracked paths.

## Game-data import flow

```text
Files picker
→ validate raw header, size, revision, and streamed content fingerprint
→ stage and validate a private Application Support copy
→ atomically install the retained image
→ launch the native game core
```

This flow is runtime-proven on both iPhone and iPad simulators for raw ISO/GCM. A valid retained copy is reused after relaunch; an invalid image leaves the import screen visible with an actionable error and does not replace existing data. The gear menu can request change/reimport while preserving the current image until replacement validates, or explicitly remove the retained image on the next launch. The supported raw image is size-allowlisted and SHA-256 checked while streaming; compressed nod formats remain hardening work. The desktop-game development procedure is documented in [BUILDING.md](docs/BUILDING.md); it uses an ignored symlink to local data and never copies the image into source or a bundle.

## Build instructions

On an Apple Silicon Mac with Xcode 26.6, CMake, Ninja, SDL2, Git, and Homebrew available:

```sh
git clone https://github.com/chrissotraidis/bellpad.git
cd bellpad
brew install cmake ninja sdl2
./scripts/verify-release-candidate.sh
./scripts/build-aurora-game-ios-simulator.sh
```

The first Aurora/Dawn build is large and requires network access. It fetches only pinned upstream source/archive revisions into ignored `ref/upstream/`; no game data is downloaded. Install the resulting universal simulator bundle from `ref/upstream/acgc-64bit/pc/build-bellpad-aurora-game-ios-simulator/bin/Bellpad.app`, launch `dev.bellpad.app`, then select your own supported raw ISO/GCM through Files. Test iPhone first, stop and shut it down, then test iPad.

Run `./scripts/build-playable-macos-app.sh` for the real-game ARM64 macOS baseline, `./scripts/build-aurora-game-ios-device.sh` for the unsigned ARM64 device bundle, or `./scripts/package-unsigned-ipa.sh` to build, strip, audit, and package `dist/Bellpad-unsigned.ipa`. The clean harnesses, Aurora probes, and game-core GX coverage/ABI audits are separately reproducible through [BUILDING.md](docs/BUILDING.md). Apple Clang is the product compiler; GCC 16 remains an optional desktop-core compatibility cross-check.

Before committing or packaging anything, run:

```sh
./scripts/audit-tracked-content.sh
```

That command also validates the mixed-license notice, shipped dependency lock,
and cryptographic archive pins. Binary bundles carry the tracked
`ThirdPartyNotices.txt`; see [LICENSE](LICENSE),
[THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt), and
[product-dependencies.lock.json](product-dependencies.lock.json).

The product build uses Apple Clang for iOS. Native save/reload, isolated Dolphin GCI-folder interchange, save-file UI, sequential simulator, dependency, and package-content gates pass. Physical-device validation, sanitizers, broader gameplay rendering, and long-session memory evidence remain before calling the project production-complete.

## Controls

The desktop reference uses:

| GameCube input | Keyboard |
|---|---|
| A / B | Space / Left Shift |
| X / Y | X / Y |
| Start | Return |
| Z / L / R | Z / Q / E |
| Left stick | W / A / S / D |
| C-stick | Arrow keys |
| D-pad | I / J / K / L |

The native mobile layout has a left analog stick, large A/B buttons, smaller X/Y buttons, Z/L/R/Start, D-pad, and C-stick/camera region. It scales from compact iPhone and resizable-iPad windows to an expanded iPad layout and respects safe areas. The top-right gear opens a native settings panel that stores separate iPhone/iPad opacity, size, visibility, normalized control positions, and render resolution; Move mode supports drag editing and Reset restores that device-class preset. Resolution choices are Native (full drawable resolution) plus 1×, 2×, 3×, and 4× EFB scales. They change only internal rendering sharpness—the game/simulation stays fixed at 60 Hz and cannot be overclocked by this menu. Higher fixed scales may supersample on a device whose drawable is smaller. Physical controllers auto-hide gameplay controls on device while leaving settings available. Touch and GameController states merge through one thread-safe normalized GameCube state using ORed buttons, strongest axes, and maximum analog triggers.

## Branding

Bellpad's original icon uses a brass handbell, teal woven handle, and warm folk-art sunburst. It deliberately avoids official characters, leaves, houses, currency bags, logos, typography, and other recognizable game assets. The opaque full-bleed 1024×1024 source and generation provenance live in `apple/ios/Assets.xcassets/AppIcon.appiconset/`; Apple tooling compiles the iPhone/iPad renditions and derives the complete macOS `.icns` size set during tracked builds.

## Screenshots and video

The tracked repository deliberately does not include retail-derived gameplay screenshots or video. Dated visual/runtime evidence is described in [TESTING.md](docs/TESTING.md); public gameplay media should be captured from a contributor's own legally obtained copy and published separately only after a rights review. The original Bellpad icon above is the repository's release-safe visual preview.

## Native keyboard

The mobile game now observes the real editor lifecycle and presents a native UIKit text field plus an explicit Done control. UIKit queues UTF-8, paste, Backspace, and Done events; the game thread alone drains those events into the existing editor API and character mapping. This path committed exact player name `Bell` and town name `Cove` on iPhone and passed the editor lifecycle on iPad. Letters, passwords, paste backpressure, editor-specific keyboard behavior, and physical-device/accessibility coverage remain.

## Saves

The canonical store is one Dolphin-compatible GCI per save in Application Support. Writes build a sibling temporary file, flush it to stable storage, rotate three backups, atomically rename it into place, and synchronize parent-directory metadata on Apple/POSIX hosts. A live Bell/Cove town produced and reloaded a canonical GCI on macOS; iPhone Simulator loaded that same file, rewrote it with backup rotation, and loaded the rewrite after relaunch. Dolphin 5.0-17995 loaded the exact 467,008-byte file from an isolated GCI Folder, and Bellpad then installed and loaded that Dolphin-managed file before startup. The gear menu exports a validated snapshot through Files and stages imported GAFE01 version 5/6 GCI data only after exact-size, block-count, town-ID, and checksum validation. Real iPhone and iPad Files exports matched the canonical SHA-256 byte-for-byte. Imports install before the next game startup and retain the previous canonical file as a pre-import backup, avoiding replacement of a live in-memory town. A fully UI-driven import selection, the retail save dialogue, recovery UI, and update persistence remain gates. No user save belongs in Git, an app bundle, an IPA, documentation, or fixtures.

## Architecture

```text
UIKit / Files / GCController / AVAudioSession
                    ↓
          Bellpad Apple adapter
                    ↓
       portable compiled game core
                    ↓
 Aurora OS/PAD/DVD/CARD/GX compatibility
                    ↓
       SDL3 + nod + Dawn/WebGPU
                    ↓
                  Metal
```

Animal Crossing's retained N64 display-list layer feeds GameCube GX calls. The proposed graphics path is therefore `N64 GBI → emu64 → GX → Aurora → Dawn/WebGPU → Metal`. Desktop OpenGL is only a temporary behavior oracle.

More detail is in [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Testing

Bellpad does not consider compilation or a blank drawable sufficient. Representative iPhone/iPad button, stick, menu, text, import, and render checks establish the native wrapper; the controls are considered wired after unit coverage and bounded live checks rather than repeated activity-by-activity replay. The broader acceptance matrix still covers town creation, saving/relaunch, RTC, lifecycle transitions, invalid images, long-session memory behavior, and package contents.

iPhone and iPad Simulator sessions will run sequentially, never concurrently. Device-only behavior such as audio routes, Files security scopes, haptics, memory pressure, thermal behavior, and physical controllers requires hardware evidence.

See [TESTING.md](docs/TESTING.md).

## Known issues

- Apple Clang compilation is proven, but the full guest-address/pointer-width audit and sanitizer run are not complete.
- Automated window-key delivery is harness-dependent. Guarded LLDB QA helpers can feed button taps, persistent left-stick values, and alphanumeric text through the same normalized APIs planned for Apple platform adapters.
- Native save creation, atomic replacement, backup rotation, process relaunch, reload, isolated Dolphin GCI-folder interchange, and real Files export now pass. A fully UI-driven GCI import selection, the retail save dialogue, recovery UI, and update persistence remain required.
- A normal macOS window close returned cleanly from the game process. Three bounded iPhone Simulator cycles paused presentation/audio on Home and restored both after activation, and three sequential iPad Home/resume cycles survived with rendering restored. The pinned SDL UIKit startup still reports two unbalanced appearance-transition warnings; real audio-route/interruption, physical-device, and long-session lifecycle testing remain open.
- Host time and timezone rebasing are implemented and deterministic conversion tests pass; Resetti/time-travel behavior and physical-device clock-change notification coverage remain open.
- The real Animal Crossing target now links, renders the complete title composition including animated title water/choice UI, correctly displays and advances multi-line K.K. dialogue, and renders a returning-player train/station scene through Aurora/Metal. Interiors and broader outdoor-town comparison remain open.
- The embedded NES emulator and audio path compile under Aurora, but its legacy OpenGL framebuffer presenter is intentionally disabled; a GX/Metal upload path is still required before NES games can display.
- The iOS/iPadOS real-game bundle, touch UI, native Files import/change/removal, private data retention, relaunch boot, native name-entry path, iPhone GCI rewrite/reload, Dolphin GCI-folder interchange, real save export, bounded background/foreground audio recovery, ARM64 device build, and audited unsigned IPA now pass their current gates. Compressed formats, complete editor coverage, route-interruption proof, signing, and physical-device validation remain pending.

## Research and credits

Primary inspected projects include:

- [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp) — clean matching decompilation, CC0-1.0.
- [flyngmt/ACGC-PC-Port](https://github.com/flyngmt/ACGC-PC-Port) — mature native port, CC0/MIT boundary.
- [birabittoh/ACGC-PC-Port](https://github.com/birabittoh/ACGC-PC-Port) — 64-bit migration used for baseline evidence.
- [encounter/aurora](https://github.com/encounter/aurora) — MIT source-level GameCube/Wii compatibility layer.
- [ACreTeam/forest](https://github.com/ACreTeam/forest) — current official WIP Aurora integration direction.
- [GabeConway/OpenCrossing-Anbernic](https://github.com/GabeConway/OpenCrossing-Anbernic) — ARM handheld reference.
- HarkinianPad — local architecture/UX reference only; its integration code is not assumed reusable.

Exact branches, commits, licensing, provenance, purpose, and disposition are recorded in [RESEARCH.md](docs/RESEARCH.md), [upstreams.lock.json](upstreams.lock.json), and [product-dependencies.lock.json](product-dependencies.lock.json). Full license text for every linked non-system component is included in [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt).

## Legal

Bellpad is unofficial and is not affiliated with or endorsed by Nintendo. Animal Crossing, Nintendo, and GameCube names are used only to describe compatibility. No GameCube image, original copyrighted game asset, leaked source, or unauthorized development material is included.

Users are responsible for supplying their own legally obtained supported game data. See [LEGAL.md](docs/LEGAL.md) and the repository's mixed-license [LICENSE](LICENSE).

## Contributing

Contributions must have clear authorship and a compatible license, preserve the clean-room boundary, avoid retail-derived fixtures, and include reproducible test evidence. Do not submit disc images, extracted assets, saves, credentials, certificates, provisioning profiles, or private keys.

Before opening a change:

1. Read the current plan, architecture, research, legal, and testing documents.
2. Run the tracked-content audit.
3. Build the affected target from a clean configuration.
4. Record the device/OS, exact source revision, image revision (never the image), command, and observable result.
5. Keep dependency pins and license notices exact.

For a source-only release check, run `./scripts/verify-release-candidate.sh`. Before publishing an IPA checkpoint, also run `./scripts/package-unsigned-ipa.sh` twice and compare SHA-256 values.
