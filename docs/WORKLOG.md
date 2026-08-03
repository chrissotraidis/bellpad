# Worklog

## 2026-08-03

- Established a persistent implementation goal and milestone plan.
- Audited the initially empty root repository and local references.
- Added and verified `.gitignore` coverage for `ref/Animal Crossing.iso`, other disc formats, extracted data, saves, packages, build output, signing material, and secrets.
- Inspected HarkinianPad commit `1197472…` and its restrictive integration-code licensing boundary.
- Researched and cloned ac-decomp, the current PC port, the full 64-bit migration, Aurora, ACreTeam forest, OpenCrossing Anbernic, and older macOS work.
- Inspected upstream branches, forks, issues, and PRs, especially PC-port PRs #33 and #48.
- Confirmed the current PC port is still forced to 32-bit, while PR #48 reports macOS ARM64 and end-to-end save/reload.
- Confirmed Aurora's iOS/Metal, disc, controller, RTC, and save capabilities from source.
- Confirmed ACreTeam forest already integrates Aurora services but currently disables Aurora GX and uses no-op GX stubs.
- Selected a provisional hybrid architecture and documented its decision gates.
- Installed Homebrew GCC 16.1.0 and built the pinned 64-bit fork successfully as an ARM64 Mach-O (15,380,656 bytes).
- Validated the ignored local image as `GAFE01`, revision 0, with correct GameCube magic; stored its size/hash only in `ref/.image-validation.txt`, which is ignored.
- Launched the baseline through SDL/Cocoa. It indexed 10 disc files, decompressed the REL, loaded 14,495 assets directly from the image, and opened 32 kHz stereo audio.
- Diagnosed the initial black screen: no draw calls occurred because JSystem's aligned 64-byte read of the last 56-byte file extended eight bytes past a trimmed image's EOF and the DVD shim retried forever.
- Corrected the local DVD shim to clamp reads to the declared file size and zero-fill only the aligned tail. The game then rendered the title correctly at 60 FPS with hundreds of draw calls and no GL errors.
- Packaged the ignored baseline executable temporarily as a minimal `.app` only so local UI automation could inspect its Cocoa window; no retail data was copied into the bundle.
- Reached K.K.'s new-game dialogue with correct rendering/audio. Town creation remains blocked because A redraws the first page instead of advancing.
- Reproduced a timing-dependent title transition that skipped cleanup and repeatedly panicked on an invalid arena free. Changed local panic behavior to abort with a bounded stack trace for future diagnosis.
- Confirmed the current shutdown path ignores window close, Command-Q, SIGINT, and SIGTERM, requiring SIGKILL during tests.
- Added an event-latched keyboard-button experiment in the ignored reference clone so synthesized short key events cannot fall entirely between PAD polls; this informs the future normalized mobile input layer but is not yet product code.
