# Bellpad implementation plan

Last updated: 2026-08-04

Bellpad is a native Apple-platform source port. It will not ship an emulator, a WebAssembly build, a retail disc image, or extracted retail assets.

## Current completion focus

The Apple wrappers are converged: macOS, iPhone, and iPad builds exist; normalized touch/controller input, the gear menu, persistent per-device layouts, Native/1×/2×/3×/4× rendering, Files import, native setup text, GCI persistence, native save/disc management, saved-player train/station rendering on both simulator classes, one iPhone outdoor-town entry, and isolated Dolphin GCI-folder interchange have runtime evidence. Do not spend ongoing implementation time replaying every button across every activity. Finish the product through broader scene/lifecycle hardening, disc-format/release audits, and physical-device validation. The exhaustive activity matrix remains a final acceptance pass.

## Evidence-based foundation

- Game code: ACreTeam's CC0 `ac-decomp`, carried through a maintained native-port tree.
- Runnable baseline: the MIT/CC0 `ACGC-PC-Port`, with the `birabittoh` 64-bit migration used to establish macOS ARM64 behavior. The migration has independent reports of boot, town entry, audio, save, and reload on 64-bit systems, including macOS ARM64.
- Final compatibility layer: Aurora (MIT), initially for SDL3/application lifecycle, DVD/nod, PAD, CARD, OS/RTC, VI, MTX, and Metal-backed GX through Dawn/WebGPU.
- Mobile shell: a thin Objective-C++/UIKit layer around a portable C/C++ game target. HarkinianPad is an architecture and UX reference only unless separately licensed code is explicitly contributed.

This selection is now supported by platform, symbol-surface, ABI, source-boundary, executable-link, rendering, and input evidence. The desktop-compiled core requires 112 GX/GD symbols; Bellpad's pinned Aurora patches supply all 112, and compiled probes verify matching value types plus sufficient opaque texture/palette storage. The complete core links to Aurora without SDL2, initializes Metal and SDL3 audio, reads the supported image, renders the complete title composition, correctly placed multi-line K.K. dialogue, animated title water/choice UI, saved-player train/station scenes on both simulator classes, and an iPhone outdoor-town entry at the fixed 60 Hz cadence, and accepts live input. Interiors, inventory, and broader outdoor comparison remain before OpenGL can be retired as the behavior oracle.

## Milestone 0 — safety, research, and provenance

- [x] Ignore disc images, extracted data, saves, signing material, and packages.
- [x] Clone primary upstream candidates under ignored `ref/upstream/` checkouts.
- [x] Record exact revisions, licensing, purpose, and disposition in `RESEARCH.md`.
- [x] Inspect relevant branches, PRs, issues, ARM/mobile forks, and browser behavior.
- [x] Add an initial Git-index audit that rejects game data, saves, packages, and secrets.

## Milestone 1 — desktop baseline

1. [x] Build the pinned 64-bit port on Apple Silicon with GCC and SDL2.
   Apple Clang 21 and GCC 16 now both complete the independent 4,000-unit ARM64 build; Clang is the default reproducible path.
2. [x] Point it at the local retail image using a symlink; never copy the image into a tracked or packaged tree.
3. [x] Verify the image identity before launch: `GAFE01`, USA Rev 0, and record its size/hash only in an ignored local validation record.
4. [x] Run from trademark/title through town creation, save, process exit, relaunch, and persistence. An isolated Bell/Cove run reached its generated town, invoked the real game-facing save routine from initialized state, wrote a canonical GCI, closed normally, and reloaded the saved-player flow in a new process. iPhone Simulator loaded the same GCI through the shared native core, atomically rewrote it with `.bak1` rotation, and loaded the rewrite after app relaunch. Dolphin 5.0-17995 loaded that canonical file from an isolated GCI Folder, and Bellpad installed and loaded the Dolphin-managed copy before startup. Real Files exports on iPhone and iPad matched it byte-for-byte. Fully UI-driven import selection and the retail save-dialogue interaction remain separate product gates.
5. Record rendering, audio, input, RTC, memory, and sanitizer evidence. Rendering, 32 kHz stereo audio, keyboard buttons, analog movement, desktop text input, host-local RTC initialization, subsecond conversion, and activation rebasing have evidence; Resetti/time-travel behavior, long-session memory, and sanitizers remain.
   The title cleanup overflow is fixed with a padded host structure-actor pool; repeated teardown/reload is now part of the regression set.
   NPC-house entry and scene reinitialization are now explicit regression gates after reproducing an unreachable host door sample and a null e-Reader payload allocation in `play_init`.
6. Rebase or forward-port the 64-bit work onto the current bug-fixed native port.
7. [x] Remove compiler-blocking GCC-only pointer truncation behavior so Apple Clang can compile and run the core. Continue the broader address audit and sanitizer work; compiler acceptance alone is not proof that every guest/native boundary is correct.
8. [x] Package the complete Apple Clang ARM64 core as an opt-in `Bellpad.app` with a native picker, explicit supported-image path, strict GAFE01 disc/revision validation, ROM-free resources, and Application Support settings/save paths. Durable temporary replacement, rolling backups, live save creation, normal close, and process reload pass.

### 64-bit and address model

- Replace host pointers stored in `u32` with `uintptr_t`, typed pointers, or explicit 32-bit guest offsets as appropriate.
- Keep serialized GameCube/N64 structures fixed-width and endian-defined; do not widen on-disc or save formats.
- Represent segmented N64 display-list addresses as 32-bit guest addresses and resolve them through bounded segment tables.
- During baseline migration, recover truncated host values only inside exact arena or loaded-image intervals and reject unknown low texture/TLUT pointers before dereference.
- Replace even the bounded executable-range baseline safeguard with explicit registration of static display-list ranges in the production address model.
- Add compile-time size assertions for serialized structures and runtime bounds checks for every guest-offset resolution.
- Run ASan/UBSan on macOS wherever compatible and make pointer-to-int truncation a compile error.

## Milestone 2 — Aurora rendering spike

1. [x] Build and visibly run Aurora's Metal-backed example for macOS ARM64.
   [x] Build the same pinned GX example for ARM64 iOS Simulator and launch it sequentially on iPhone and iPad simulators. This is a dependency proof, not a Bellpad app pass.
2. [x] Create a minimal Animal Crossing target using Aurora core/VI/MTX/OS/PAD/DVD/CARD. The native ARM64 executable links without SDL2, initializes Metal/SDL3, loads the game, and reaches the title menu.
3. [x] Inventory every GX/GD function called by the game and compare it to Aurora exports. The 3,905 compiled game-core objects require 112 symbols; patched Aurora provides all of them.
   [x] Compile-check the GX host ABI. Value types match exactly; the core's 88-byte `GXTexObj` holds Aurora's 64-byte implementation, and patch 13 expands `GXTlutObj` from 16 to the required 40 bytes.
   [x] Compile the complete game source with the Aurora path enabled and audit undefined symbols. All 3,904 core objects compile, all 111 resulting GX/GD imports resolve, and no `pc_gx_*` or renderer diagnostic globals remain. Host-generated palettes use one explicit `AuroraInitTlutObjHost` extension so byte order is not hidden inside the old OpenGL backend.
4. [x] Feed the title scene's Animal Crossing display lists through Aurora GX. Explicit host EFB clearing removed the accumulated-frame smear; static host-endian palette conversion now matches the dynamic path, cache invalidation is bounded per frame, unsafe draw merging is disabled, and corrected counter-clockwise WebGPU front faces restore the complete scene geometry.
5. Validate correct title, train, outdoor town, interiors, inventory, dialogue, particles, framebuffer effects, and NES output.
   [x] Title composition and multi-line K.K. dialogue match the OpenGL oracle at the fixed 60 Hz cadence.
   [x] Saved-player iPhone and iPad runs visibly completed returning-player dialogue and the train arrival at Cove station through Metal; iPhone additionally exited into the outdoor town and triggered Tom Nook's greeting.
   [x] Choice UI and animated title water render through Metal.
   [ ] Broader outdoor town comparison, iPad outdoor traversal, interiors, inventory, particles, framebuffer effects, and runtime NES output remain. The NES GX/Metal presenter and deterministic tiled-RGB565 tests now compile in every Apple target.
6. Use Aurora GX after the real core link and scene-rendering gates pass. Keep the existing OpenGL renderer only as a temporary desktop oracle.

GX reaches Metal as: game/JSystem/emu64 GX calls → Aurora GX command processor → WebGPU → Dawn Metal backend → `CAMetalLayer`.

## Milestone 3 — mobile targets and data import

- [x] Generate a native macOS application and a universal iOS/iPadOS application target with real product bundle metadata, MetalKit surfaces, fixed 60 Hz presentation, and a shared portable input library.
- [x] Add the adaptive GameCube touch overlay and GameController merge. The real iPhone and iPad game bundle displays compact and expanded layouts over Aurora's Metal surface, with persistent device-class settings and drag editing.
- [x] Align the product input mask with GameCube PAD and add a thread-safe pull ABI. The linked UIKit product exports the strong snapshot consumed by patch 19 on the game thread. Rising button edges are latched until one 60 Hz poll consumes them so short taps cannot disappear between frames.
- [x] Add native macOS/iOS document choosers and one shared streamed raw ISO/GCM validator for GameCube magic, `GAFE01`, revision 0, exact full/trimmed size, and the complete meaningful-payload SHA-256. Synthetic size/hash tests and ignored local-image integration pass without adding retail fixtures.
- [x] Connect the working Aurora game target to a native universal iOS/iPadOS bundle. SDL3/Aurora owns `UIApplicationMain`, lifecycle, and the `CAMetalLayer`; Bellpad attaches a transparent UIKit overlay to that existing view instead of creating a second renderer. The real game reaches title on both simulators, and an iPhone touch A advances into K.K.'s opening.
- [x] Connect the Files picker/validator to durable raw ISO/GCM retention and the real boot path. The importer security-scopes the selected URL, validates source and staged copies, atomically installs `Application Support/Bellpad/Bellpad/Game Data/Animal Crossing.iso`, and reuses it on relaunch. No-data, cancel, invalid, valid import, title boot, exact-copy, and relaunch checks pass sequentially on iPhone and iPad simulators.
- [x] Connect the real mobile editor lifecycle to a native UIKit keyboard proxy and explicit Done control. UTF-8, paste, Backspace, and Done cross a bounded mutex queue and are drained only on the game thread. The iPhone flow committed exact player name `Bell` and town name `Cove`; the same editor lifecycle passed on iPad. Broader editors remain test gates.
- Add hash/size allowlisting, nod indexing, and measured CISO/RVZ support before advertising those formats.
- Extend the security-scoped document picker beyond the currently supported ISO/GCM formats only after each reader is linked and tested.
- Validate disc header, revision, size, and known supported hashes before retaining data.
- Prefer direct indexed reads through Aurora/nod because it supports compressed formats and avoids duplicating copyrighted data. If measurements show unacceptable random-read latency, build a local, versioned index or extracted cache under Application Support; that cache remains excluded from packages and backups as appropriate.
- [x] Store a private Application Support copy selected by the user. Never place the image in the app bundle. A security-scoped bookmark remains an optional future storage-mode alternative.
- [x] Provide actionable invalid-image errors and explicit change/reimport/remove actions. Actions are deferred to startup so an in-use disc image is never deleted underneath the game.

## Milestone 4 — platform services

- Saves: [x] Application Support GCI storage, checksums, durable atomic replacement, recovery, rolling backups, desktop creation/relaunch, iPhone rewrite/relaunch, native import/export document pickers, isolated Dolphin GCI-folder interchange, and real iPhone/iPad Files exports. Imports are validated and staged for pre-boot installation with a pre-import backup; exports use immutable validated snapshots. Exercise the retail save dialogue and complete a fully UI-driven import selection. Consider raw-card support after GCI is stable.
- RTC: [x] Combine a subsecond host wall clock with an overflow-safe monotonic counter, poll for drift, and rebase on iOS activation, significant-time-change, and timezone-change notifications. Deterministic conversion tests and a zero-jump iPhone Home/resume smoke pass. Test Resetti/time-travel behavior and physical-device notification delivery.
- Audio: native SDL3/CoreAudio route with AVAudioSession ownership, interruption/route-change recovery, suspension-safe queues, and no busy-loop while inactive.
- Input: one normalized GameCube state merging touch, GCController/SDL controller, and keyboard sources. Physical-controller connection optionally hides gameplay touch controls.
- Lifecycle: [x] Three bounded iPhone Simulator Home/foreground cycles stop presentation, clear input, pause SDL3 audio, restore Metal output, and resume the stream only after `UIApplicationDidBecomeActive`; three sequential iPad Home/resume cycles also survive and restore visible rendering. Patch 29 prevents the game wrapper from ending an Aurora frame when backgrounding declined to begin one. Audio-route interruption, physical-device, memory-warning, and long-session tests remain. Do not invent an out-of-band gameplay save during suspension.
- Keyboard: extend the proven native player-name path through town names, letters, passwords, and other supported editors; add editor-aware return keys, paste backpressure, length validation, and physical-device/accessibility coverage.

## Milestone 5 — touch and adaptive UI

- iPhone: large contextual A/B buttons, smaller X/Y, left stick, shoulders/Z/Start, optional D-pad, and a camera drag region.
- iPad: wider separated controls, larger camera region, and layouts tuned independently from iPhone.
- [x] Persist position, scale, visibility, and opacity in separate iPhone/iPad profiles; the app is landscape-only and recomputes normalized positions for both supported landscape orientations and resizable safe areas.
- [x] Expose per-device Native, 1×, 2×, 3×, and 4× internal render-resolution choices without changing the fixed 60 Hz simulation cadence.
- [x] Add a drag layout editor, per-device reset, controller auto-hide, and accessible labels.
- [x] Route touch and physical input through the same normalization and conflict-resolution layer.
- [x] Accept representative iPhone/iPad button, stick, layout, settings, and text-entry evidence as the wrapper gate; retain exhaustive gameplay scenarios for release acceptance instead of replaying them for every input change.

## Milestone 6 — verification and packaging

- Sequential simulator loop: iPhone build/run/stop, then iPad build/run/stop.
- Physical ARM64 device tests for Metal, audio routes, haptics, controller reconnect, Files access, memory pressure, suspension, and thermal behavior.
- Functional matrix in `TESTING.md`, including town creation, inventory, shops, letters, tools, museum, saving, NES, island, and town travel where supported.
- [x] Add an ARM64 iOS device build and reproducible unsigned IPA with staging/archive/runtime-link audits. An independent fresh GitHub clone reproduces the package path. Direct product archives are hash-pinned, every linked non-system dependency is locked, and exact third-party notices ship in the app. Signing/install on physical hardware remains.
- [x] Add original bell-centered branding, compile the universal iOS/iPadOS icon through `actool`, derive all macOS `.icns` renditions from the same opaque source, and verify the installed iPhone home-screen result.
- Long sessions with memory sampling and repeated suspend/resume/save/reload cycles.

## Definition-of-done control

`STATUS.md` maps the requested 26 completion conditions to evidence. A condition is complete only when a reproducible command, log, screenshot, or manual test record demonstrates it.
