# Bellpad

Bellpad is an experimental, native Apple ARM64 source port project for the original US revision of Animal Crossing for Nintendo GameCube. The intended application compiles legally clean reverse-engineered game code for macOS, iOS, and iPadOS. It is not a GameCube emulator and will not embed a WebAssembly/browser port.

The repository is in active platform integration. It now contains native macOS and universal iOS/iPadOS application shells, but it does not yet contain a playable mobile game build.

## Current status

As of 2026-08-03:

- A pinned 64-bit source-port fork builds locally as a native macOS ARM64 executable.
- The same patched source now builds with both Apple Clang 21 and GCC 16; the Apple Clang binary reaches the correctly rendered 60 FPS title screen.
- The pinned checkout, local patches, and build are now reproducible with tracked scripts.
- A user-supplied `GAFE01` revision 0 image is validated and read directly without extracting or bundling its assets.
- The desktop baseline renders the title, setup, train, and generated town at 60 FPS and starts 32 kHz stereo audio.
- A trimmed-image aligned-read bug was identified and corrected locally.
- Player and town naming work through the port's native SDL text-input path; a test player entered and moved around a newly generated town.
- Save creation/relaunch and app-window lifecycle remain under investigation. The title cleanup invalid-free was traced to an undersized static structure-actor pool and repaired with an upstream-derived host slot layout.
- Aurora is the selected production compatibility-layer candidate, subject to an Animal Crossing GX coverage proof.
- Aurora's pinned GX example now builds and visibly renders through Metal on macOS ARM64 and sequential iPhone/iPad simulators. This proves the compatibility-layer platform path, not Animal Crossing rendering.
- Bellpad-owned macOS and universal iOS/iPadOS bundles now build as native ARM64 applications. They render with MetalKit at a fixed 60 Hz and expose a shared normalized GameCube input boundary.
- The mobile shell includes left/C sticks, A/B/X/Y, Z/L/R/Start, D-pad, adaptive compact/expanded layouts, safe-area handling, a touch visibility override, GameController merging, and physical-controller auto-hide on devices.
- Native macOS and iOS/iPadOS choosers now accept a user-selected file and pass it to a shared header validator. The current slice recognizes raw ISO/GCM, requires GameCube magic plus `GAFE01` revision 0, reads only the first 32 bytes, and neither retains nor copies the image.
- The game core, Aurora renderer, durable disc retention/indexing, compressed image formats, saves, native game text entry, audio, and IPA packaging are not connected to the shell yet.

See [STATUS.md](docs/STATUS.md), [PLAN.md](docs/PLAN.md), and [WORKLOG.md](docs/WORKLOG.md) for evidence and current blockers.

## Supported platforms

| Platform | Status |
|---|---|
| Apple Silicon macOS | Desktop game baseline reaches a generated town; native Bellpad Metal shell builds and launches |
| iPhone Simulator/device | Bellpad ARM64 simulator shell installs, launches, renders, and shows touch controls; game core pending |
| iPad Simulator/device | Same universal shell passes sequentially with adaptive resizable-window controls; game core pending |
| Intel macOS, Windows, Linux | Upstream-reference platforms, not Bellpad release targets |

## Game-data requirements

Bellpad will never include a GameCube image or extracted Nintendo assets. Users must supply their own legally obtained, supported retail data.

The initial compatibility target is:

- Game ID: `GAFE01`
- Region: USA
- Revision: 0

The desktop reference currently recognizes ISO, GCM, and CISO. The intended Aurora/nod-backed application flow also targets RVZ and other formats only after each format has validation and test evidence.

Never add game data to this repository. Root ignore rules cover common disc, extracted-data, and save formats, and `scripts/audit-tracked-content.sh` rejects dangerous tracked paths.

## Planned import flow

```text
Files picker
→ validate header, revision, size, and supported hash
→ retain a security-scoped reference or private Application Support copy
→ index the disc filesystem without bundling assets
→ launch the native game core
```

The native shells now present Apple file choosers and validate a selected raw image header without retaining it. The current desktop-game development procedure is documented in [BUILDING.md](docs/BUILDING.md); it uses an ignored symlink to the local image and never copies the image into source or a bundle.

## Build instructions

To build the Bellpad-owned native shell, run `./scripts/build-apple-shell.sh macos` or `./scripts/build-apple-shell.sh ios-simulator`. The pinned desktop investigation and Aurora Metal probes remain separately reproducible through the scripts in [BUILDING.md](docs/BUILDING.md). Apple Clang is the product compiler; GCC 16 remains an optional desktop-core compatibility cross-check.

Before committing or packaging anything, run:

```sh
./scripts/audit-tracked-content.sh
```

The final build must use Apple Clang for iOS. The initial compiler gate is now passed; the remaining address-model audit, sanitizers, save/reload proof, and mobile platform migration are still required.

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

The first native mobile layout now has a left analog stick, large A/B buttons, smaller X/Y buttons, Z/L/R/Start, D-pad, and C-stick/camera region. It scales from compact iPhone and resizable-iPad windows to an expanded iPad layout, respects safe areas, supports manual hiding, and auto-hides for physical controllers on device. Touch and GameController states merge through a thread-safe normalized GameCube state using ORed buttons, strongest axes, and maximum analog triggers. Layout editing and persistence remain pending.

## Native keyboard

The desktop baseline now exposes editor begin/end, UTF-8 commit, and editor-command functions independently of SDL events. They have been validated across player and town naming and form the narrow interface planned for UIKit names, letters, passwords, and other supported editors. Committed text is translated through the port's existing game-character mapping; product-specific length validation remains to be added.

## Saves

The intended canonical store is one Dolphin-compatible GCI per save in Application Support, with serialized writes, validation, atomic replacement, and rotating backups. Import/export and update persistence must be proven before save compatibility is advertised. No user save belongs in Git, an app bundle, an IPA, documentation, or fixtures.

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

Bellpad does not consider compilation, a blank drawable, the title screen, or character creation sufficient. The acceptance matrix covers town creation, movement, inventory, shops, dialogue, letters, tools, museum, saving/relaunch, RTC, lifecycle transitions, controller reconnect, invalid images, long-session memory behavior, and package contents.

iPhone and iPad Simulator sessions will run sequentially, never concurrently. Device-only behavior such as audio routes, Files security scopes, haptics, memory pressure, thermal behavior, and physical controllers requires hardware evidence.

See [TESTING.md](docs/TESTING.md).

## Known issues

- Apple Clang compilation is proven, but the full guest-address/pointer-width audit and sanitizer run are not complete.
- Automated window-key delivery is harness-dependent. Guarded LLDB QA helpers can feed button taps, persistent left-stick values, and alphanumeric text through the same normalized APIs planned for Apple platform adapters.
- Save creation and relaunch persistence have not yet been completed in the local baseline.
- App-window close and lifecycle teardown still need a clean retest; `SIGTERM` exits the clean scripted build.
- Aurora's Apple Metal/GX example path is proven, but Aurora GX coverage for this game has not yet been demonstrated.
- The iOS/iPadOS shell, first touch UI, native Files chooser, and raw-header validator exist; durable import/indexing, the game core, native game keyboard, and unsigned IPA remain pending.

## Research and credits

Primary inspected projects include:

- [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp) — clean matching decompilation, CC0-1.0.
- [flyngmt/ACGC-PC-Port](https://github.com/flyngmt/ACGC-PC-Port) — mature native port, CC0/MIT boundary.
- [birabittoh/ACGC-PC-Port](https://github.com/birabittoh/ACGC-PC-Port) — 64-bit migration used for baseline evidence.
- [encounter/aurora](https://github.com/encounter/aurora) — MIT source-level GameCube/Wii compatibility layer.
- [ACreTeam/forest](https://github.com/ACreTeam/forest) — current official WIP Aurora integration direction.
- [GabeConway/OpenCrossing-Anbernic](https://github.com/GabeConway/OpenCrossing-Anbernic) — ARM handheld reference.
- HarkinianPad — local architecture/UX reference only; its integration code is not assumed reusable.

Exact branches, commits, licensing, provenance, purpose, and disposition are recorded in [RESEARCH.md](docs/RESEARCH.md) and [upstreams.lock.json](upstreams.lock.json).

## Legal

Bellpad is unofficial and is not affiliated with or endorsed by Nintendo. Animal Crossing, Nintendo, and GameCube names are used only to describe compatibility. No GameCube image, original copyrighted game asset, leaked source, or unauthorized development material is included.

Users are responsible for supplying their own legally obtained supported game data. See [LEGAL.md](docs/LEGAL.md).

## Contributing

Contributions must have clear authorship and a compatible license, preserve the clean-room boundary, avoid retail-derived fixtures, and include reproducible test evidence. Do not submit disc images, extracted assets, saves, credentials, certificates, provisioning profiles, or private keys.

Before opening a change:

1. Read the current plan, architecture, research, legal, and testing documents.
2. Run the tracked-content audit.
3. Build the affected target from a clean configuration.
4. Record the device/OS, exact source revision, image revision (never the image), command, and observable result.
5. Keep dependency pins and license notices exact.
