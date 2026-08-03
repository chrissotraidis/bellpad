# Status

Last updated: 2026-08-03

Current phase: desktop-baseline save/pointer-model work.

## Confirmed

- Retail image and nested reference repositories are local and untracked.
- Root ignore rules reject common GameCube image formats, extracted runtime data, saves, Apple build products, packages, signing material, and credentials.
- The local image path is matched by `.gitignore`.
- Xcode 26.6 and an Apple Silicon (`arm64`) host are available.
- The current upstream PC port remains deliberately 32-bit.
- A separate 64-bit migration at commit `915fb86…` documents and has community validation for macOS ARM64, Windows/Linux 64-bit, audio, GCI save, and reload.
- Aurora supports macOS/iOS/tvOS, Metal through Dawn/WebGPU, SDL3, nod-backed disc images including RVZ, controller input, RTC fixes for iOS, and GCI/raw-card storage.
- ACreTeam's current `forest` port already integrates Aurora services, but disables Aurora GX and uses rendering stubs; it is not a playable baseline.
- The pinned 64-bit fork builds locally as a 15.4 MiB ARM64 Mach-O with GCC 16.1.0 and SDL2.
- The local image validates as `GAFE01`, revision 0, with correct GameCube disc magic; its size and SHA-256 are stored only in an ignored local record.
- The baseline reads the image directly, indexes 10 disc files, decompresses the REL, and loads 14,495 assets without extracting them.
- A bug in the desktop DVD shim was reproduced and fixed locally: a 32-byte-aligned read of the final 56-byte file at a trimmed image's physical EOF retried forever. Clamping to the declared file length and zero-filling only the alignment tail unlocks boot.
- After that fix, trademark/title rendering is visually correct at 60 FPS, the renderer submits hundreds of draw calls per frame without GL errors, 32 kHz stereo audio starts, and the game reaches K.K.'s new-game dialogue.
- Message-state tracing showed that K.K. advancement is correct. The apparent stall was a short synthetic key edge falling between pad polls, not a 64-bit message/parser defect.
- A minimal keyboard-edge latch carries non-repeating GameCube button events to the next `PADRead`; with it, all K.K. pages, Rover dialogue, choices, and both name-entry screens advance correctly.
- The desktop SDL text adapter accepted the test player name `Bell` and town name `Cedar` through the in-game editors.
- The full train sequence completed, a new town was generated, the player arrived at the station, exited into town, moved outdoors, met Tom Nook, and reached the house-selection area.
- Tracked scripts now reproduce the pinned checkout, apply both clean compatibility patches idempotently, build an ARM64 Mach-O, and optionally link (never copy) a local image.
- A fresh scripted build was run from an empty ignored checkout and reached the title loop with disc/archive/audio initialization complete. A targeted `SIGTERM` test terminated that clean process.

## Active blockers

- The 64-bit fork relies on GCC accepting pointer-to-`u32` static initializers. Apple Clang rejects them, so further pointer-model work is mandatory for iOS.
- A timing-dependent title transition jumped from action 3 directly to action 6 and triggered an invalid-free panic in the game arena. The normal timed fade path did not reproduce it, so the state-machine/cleanup race remains open.
- The new town has not yet reached its first successful GCI write, controlled in-game exit, and reload, so persistence remains unproven.
- SDL window close/Command-Q and full cleanup still require a clean retest. The earlier instrumented app-wrapper run needed `SIGKILL`, while the fresh scripted executable terminates on `SIGTERM`; the conflicting evidence is kept explicit.
- No Animal Crossing-on-Aurora-GX render has been demonstrated locally.
- No native iOS/iPadOS target exists yet.
- Simulator and physical-device gameplay evidence do not yet exist.

## Requested completion criteria

| # | Criterion | State |
|---|---|---|
| 1 | Clean-checkout build | Partial — pinned desktop reference fetch/build passes; product targets pending |
| 2 | Dependencies pinned/documented | Desktop mechanism passes; product dependency mechanism pending |
| 3 | No leaked source | Policy established; audit pending |
| 4 | User image selection/validation | Local desktop header/hash validation only; native picker pending |
| 5 | Runtime resources produced/loaded | Desktop direct-image load proven; product flow pending |
| 6 | iPhone Simulator installs/launches | Not started |
| 7 | iPad Simulator installs/launches | Not started |
| 8–10 | Title/setup/town entry | Desktop pass — names, train, generated town, and outdoor movement observed |
| 11–21 | Rendering/platform behavior | Desktop rendering/audio/input/text partial pass; saves, RTC, lifecycle, memory, and mobile pending |
| 22 | Reproducible unsigned IPA | Not started |
| 23 | IPA contains no game data | Not started |
| 24 | Original icon/branding | Not started |
| 25 | Accurate README/docs | In progress |
| 26 | Coherent work committed/pushed | Initial safety/research checkpoint pushed; current baseline checkpoint pending |
