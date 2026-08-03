# Bellpad

Bellpad is an experimental, native Apple ARM64 source port project for the original US revision of Animal Crossing for Nintendo GameCube. The intended application compiles legally clean reverse-engineered game code for macOS, iOS, and iPadOS. It is not a GameCube emulator and will not embed a WebAssembly/browser port.

The repository is in active research and desktop-baseline development. It does not yet contain a playable iPhone or iPad application.

## Current status

As of 2026-08-03:

- A pinned 64-bit source-port fork builds locally as a native macOS ARM64 executable.
- A user-supplied `GAFE01` revision 0 image is validated and read directly without extracting or bundling its assets.
- The desktop baseline renders the title and K.K. new-game scene at 60 FPS and starts 32 kHz stereo audio.
- A trimmed-image aligned-read bug was identified and corrected locally.
- Character/town creation is blocked: the opening K.K. dialogue redraws instead of advancing.
- A title cleanup race and broken controlled-shutdown path remain under investigation.
- Aurora is the selected production compatibility-layer candidate, subject to an Animal Crossing GX coverage proof.
- Native iOS and iPadOS targets, Metal integration, touch controls, Files import, and IPA packaging have not been implemented yet.

See [STATUS.md](docs/STATUS.md), [PLAN.md](docs/PLAN.md), and [WORKLOG.md](docs/WORKLOG.md) for evidence and current blockers.

## Supported platforms

| Platform | Status |
|---|---|
| Apple Silicon macOS | Research baseline builds and reaches new-game dialogue |
| iPhone Simulator/device | Planned; no target yet |
| iPad Simulator/device | Planned; no target yet |
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

The current desktop-only development procedure is documented in [BUILDING.md](docs/BUILDING.md). It uses an ignored symlink to the local image; it never copies the image into source or a bundle.

## Build instructions

There is no product build yet. To reproduce the pinned desktop investigation on Apple Silicon, install CMake, Ninja, SDL2 compatibility, and Homebrew GCC 16, then follow [BUILDING.md](docs/BUILDING.md).

Before committing or packaging anything, run:

```sh
./scripts/audit-tracked-content.sh
```

The final build must use Apple Clang for iOS. Removing the remaining GCC-only pointer-width assumptions is a required desktop milestone, not optional cleanup.

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

The planned mobile layout has a left analog stick, large contextual A/B buttons, smaller X/Y buttons, Z/L/R/Start, optional D-pad, and an optional C-stick or camera-drag region. iPhone and iPad layouts will be tuned and persisted separately. Physical controllers and touch will feed the same normalized GameCube input state, and gameplay controls may auto-hide when a controller connects.

## Native keyboard

Native UIKit text entry is planned for player names, town names, letters, passwords, and other supported editors. Committed text will be length-checked and translated to the game's character encoding. This path is not implemented yet.

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

- The current 64-bit reference needs GCC; Apple Clang rejects remaining pointer-to-`u32` static initialization.
- Opening K.K. dialogue does not advance correctly on the tested macOS baseline.
- One title timing path skips cleanup and reaches an invalid arena free.
- Graceful window/app/process shutdown is currently broken.
- Aurora GX coverage for this game has not yet been demonstrated.
- No iOS/iPadOS app, touch UI, native keyboard, Files import, or unsigned IPA exists yet.

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
