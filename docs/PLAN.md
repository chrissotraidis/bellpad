# Bellpad implementation plan

Last updated: 2026-08-03

Bellpad is a native Apple-platform source port. It will not ship an emulator, a WebAssembly build, a retail disc image, or extracted retail assets.

## Evidence-based foundation

- Game code: ACreTeam's CC0 `ac-decomp`, carried through a maintained native-port tree.
- Runnable baseline: the MIT/CC0 `ACGC-PC-Port`, with the `birabittoh` 64-bit migration used to establish macOS ARM64 behavior. The migration has independent reports of boot, town entry, audio, save, and reload on 64-bit systems, including macOS ARM64.
- Final compatibility layer: Aurora (MIT), initially for SDL3/application lifecycle, DVD/nod, PAD, CARD, OS/RTC, VI, MTX, and Metal-backed GX through Dawn/WebGPU.
- Mobile shell: a thin Objective-C++/UIKit layer around a portable C/C++ game target. HarkinianPad is an architecture and UX reference only unless separately licensed code is explicitly contributed.

This selection is now supported by platform, symbol-surface, ABI, source-boundary, executable-link, rendering, and input evidence. The desktop-compiled core requires 112 GX/GD symbols; Bellpad's pinned Aurora patches supply all 112, and compiled probes verify matching value types plus sufficient opaque texture/palette storage. The complete core links to Aurora without SDL2, initializes Metal and SDL3 audio, reads the supported image, renders the complete title composition and correctly placed multi-line K.K. dialogue at 60 Hz, and accepts live input. Water, choices, and representative train/town scenes must still pass before OpenGL is retired.

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
4. [ ] Run from trademark/title through town creation, save, process exit, relaunch, and persistence. Current evidence completes names, train arrival, town generation, house selection, mortgage, inventory/equipment, planting, and two resident introductions. A clean replay also crossed an intermittent low-texture-pointer fault after bounded recovery was added. The first NPC-house transition exposed and now has patches for door reach and null optional-payload allocation; fresh interior, save creation, and relaunch evidence remain.
5. Record rendering, audio, input, RTC, memory, and sanitizer evidence. Rendering, 32 kHz stereo audio, keyboard buttons, analog movement, and desktop text input have initial evidence; RTC, memory, and sanitizers remain.
   The title cleanup overflow is fixed with a padded host structure-actor pool; repeated teardown/reload is now part of the regression set.
   NPC-house entry and scene reinitialization are now explicit regression gates after reproducing an unreachable host door sample and a null e-Reader payload allocation in `play_init`.
6. Rebase or forward-port the 64-bit work onto the current bug-fixed native port.
7. [x] Remove compiler-blocking GCC-only pointer truncation behavior so Apple Clang can compile and run the core. Continue the broader address audit and sanitizer work; compiler acceptance alone is not proof that every guest/native boundary is correct.
8. [x] Package the complete Apple Clang ARM64 core as an opt-in `Bellpad.app` with a native picker, explicit supported-image path, strict GAFE01 disc/revision validation, ROM-free resources, and Application Support settings/save paths. Atomic save backups and in-game save/relaunch proof remain separate gates.

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
   [ ] Choice UI, water, train, town, interiors, inventory, particles, framebuffer effects, and NES output remain.
6. Use Aurora GX after the real core link and scene-rendering gates pass. Keep the existing OpenGL renderer only as a temporary desktop oracle.

GX reaches Metal as: game/JSystem/emu64 GX calls → Aurora GX command processor → WebGPU → Dawn Metal backend → `CAMetalLayer`.

## Milestone 3 — mobile targets and data import

- [x] Generate a native macOS application and a universal iOS/iPadOS application target with real product bundle metadata, MetalKit surfaces, fixed 60 Hz presentation, and a shared portable input library.
- [x] Add the first adaptive GameCube touch overlay and GameController merge. Compact iPhone/resizable-iPad layouts are visually proven; expanded iPad layout, editing, and persistence remain.
- [x] Align the product input mask with GameCube PAD and add a thread-safe pull ABI. The UIKit/GameController side exports a strong snapshot function; patch 19 polls it on the Aurora game thread and supplies a weak fallback while the targets are still separate.
- [x] Add native macOS/iOS document choosers and one shared raw ISO/GCM header validator for GameCube magic, `GAFE01`, and revision 0. The UI presentation and synthetic-header tests pass without selecting retail data.
- Connect the working Aurora game target to the Bellpad-owned Metal/touch product targets after its GX output is correct. The thread-safe input ABI is ready on both sides and desktop keyboard mapping is live; executable ownership, Files flow, lifecycle, bundle paths, and UIKit/Aurora surface ownership are still separate.
- Add hash allowlisting, security-scoped bookmark or Application Support retention, nod indexing, and measured CISO/RVZ support before enabling launch.
- Use a document picker for security-scoped ISO/GCM/CISO/RVZ selection.
- Validate disc header, revision, size, and known supported hashes before retaining data.
- Prefer direct indexed reads through Aurora/nod because it supports compressed formats and avoids duplicating copyrighted data. If measurements show unacceptable random-read latency, build a local, versioned index or extracted cache under Application Support; that cache remains excluded from packages and backups as appropriate.
- Store a bookmark or a private Application Support copy selected by the user. Never place the image in the app bundle.
- Provide actionable invalid-image errors and an explicit remove/reimport flow.

## Milestone 4 — platform services

- Saves: Aurora CARD with GCI-folder mode first; Application Support storage, atomic replacement, rolling backups, checksum validation, and import/export document pickers. Test Dolphin-compatible GCI in both directions. Consider raw-card support after GCI is stable.
- RTC: wall clock plus monotonic time; observe timezone and significant-time-change notifications; preserve GameCube tick conversion without overflow; test Resetti/time-travel behaviors.
- Audio: native SDL3/CoreAudio route with AVAudioSession ownership, interruption/route-change recovery, suspension-safe queues, and no busy-loop while inactive.
- Input: one normalized GameCube state merging touch, GCController/SDL controller, and keyboard sources. Physical-controller connection optionally hides gameplay touch controls.
- Lifecycle: stop presentation and pause safely on resign-active/background; flush saves atomically; recreate drawable/audio resources on foreground; handle memory warnings without discarding live save state.
- Keyboard: native text input for player/town names, letters, passwords, and other supported editors, translating committed text into the game's character encoding with length validation.

## Milestone 5 — touch and adaptive UI

- iPhone: large contextual A/B buttons, smaller X/Y, left stick, shoulders/Z/Start, optional D-pad, and a camera drag region.
- iPad: wider separated controls, larger camera region, and layouts tuned independently from iPhone.
- Persist position, scale, visibility, and opacity per device class and orientation; respect safe areas.
- Add a layout editor, reset presets, controller auto-hide, and accessible labels.
- Route touch and physical input through the same normalization and conflict-resolution layer.

## Milestone 6 — verification and packaging

- Sequential simulator loop: iPhone build/run/stop, then iPad build/run/stop.
- Physical ARM64 device tests for Metal, audio routes, haptics, controller reconnect, Files access, memory pressure, suspension, and thermal behavior.
- Functional matrix in `TESTING.md`, including town creation, inventory, shops, letters, tools, museum, saving, NES, island, and town travel where supported.
- Automated clean-checkout builds, package-content audits, unsigned IPA generation, license collection, and dependency pin checks.
- Long sessions with memory sampling and repeated suspend/resume/save/reload cycles.

## Definition-of-done control

`STATUS.md` maps the requested 26 completion conditions to evidence. A condition is complete only when a reproducible command, log, screenshot, or manual test record demonstrates it.
