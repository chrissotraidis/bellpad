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
| Character/town creation | Completes with text entry | Partial pass — player/town names, train, and town generation completed; first house/save not yet finalized |
| Enter town | Stable outdoor rendering and movement | Pass — station exit, outdoor movement, Nook greeting, and housing area observed |
| Save/exit/relaunch | Same town loads from GCI | Pending |
| RTC | Time and date match host | Pending |
| Memory | No unbounded growth during sustained play | Pending |

### Baseline defects reproduced on 2026-08-03

- Trimmed-image EOF: the 56-byte final file is requested as 64 aligned bytes; the original host shim retries forever. A local file-length clamp plus zero-filled alignment tail fixes boot.
- Title cleanup overflow: debugger sampling showed `play_cleanup → Actor_info_dt → Actor_info_delete → zelda_free`, with the invalid pointer inside `aSTR_actor_cl`. Clang record layouts measured `STRUCTURE_ACTOR=832` and `SHRINE_ACTOR=840`; the Shrine tail overwrote the next 832-byte slot. A 0x400-byte host slot, based on current upstream's equivalent 32-bit repair, survives repeated teardown/reload cycles under Apple Clang; GCC also rebuilds.
- Short keyboard edges: synthesized native key taps could end between `PADRead` calls. An event-edge latch fixes dialogue advancement and is now a tracked patch.
- Shutdown evidence differs by harness: app-wrapper sessions have needed SIGKILL, while one targeted raw-process `SIGTERM` test exited. A later Clang wrapper again needed SIGKILL, so window/app teardown remains open.

### Gameplay evidence on 2026-08-03

- Completed K.K. introduction and all Rover setup dialogue.
- Entered `Bell` and `Cedar` through the desktop text-input adapter.
- Completed the train sequence and arrived in the generated town.
- Exited the station, moved outdoors, met Tom Nook, and reached house selection.
- Rendering and audio remained active throughout; no panic occurred on the normal title path.
- No GCI file was created before the session ended, so save/reload is not marked passed.
- The current Computer Use wrapper does not consistently deliver synthesized keys to SDL. Manual/native input evidence is retained, while future automated runs require an explicit test-input adapter rather than relying on window automation timing.

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
