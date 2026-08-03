# Testing strategy and evidence

Last updated: 2026-08-03

No gameplay test is marked passed without a dated result, device/OS, build revision, image revision, and observable outcome.

## Desktop baseline matrix

| Test | Expected | Current evidence |
|---|---|---|
| Configure/build native ARM64 | Mach-O arm64 executable | Pass — 2026-08-03, M2/macOS 26.5, GCC 16.1.0 |
| Validate supported disc | Accept `GAFE01` USA Rev 0 only | Partial pass — local header/revision/magic/hash validated; product hash allowlist pending |
| Trademark/title | Correct render/audio/input | Partial pass — correct 60 FPS rendering and 32 kHz stereo; A/Start works through a latched test path; transition race remains |
| Character/town creation | Completes with text entry | Blocked — first K.K. page redraws but does not advance |
| Enter town | Stable outdoor rendering and movement | Pending |
| Save/exit/relaunch | Same town loads from GCI | Pending |
| RTC | Time and date match host | Pending |
| Memory | No unbounded growth during sustained play | Pending |

### Baseline defects reproduced on 2026-08-03

- Trimmed-image EOF: the 56-byte final file is requested as 64 aligned bytes; the original host shim retries forever. A local file-length clamp plus zero-filled alignment tail fixes boot.
- Title transition: one input/timing sequence skipped from title action 3 to 6 and repeatedly panicked on an invalid arena free; the normal 3→4→5 sequence reaches K.K. and does not reproduce it.
- Dialogue: at K.K.'s opening page, A restarts the text reveal instead of progressing the script.
- Shutdown: window close, Command-Q, SIGINT, and SIGTERM do not exit; SIGKILL was required.

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
