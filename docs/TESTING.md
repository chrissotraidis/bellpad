# Testing strategy and evidence

Last updated: 2026-08-06

No gameplay test is marked passed without a dated result, device/OS, build revision, image revision, and observable outcome.

## Source-release gate

| Test | Current evidence |
|---|---|
| Clean Apple ARM64 checkout | Pass — the live [source-release workflow](https://github.com/chrissotraidis/bellpad/actions/workflows/source-release.yml) verifies current `main` on a `macos-15` ARM64 runner |
| Retail-data exclusion | Pass — the hosted job receives no disc image, extracted asset, or save and completes the tracked/release-content audits |
| Pinned core reconstruction | Pass — the exact `915fb86…` upstream commit is fetched and all fifty tracked patches pass `git apply --check` and replay in an isolated detached worktree |
| Source checks | Pass — native macOS shell and normalized-input test, deterministic RTC suite, Apple disc-memory suite, NES/GX frame-conversion suite, shell syntax, and whitespace checks |

## Desktop baseline matrix

| Test | Expected | Current evidence |
|---|---|---|
| Configure/build native ARM64 | Mach-O arm64 executable | Pass — 2026-08-03, M2/macOS 26.5; independent full builds with Apple Clang 21.0.0 and GCC 16.1.0 |
| Apple toolchain runtime smoke test | Native binary reaches visible game output | Pass — Apple Clang build rendered the title correctly at 60 FPS using the ignored supported image |
| Validate supported disc | Accept `GAFE01` USA Rev 0 only | Pass for raw ISO/GCM — header/revision, exact full/trimmed size, and streamed meaningful-payload SHA-256 are enforced; compressed formats pending |
| Trademark/title | Correct render/audio/input | Partial pass — correct 60 FPS rendering and 32 kHz stereo; A/Start works through a latched native test path; cleanup overflow fixed; repeatable UI automation pending |
| Character/town creation | Completes with text entry | Pass for baseline — Bell/Cove setup, train, generated town, initialized save state, and saved-player relaunch flow completed; later tutorial breadth is covered by the separate Cedar run |
| Enter town | Stable outdoor rendering and movement | Pass — station exit, outdoor movement, Nook greeting, and housing area observed |
| Save/exit/relaunch | Same town loads from GCI | Pass for native persistence and isolated interchange — live Bell/Cove state wrote a canonical GCI, macOS closed normally and reloaded it; iPhone loaded, rewrote with `.bak1`, terminated, and reloaded the rewrite. Dolphin 5.0-17995 read the file from an isolated GCI Folder, Bellpad installed and loaded the Dolphin-managed copy, real iPhone/iPad Files exports matched it byte-for-byte, and a fully UI-driven iPhone Files import staged and installed the same canonical bytes before normal startup. Retail save UI remains open |
| RTC | Time and date match host | Pass for implementation and simulator-resume gate — fresh setup displayed the expected host-local date/time; deterministic tests cover GameCube epoch, timezone offsets, time overrides, large/zero-frequency counters, and nanoseconds. The rebuilt iPhone product rebased on activation with a logged `0.000`-second adjustment. Resetti/time-travel behavior and physical-device clock/timezone notifications remain pending |
| Sanitizers | Native title path has no memory-safety failure | Partial pass — 2026-08-04, M2/macOS 26.5, Apple Clang 21 ASan/UBSan build loaded disc/assets/audio, rendered the complete title, and held roughly 1,900 frames without an ASan failure after patches 33–41. Legacy signed-angle float-cast diagnostics are excluded from the strict gate; broader scenes and a long soak remain |
| Memory | No unbounded growth during sustained play | Pending |

### Baseline defects reproduced on 2026-08-03

- Trimmed-image EOF: the 56-byte final file is requested as 64 aligned bytes; the original host shim retries forever. A local file-length clamp plus zero-filled alignment tail fixes boot.
- Title cleanup overflow: debugger sampling showed `play_cleanup → Actor_info_dt → Actor_info_delete → zelda_free`, with the invalid pointer inside `aSTR_actor_cl`. Clang record layouts measured `STRUCTURE_ACTOR=832` and `SHRINE_ACTOR=840`; the Shrine tail overwrote the next 832-byte slot. A 0x400-byte host slot, based on current upstream's equivalent 32-bit repair, survives repeated teardown/reload cycles under Apple Clang; GCC also rebuilds.
- Short keyboard edges: synthesized native key taps could end between controller reads. The tracked latch runs in the real key-down case and remains visible to both JUT and pad-manager `PADRead` calls; one injected normalized A edge advanced exactly one K.K. prompt.
- Shutdown evidence differs by harness: app-wrapper sessions have needed SIGKILL, while one targeted raw-process `SIGTERM` test exited. A later Clang wrapper again needed SIGKILL, so window/app teardown remains open.
- NPC-house reach: at Bunnie's active house, the host collision stopped Bell near `z=2175` while the original 20-unit forward sample could not reach the door-label unit. A diagnostic at `z=2138` produced the expected `item_in_front=0xF0A6`. A narrow `TARGET_PC` door-approach fallback compiles under both toolchains; fresh runtime replay is pending.
- Scene-entry allocation: the first NPC-house transition terminated after 2 h 44 min with `EXC_BAD_ACCESS` at `0x2C`. The native stack is `putLEWord → mEA_GetCardDLProgram → play_init`; the optional 9,612-byte e-Reader allocation returned null. Resource/allocation guards compile under both toolchains; fresh runtime replay is pending.
- Low GBI texture pointer: an intermittent Rover train run terminated in `tex_content_hash → GXLoadTexObj → emu64::dirty_check → dl_G_TRIN` while hashing a 32×16 `GX_TF_C8` texture through `0x43C80000`. The old macOS recovery used a speculative image end. In the nine-patch build, LLDB measured the exact image interval as `0x100000000–0x1025C0000`, proved that `0x43C80000` is rejected to null, and proved that truncated arena (`0x11C47D234`) and image (`0x1009E4020`) pointers recover exactly. Both compiler builds and a normal title smoke pass.

### Gameplay evidence on 2026-08-03

- Timing-sensitive evidence is collected only at the normal 60 FPS presentation rate. A short 120 FPS `[2x]` setup run was found to advance gameplay at double speed and is excluded from timing, audio, RTC, memory, save, and stability conclusions.
- Patch 10 removes the F3/F4 2× toggle and hard-locks the coupled VI/game loop to 16,667 microseconds per tick. Apple Clang 21 and GCC 16 ARM64 builds pass; `--framelimit 120` and `--no-framelimit` both exit with status 2 and an acceleration warning, while `--help` exposes only `--framelimit 60`.
- A fresh, quiet (non-verbose) Apple Clang run held 60.0 FPS outside brief LLDB stops and completed K.K./Rover setup, `Bell`/`Cedar` native text entry, train arrival, house selection, the mortgage, Nook's shop entry, uniform equipment, and the complete planting assignment.
- The fresh planting replay consumed all seven flower bags and all three saplings through the retail inventory/context-menu path. The game rejected a paved placement with `You can't plant anything here!`, accepted grass placements, rendered all ten plants, and Nook accepted the completed job.
- The same run returned through Nook's exterior/interior scene transition multiple times without the former low-GBI train fault. The process remained alive after approaching a nearby villager house, but its resident was outdoors and the closed door did not start a scene transition; patches 7 and 8 therefore remain runtime-pending.
- Runtime `g_block_type_p` inspection identified Cedar's generated river bridge, cliff ramp, and beach-river bridge. Normalized input crossed the northern town boundary, descended the four-cell-wide ramp on its collision-grid centerline, and crossed the beach bridge through its three-cell-wide deck. This validates generated-acre navigation and both elevation tiers without modifying player position or save data.
- The corrected-rate run completed first-time dialogue with Purrl and Rex. Resident `is_home` flags were checked read-only before door tests: the last occupied villager transitioned outdoors before arrival and was visibly present beside the house. No closed-door attempt made while all six flags were clear is treated as scene-entry evidence.

- Completed K.K. introduction and all Rover setup dialogue.
- Entered `Bell` and `Cedar` through the desktop text-input adapter.
- Repeated the `Bell`/`Cedar` flow through the new SDL-independent native text API: begin returned success, all characters were queued, Enter was accepted, and the second editor reopened cleanly.
- Completed the train sequence and arrived in the generated town.
- A second clean replay using the native text and normalized-pad APIs crossed the precise dialogue choice preceding the intermittent texture fault and arrived at Cedar station without the fault recurring.
- Exited the station, moved outdoors, met Tom Nook, and reached house selection.
- Selected a house, accepted the mortgage, equipped Nook's work uniform through the inventory, and planted all seven flowers and three saplings. Placement validation rejected paved locations and accepted valid soil.
- Completed first-time resident conversations with Peaches and Chuck. Live quest inspection reported 2 friend records out of 6 starting villagers; Tortimer's work-introduction flag remained unset.
- Rendering and audio remained active throughout; no panic occurred on the normal title path.
- That historical Cedar session ended before creating a GCI. The later isolated Bell/Cove persistence run below supersedes this specific gap without changing the Cedar gameplay evidence.
- The current Computer Use wrapper does not consistently deliver synthesized keys to SDL. The linked Homebrew library is `sdl2-compat`, backed by SDL3, so raw SDL2 event-layout injection is also invalid. For desktop QA, `scripts/tap-desktop-button.sh <pid> A` calls the same normalized queue under LLDB; it deliberately supports buttons only and does not bypass game logic.
- `scripts/type-desktop-text.sh <pid> Bell` validates an explicit game PID, restricts its shell-facing value to ASCII alphanumerics, and calls the same begin/commit/Enter API planned for native keyboard adapters. The underlying API retains the port's existing UTF-8 mapping, including its supported accented characters.
- Normalized pad merge: requested left stick `(-77,55)`, C-stick `(33,-44)`, and triggers `(120,130)`. `PADRead` returned packed bytes `0x8278d42137b30060`, exactly matching all axes/triggers plus trigger-derived L/R bits `0x0060`. `scripts/set-desktop-stick.sh` also set and cleared the persistent left-stick state.
- `scripts/pulse-desktop-stick.sh` holds a normalized left-stick value for an exact `PADRead` count, clears it before detaching, and may queue one button on release. Direct state inspection confirmed all ten virtual-pad bytes return to zero; it then drove deterministic town movement and both resident conversations.
- `scripts/tap-desktop-button-sequence.sh` delivers repeated normalized button edges from one LLDB attachment, separated by one-shot `PADRead` breakpoints. Button and stick helpers now tolerate up to five transient debugger-ownership races with two-second backoff; shell syntax checks pass.
- The rebuilt nine-patch Apple Clang binary again completed disc indexing, archive loading, 32 kHz audio startup, and a visible 60 FPS title loop, then returned from `graph_proc` after an exact-PID `SIGTERM`. This is a smoke pass only, not proof of the patched interior transition.

### Sanitizer evidence — 2026-08-04

- Configured the complete Apple Silicon macOS game with AddressSanitizer and UndefinedBehaviorSanitizer, frame pointers, and debug symbols. The run used an isolated temporary `BELLPAD_DATA_HOME` and the ignored local supported image; no retail data entered a tracked file or build product.
- The first strict passes found and fixed uninitialized JUT video state, 4-byte heap rounding around 8-byte native headers, 8-byte message writes into 4-byte audio locals, a zero-sized release debug-flags object, undefined clock-angle conversion, event sentinel indexing, missing actor-bank indexing, cross-array player initialization, and an RSP audio-resampler state over-read.
- The final recovery run loaded 14,495 assets, opened 32 kHz stereo audio, mounted all three archives, rendered the title, reached the stable press-start state, and ran roughly 1,900 frames without a new AddressSanitizer report. It exited through an exact foreground interrupt with `graph_proc` returning.
- UBSan still reports the port's widespread legacy conversion of floating-point angles into signed 16-bit GameCube angle units. The reproducible strict script excludes only `float-cast-overflow` for that known wraparound class; it does not suppress memory, bounds, alignment, pointer, integer, or other undefined-behavior checks. Broader gameplay and long-session sanitized runs remain required.

## Functional gameplay matrix

Title/setup, train, town movement, inventory, shops, dialogue, letters, fishing, bug catching, digging, furniture, museum, saving, NES furniture, island, slot B/town travel, and controller reconnect are tracked individually. Features unsupported upstream must fail safely and be documented.

## Apple mobile sequence

For every meaningful milestone:

1. Build and run one iPhone Simulator.
2. Capture logs/layout/input/memory/render/audio observations and stop it.
3. Build and run one iPad Simulator.
4. Capture the same observations and stop it.
5. Compare, fix device-specific behavior, and repeat.

Simulator sessions must never overlap. Synthetic interruption and route notifications can prove Bellpad's in-process audio wiring, but physical hardware is required for final Metal performance, Files security scopes, real audio devices/calls/routes, haptics, controller reconnect, memory pressure, suspension, and thermal validation.

### Compatibility-layer probe evidence — 2026-08-03

| Test | Result |
|---|---|
| macOS ARM64 Aurora GX/Metal | Pass — visible blue GX clear; Dawn selected Apple M2 / Metal |
| iPhone 17 Pro Simulator install/launch | Pass — ARM64 `IOSSIMULATOR` bundle installed, launched, and visibly rendered blue through Metal |
| Stop iPhone before iPad | Pass — app terminated and phone simulator reported `Shutdown` before iPad boot |
| iPad Pro 13-inch Simulator install/launch | Pass — same bundle launched and visibly rendered in an iPadOS resizable window; logs selected Apple iOS simulator GPU / Metal |
| Bellpad/game-core rendering | Not tested by this probe |

The upstream example's empty bundle identifier was replaced only in the ignored
generated probe bundle. Its portrait phone presentation and resizable iPad
window are not accepted product layouts; they are evidence that Bellpad must own
scene/orientation/safe-area policy and adaptive touch controls.

### Bellpad-owned shell evidence — 2026-08-03

| Test | Result |
|---|---|
| macOS ARM64 configure/build | Pass — native `Bellpad.app`, ARM64 Mach-O, valid Info.plist |
| macOS launch/Metal/quit | Pass — visible MetalKit surface at requested 60 FPS; normal app quit terminates |
| Normalized input merge | Pass — native unit test covers exact GameCube button masks, eight-byte state layout, ORed buttons, strongest axes, maximum triggers, clearing, one-poll short-tap latching, invalid snapshot outputs, and 10,000 concurrent writes/copies without a torn state |
| iPhone 17 Pro Simulator | Pass — product bundle installs/launches; full GameCube touch set is visible without overlap after safe-area layout correction |
| Sequential stop | Pass — iPhone app terminated and simulator shut down before iPad boot |
| iPad Pro 13-inch Simulator | Pass — universal bundle installs/launches in a 960×640 resizable iPadOS window; actual-size scaling selects a compact no-overlap layout |
| Expanded iPad layout | Pass on the real game target — iPad metrics are visibly applied over the 2752×2064 Aurora framebuffer; current iPadOS may still manage the game in a system window |
| Shared disc validator | Pass — synthetic tests cover exact trimmed/full lengths, valid payload SHA-256, hash mismatch, wrong size/revision/game, and `.rvz` rejection; optional ignored retail-image integration passes with no retail fixture tracked |
| iPhone Files picker | Pass — Computer Use activated “Choose Game Data…” and observed Apple's native Files/Recents UI; cancel returned cleanly, and later product tests exercised invalid and valid selections |
| macOS open panel | Pass — native sheet presented with ISO/GCM content filtering; cancelled without selecting a file |
| Shell game rendering/input | Superseded — the product overlay is now linked directly into the Aurora game bundle |

### Native iOS/iPadOS game evidence — 2026-08-04

| Test | Result |
|---|---|
| Product build | Pass — complete game core links as an ARM64 `IOSSIMULATOR` `Bellpad.app` with SDL3, Aurora, Dawn/Metal, UIKit overlay, and strong normalized-input snapshot |
| Package contents | Pass — bundle contains the executable, plist, two compiled icon PNGs, `Assets.car`, and exact third-party notices; no ISO/GCM/CISO/RVZ, extracted retail asset, GCI, or raw card |
| iPhone first-run/cancel | Pass — no retained data presents Bellpad's native legal import screen; Files opens and cancellation returns to that screen without starting the core |
| iPhone invalid image | Pass — a synthetic invalid `.iso` reports an invalid GameCube header, remains on the import screen, and creates no retained image |
| iPhone valid Files import | Pass — a private ignored GAFE01 revision 0 image selected through Files passed source and staged header/size/SHA-256 validation, copied byte-for-byte into private Application Support, and booted without `--disc`; no staging file remained |
| iPhone real-game launch | Pass — private ignored GAFE01 data was read from the simulator sandbox, 14,495 assets loaded, 32 kHz audio opened, and the animated title rendered at the fixed 60 Hz simulation cadence |
| iPhone touch-to-game path | Pass — UIKit A advanced the real title into K.K.'s opening; the button edge crossed the mutex snapshot and Aurora PAD on the game thread |
| iPhone native player name | Pass — the game opened its real name editor, UIKit's native field became first responder and accepted `Bell`, the game-thread bridge consumed all four characters plus Done, and Rover rendered `Bell` in the following dialogue |
| iPhone native town name | Pass — native paste interception queued exact `Cove`, the explicit UIKit Done control committed it on the game thread, and the game advanced without debugger input injection |
| iPhone layout | Pass — landscape controls are upright after rotating the simulated hardware and avoid the Dynamic Island/safe areas |
| iPhone control settings | Pass — the native gear opened a correctly laid-out panel over the real Metal game with Native/1×/2×/3×/4× resolution, opacity/size sliders, hide/move switches, and per-device reset; source/build checks cover normalized safe-area position persistence |
| iPhone data-management UI | Pass — the compact panel now fits `Game Data & Saves…` without scrolling; no-save error and import picker routing pass, a real validated 467,008-byte GCI export completed through Files, and a later Files import staged byte-identical data that installed before normal relaunch |
| iPhone render resolution | Pass — Native used 2622×1206, 1× used 1044×480, 2× used 2087×960, 3× used 3131×1440, and 4× used 4174×1920 while the Metal drawable remained 2622×1206; this changes render resolution, not the fixed 60 Hz simulation rate |
| iPhone retained relaunch | Pass — terminating and launching again with no arguments skipped Files and returned to the animated title from the retained Application Support copy |
| iPhone GCI persistence | Pass — a desktop-created 467,008-byte Bell/Cove GCI loaded with all four endian round trips passing; the live game-facing save routine returned success, rotated the original to `.bak1`, wrote a changed canonical file, and the canonical file loaded successfully after app termination/relaunch |
| iPhone app-update persistence | Pass — a `0.1.0` build-100 Simulator app was replaced in place by `0.1.1` build 101 under the production bundle identifier. CoreSimulator relocated the data-container path but preserved the original save and retained-image filesystem inodes, sizes, and SHA-256 hashes plus opacity `0.55` and render scale `3`; normal launch selected Metal, restored the 3× framebuffer, reused retained game data, passed every GCI endian round trip, logged `GCI save loaded successfully`, and reached the title |
| iPhone corrupt-save recovery | Pass — with checksum-only corruption in a same-size, correct-header canonical GCI and valid `.bak1`, pre-boot strict validation restored a canonical file byte-identical to the known-good backup, retained the damaged file byte-identically under a unique `.gci.corrupt-…` name, loaded the recovered GCI, and reached the title. The initial live attempt exposed Foundation's default deletion of replacement backups; the final implementation explicitly retains the displaced item and the repeated proof passed |
| iPhone no-backup quarantine | Pass — with the same checksum-only damaged canonical GCI and no backup candidates, Bellpad atomically moved the exact damaged bytes to a filename that does not end in `.gci`, left no canonical file for the permissive legacy loader, logged `No save file found`, and reached the title. The isolated simulator was then terminated, shut down, and deleted |
| iPhone saved-player Metal scene | Pass — returning-player dialogue showed the host-local August 4, 2026 date/time, the train sequence advanced, Porter announced Cove, the train departed, and the station environment remained visibly rendered through Metal |
| iPhone outdoor town entry | Pass — the production UIKit A button advanced the saved-player path, the shared normalized left-stick state moved Bell out of Cove station, the outdoor town rendered through Metal, and the movement triggered Tom Nook's greeting. This bounded proof replaces broader activity-by-activity control replay |
| Dolphin GCI-folder interchange | Pass with isolated harness — Dolphin 5.0-17995 booted GAFE01 with Bellpad's canonical GCI in a private GCI Folder, read its header/data without invalid-file diagnostics, and left the SHA unchanged; Bellpad then installed and loaded that Dolphin-managed file before startup |
| iPhone real GCI export | Pass — the production gear-menu action opened Files while holding the game render loop, saved `Bellpad-Dolphin-Save.gci`, dismissed, resumed live rendering, removed its temporary snapshot, and produced the same 467,008-byte SHA-256 as the canonical file |
| Sequential stop | Pass — iPhone app terminated, exact simulator test copies were removed, and the simulator shut down before iPad boot |
| iPad first-run/valid import | Pass — no-data screen presented in iPadOS's managed window; Files-selected GAFE01 data was retained byte-exactly with no staging residue and the native title rendered with iPad control metrics |
| iPad native player name | Pass with harness limitation — the real editor presented the adaptive UIKit field as first responder, accepted text through the production insertion method, exited on Done, and Rover echoed the entered prefix. Simulator host-focus loss paused consumption during LLDB automation, so this run does not claim an exact full-name value |
| iPad control settings | Pass — after the iPhone session was stopped, the universal app rendered expanded iPad controls in the managed window and opened the complete top-right gear panel; Render, Native/1×/2×/3×/4×, sliders, switches, and reset remained readable at the iPad window scale |
| iPad data-management UI | Pass — after iPhone shutdown, the full settings panel exposed `Game Data & Saves…`; a real validated GCI export presented in the managed Files sheet, saved, dismissed, and returned to the live game |
| iPad render resolution | Pass — the 4× choice produced a 2560×1920 internal framebuffer against the 2752×2064 iPad drawable, preserving the fixed 60 Hz simulation path |
| iPad saved-player Metal scene | Pass through station — after the iPhone simulator was shut down, the same universal app and Bell/Cove GCI advanced through returning-player selection, train animation, Porter dialogue, and the live Cove station using production UIKit A input. The Simulator automation gesture releases the analog stick too quickly for a reliable outdoor traversal, so this row does not claim one |
| Populated inventory rendering | Pass — 2026-08-06, iPad Simulator and physical iPad. The protected Chris/BUDAPEST save exposed two occupied pocket slots; patch 49 routes the existing item and selection-mark quads through the working polygon display-list path. Both icons rendered in the Simulator screenshot, and the same signed build passed the user's physical-iPad inventory check |
| Original app icon | Pass — opaque full-bleed 1024×1024 source has no alpha or baked rounded corners; `actool` emitted iPhone/iPad renditions and plist metadata, the installed iPhone home screen displayed the Bellpad icon, and macOS `iconutil` round-tripped all ten 16–1024 px iconset files |
| iPad retained startup/relaunch | Pass — earlier terminate/relaunch returned to the animated Metal title, and a fresh no-argument strict-validator launch accepted the retained image's exact size/SHA-256 and stayed live on the Metal product |
| Cleanup | Pass — each recorded sequential run terminated the active app and shut down its simulator before the next device class; no simulator remained booted. Retail data and saves remained outside Git and every app/package artifact |
| Lifecycle/audio wiring | Pass for three bounded iPhone Simulator cycles after fixing a reproduced second-cycle `EXC_BAD_ACCESS`: when Aurora declines a background frame, patch 29 discards queued GX data and never calls `aurora_end_frame` without a frame packet. All three Home/foreground cycles logged matched pause/resume edges and restored Metal rendering; RSS remained bounded in the short run and no new crash report appeared. Three sequential iPad Home/resume cycles also restored visible rendering. On 2026-08-04, isolated iPhone and then iPad Simulator runs opened the real SDL3 stream at 32 kHz and underwent eight-second opt-in `AVAudioSession` interruptions. Both logged sample-clocked discard, matched pause/reactivate/fresh-sample resume, no `SendStart::Mesg Full Queue`, a subsequent route-change pause/resume, and continued title frames. Real hardware routes/calls, long-session memory, and two SDL UIKit startup warnings remain |
| RTC activation rebase | Pass — patches 30/31 rebuilt into the universal product; iPhone Home/foreground logged audio pause, `RTC synchronized after UIApplicationDidBecomeActive (adjustment 0.000 seconds)`, and audio resume. The same bundle then booted the real game on iPad only after iPhone shutdown and returned from one bounded Home/resume cycle |
| NES GX framebuffer | Partial — deterministic tests prove visible-row cropping, fixNES-to-GX RGB565 field conversion, big-endian bytes, 4×4 tile ordering, invalid-buffer rejection, and final-pixel placement; macOS, iOS Simulator, and iOS device products compile/link the GX presenter. No local `.nes` input was available, so actual NES-furniture video remains a runtime gate |
| ARM64 device build | Pass — complete product links as Mach-O arm64 with `LC_BUILD_VERSION` platform `IOS`, minimum iOS 17.0, Metal, and no SDL2. The inventory-fix build was locally signed, verified, installed in place on Chris' iPad Pro, launched, and observed live as PID 5857 |
| Unsigned IPA reproducibility | Pass — two final 14,137,497-byte timestamp-normalized inventory-fix packages were byte-identical with SHA-256 `d95ef5716740081dba9eb5816b9b4037f6337ec52123f75441ad878f52e462a7` |
| Device runtime-link audit | Pass — `otool` reports only Apple system frameworks and `/usr/lib` libraries; no `LC_RPATH` remains, and the package script independently enforces both constraints |
| Post-static-link simulator smoke | Pass — rebuilt universal bundle installed and launched to the native no-data Files screen on iPhone 17 Pro, then after shutdown on iPad Pro 13-inch; both sessions were terminated and shut down without extended control replay |
| Dependency/archive pins | Pass — product dependency lock covers every linked non-system library; Abseil, SDL3, source Dawn, iOS Dawn, and macOS Dawn hashes close the formerly version-only downloads, while all remaining fetched archives retain upstream SHA-256 pins |
| Bundled license notices | Pass — the macOS baseline, universal Simulator app, device app, IPA staging tree, and final IPA carry byte-identical `ThirdPartyNotices.txt`, including SDL HIDAPI/yuv2rgb's separate BSD terms; the archive contains only that notice plus the executable, plist, `Assets.car`, and two compiled icon PNGs |
| Unsigned IPA contents | Pass — 13 MiB archive contains only the executable, plist, `Assets.car`, two compiled icon PNGs, and `ThirdPartyNotices.txt`; staged bundle signatures and empty signature directories are removed, with no provisioning profile, retail data, save, key, or certificate |

The disc-import runs above used the native Files UI and no `--disc` argument. They
prove the raw ISO/GCM user flow and relaunch retention. The later save-management
runs used ignored GCI data and the production gear-menu actions. They prove real
export bytes, isolated Dolphin interchange, a fully UI-driven Files import, and
byte-identical pre-boot installation. The versioned update test additionally
proves that Simulator bundle replacement preserves that private state and settings.
The fault-injection tests prove that strict mobile pre-boot validation either
installs a valid backup while preserving the displaced bytes or quarantines the
invalid canonical file before the legacy loader can observe it.
These runs do not prove compressed formats, broad letter-editor coverage,
physical-device security scopes/keyboards, real hardware audio routes/calls, or
long-session mobile lifecycle behavior.

The native keyboard tests used the actual UIKit first-responder and insertion
methods, then inspected the bounded product queue and existing game editor under
LLDB. The iOS software keyboard was visibly presented on iPhone. Simulator
hardware-keyboard capture and host focus made reliable on-screen key clicking
non-deterministic, especially on iPad; that automation limitation is recorded
instead of treating partial queued input as an exact-name pass. Both simulator
sessions were terminated and shut down sequentially, and their exact private
test copies were removed or moved to Trash afterward.

### Playable macOS app evidence — 2026-08-03

| Test | Result |
|---|---|
| App configure/build | Pass — all 4,000 core units link into `Bellpad.app/Contents/MacOS/Bellpad`, a native ARM64 Mach-O with a valid plist |
| Package contents | Pass — executable, plist, and two clean GLSL shaders only; no disc image, extracted retail data, or save |
| Explicit image validation/load | Pass — ignored GAFE01 disc 0 revision 0 image selected through `--disc`; 10 FST files indexed and 14,495 assets loaded directly |
| Arbitrary-cwd launch | Pass — launched from `/tmp`; shaders resolved from app resources and mutable data moved to Application Support |
| Render/audio/timing smoke | Pass — Apple M2 renderer, 32 kHz stereo audio, fixed 60 Hz VI pacing, `graph_proc`, and completed title prompt observed |
| Overclock rejection | Pass — bundled executable returns status 2 for both `--framelimit 120` and `--no-framelimit` with an acceleration warning |
| Native picker | Build/runtime path present; the previously proven AppKit sheet covers presentation, but selecting retail data through it remains a manual product test |
| Application Support path/relaunch | Pass — isolated `BELLPAD_DATA_HOME` became the reported save cwd; a second launch loaded the same settings/keybindings |
| Game-facing save/atomic backups | Pass for native persistence/interchange — an initialized Bell/Cove town wrote a canonical GCI, normal window close returned from `graph_proc`, and a fresh process passed all four endian round trips, reported `GCI save loaded successfully`, and entered the saved-player Cove station flow. Dolphin GCI-folder read, Bellpad pre-boot install/load, real Files exports, and fully UI-driven Files import pass; the retail save dialogue remains pending |

### Game-core/Aurora convergence evidence — 2026-08-03

| Test | Result |
|---|---|
| Compiled GX/GD coverage | Pass — 3,905 game-core objects require 112 symbols; patched Aurora provides all 112 |
| GX value ABI | Pass — sizes and alignments match for render mode, colors, lights, fog, and vertex descriptors |
| Opaque GX object storage | Pass — core/Aurora `GXTexObj` is 88/64 bytes and `GXTlutObj` is 40/40 bytes |
| Baseline regression rebuild | Pass — all 3,361 affected build steps completed and the ARM64 `Bellpad.app` linked after palette-storage expansion |
| Aurora-defined full-core compile | Pass — 3,904 game objects compile with `AURORA`; 111 GX/GD imports all resolve |
| Legacy renderer-hook isolation | Pass — zero `pc_gx_*`, `pc_emu64_frame_*`, or `s_tlut_*` imports; host TLUT byte order resolves through the explicit Aurora bridge |
| OpenGL baseline regression rebuild | Pass — ARM64 `Bellpad.app` relinked after the conditional split, proving the temporary playable backend still compiles |
| Animal Crossing through Aurora/Metal | Partial — native ARM64 executable selects Metal, loads disc/assets/audio, and reaches an interactive title menu at 60 FPS; EFB clearing prevents accumulation, palette/cache fixes hold, counter-clockwise WebGPU front faces restore complete title geometry, keyboard A advances correctly rendered multi-line K.K. dialogue, both simulator classes render a saved-player train/station sequence, and iPhone continues into the outdoor town and Tom Nook's greeting. Interiors, broader outdoor comparison, and long-session memory still need direct evidence |
| Aurora normalized input boundary | Pass for the implementation gate — default keyboard mapping remains, patch 19 pulls on the game thread, the mobile executable links the strong snapshot, UIKit A advances the real game, and normalized stick movement is proven on desktop. Exhaustive activity-by-activity replay is deferred to release acceptance |

The iPhone simulator screenshot required rotation for human inspection because
`simctl io screenshot` retained the physical portrait buffer while UIKit
correctly laid out the app in landscape. No screenshot is used as game evidence.

## Safety and package tests

- Scan Git index, archive, app bundle, and IPA case-insensitively for ISO/GCM/CISO/RVZ/WIA/WBFS/GCZ, extracted retail files, GCI/raw saves, credentials, certificates, and provisioning profiles.
- Verify the IPA contains no retail image, extracted retail asset, generated playable archive, user save, or signing secret.
- Install, create/import a save, update in place, verify persistence, inject canonical corruption, and prove both valid-backup restoration and no-backup quarantine.
