# Testing strategy and evidence

Last updated: 2026-08-03

No gameplay test is marked passed without a dated result, device/OS, build revision, image revision, and observable outcome.

## Desktop baseline matrix

| Test | Expected | Current evidence |
|---|---|---|
| Configure/build native ARM64 | Mach-O arm64 executable | Pass — 2026-08-03, M2/macOS 26.5; independent full builds with Apple Clang 21.0.0 and GCC 16.1.0 |
| Apple toolchain runtime smoke test | Native binary reaches visible game output | Pass — Apple Clang build rendered the title correctly at 60 FPS using the ignored supported image |
| Validate supported disc | Accept `GAFE01` USA Rev 0 only | Partial pass — local header/revision/magic/hash validated; product hash allowlist pending |
| Trademark/title | Correct render/audio/input | Partial pass — correct 60 FPS rendering and 32 kHz stereo; A/Start works through a latched native test path; cleanup overflow fixed; repeatable UI automation pending |
| Character/town creation | Completes with text entry | Partial pass — Bell/Cedar, train, town generation, house selection, mortgage, and early work tutorial completed; first save remains pending |
| Enter town | Stable outdoor rendering and movement | Pass — station exit, outdoor movement, Nook greeting, and housing area observed |
| Save/exit/relaunch | Same town loads from GCI | Pending |
| RTC | Time and date match host | Partial pass — fresh setup displayed Monday, August 3, 2026 and the expected host-local time; save/relaunch and clock-change behavior remain pending |
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
- No GCI file was created before the session ended, so save/reload is not marked passed.
- The current Computer Use wrapper does not consistently deliver synthesized keys to SDL. The linked Homebrew library is `sdl2-compat`, backed by SDL3, so raw SDL2 event-layout injection is also invalid. For desktop QA, `scripts/tap-desktop-button.sh <pid> A` calls the same normalized queue under LLDB; it deliberately supports buttons only and does not bypass game logic.
- `scripts/type-desktop-text.sh <pid> Bell` validates an explicit game PID, restricts its shell-facing value to ASCII alphanumerics, and calls the same begin/commit/Enter API planned for native keyboard adapters. The underlying API retains the port's existing UTF-8 mapping, including its supported accented characters.
- Normalized pad merge: requested left stick `(-77,55)`, C-stick `(33,-44)`, and triggers `(120,130)`. `PADRead` returned packed bytes `0x8278d42137b30060`, exactly matching all axes/triggers plus trigger-derived L/R bits `0x0060`. `scripts/set-desktop-stick.sh` also set and cleared the persistent left-stick state.
- `scripts/pulse-desktop-stick.sh` holds a normalized left-stick value for an exact `PADRead` count, clears it before detaching, and may queue one button on release. Direct state inspection confirmed all ten virtual-pad bytes return to zero; it then drove deterministic town movement and both resident conversations.
- `scripts/tap-desktop-button-sequence.sh` delivers repeated normalized button edges from one LLDB attachment, separated by one-shot `PADRead` breakpoints. Button and stick helpers now tolerate up to five transient debugger-ownership races with two-second backoff; shell syntax checks pass.
- The rebuilt nine-patch Apple Clang binary again completed disc indexing, archive loading, 32 kHz audio startup, and a visible 60 FPS title loop, then returned from `graph_proc` after an exact-PID `SIGTERM`. This is a smoke pass only, not proof of the patched interior transition.

## Functional gameplay matrix

Title/setup, train, town movement, inventory, shops, dialogue, letters, fishing, bug catching, digging, furniture, museum, saving, NES furniture, island, slot B/town travel, and controller reconnect are tracked individually. Features unsupported upstream must fail safely and be documented.

## Apple mobile sequence

For every meaningful milestone:

1. Build and run one iPhone Simulator.
2. Capture logs/layout/input/memory/render/audio observations and stop it.
3. Build and run one iPad Simulator.
4. Capture the same observations and stop it.
5. Compare, fix device-specific behavior, and repeat.

Simulator sessions must never overlap. Physical hardware is required for final Metal performance, Files security scopes, audio interruption/route changes, haptics, controller reconnect, memory pressure, suspension, and thermal validation.

## Safety and package tests

- Scan Git index, archive, app bundle, and IPA case-insensitively for ISO/GCM/CISO/RVZ/WIA/WBFS/GCZ, extracted retail files, GCI/raw saves, credentials, certificates, and provisioning profiles.
- Verify the IPA contains no retail image, extracted retail asset, generated playable archive, user save, or signing secret.
- Install, create/import a save, update in place, and verify persistence and backup recovery.
