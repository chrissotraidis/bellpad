# Research and upstream provenance

Last updated: 2026-08-03

All checkouts below live under ignored `ref/` paths. A commit pin records what was inspected; no checkout is automatically incorporated.

| Project | URL and inspected revision | License / provenance | Purpose and observed result | Disposition / likely reuse |
|---|---|---|---|---|
| ACreTeam ac-decomp | https://github.com/ACreTeam/ac-decomp — `master` `09ca8e8b5b24e6ab44047ee980cf0088ad7ecb4c` | CC0-1.0; matching clean-room decomp; repo says no game assets or assembly | Authoritative USA Rev 0 (`GAFE01_00`) game-code source | Candidate incorporated game code through a port tree; exact attribution retained |
| ACGC-PC-Port | https://github.com/flyngmt/ACGC-PC-Port — `master` `4099d246c927e75b4fd342ca13f4ac4395c55af5` | Decomp CC0; `pc/` and `TARGET_PC` additions MIT; FixNES MIT | Most mature playable native port; SDL2, OpenGL 3.3, direct ISO/GCM/CISO reads, GCI saves. Current CMake intentionally requires 32-bit because of pointer truncation | Reference and source of mature gameplay/platform fixes; not accepted unchanged |
| Full 64-bit migration | https://github.com/birabittoh/ACGC-PC-Port — `master` `915fb86ba9a6c2144dabda9143d93af7a3f92be7` (upstream PR #48) | Inherits CC0/MIT tree; provenance derives from the PC port and PR history | Built locally as macOS ARM64. After a local aligned-DVD-tail fix it renders title/K.K. with audio, but dialogue advancement, a title cleanup race, and shutdown remain broken. Still GCC-only on 64-bit and not rebased to current upstream | Milestone 1 fault-isolation baseline and migration evidence; changes must be reviewed/forward-ported |
| Early macOS fork | https://github.com/Dimillian/ACGC-macOS-Port — `master` `d552ede1bbe3910759ce749b18fd4d2d670b117a` | Inherits PC-port licensing; older fork | Early native macOS experiment | Reference only; superseded by the maintained 64-bit PR |
| Aurora | https://github.com/encounter/aurora — `main` `5027ed63a73dfba28de9eceed00481fb09a19c35` | MIT, independently written source-level compatibility layer | SDL3 app layer; Windows/Linux/macOS/iOS/tvOS/Android; GX→Dawn→Metal/Vulkan/D3D12; PAD; nod DVD incl. RVZ; GCI/raw CARD; RTC/iOS and haptics work | Intended pinned dependency after integration spike; likely submodule or FetchContent pin |
| ACreTeam forest | https://github.com/ACreTeam/forest — `main` `2151e11e7520b1d07f544984af4c3113a1f8023f` | CC0 top-level; matching-decomp provenance | New official WIP source-port tree. Pins Aurora `bd20b65…` for core/PAD/SI/OS/CARD/DVD but disables Aurora GX and contains no-op GX stubs. Its tracked 16 MiB `aram.bin` requires provenance review before reuse | Reference for Aurora integration and upstream direction; not currently playable; do not copy `aram.bin` pending review |
| OpenCrossing Anbernic | https://github.com/GabeConway/OpenCrossing-Anbernic — `main` `762ea7a5a5c3d9325ef9fa4a767b17b9f33b0f01` | Inherits PC-port CC0/MIT boundary; verify added-file notices individually | Native ARMv7/Cortex-A53 handheld port using OpenGL ES 3.2; boots/renders/saves on hardware; direct image read and GCI saves | Reference for ARM portability, GLES adaptations, memory/performance, and handheld controls |
| HarkinianPad | https://github.com/chrissotraidis/harkinianpad — `main` `1197472956cd2c4dd3f03fb6fe5f2dfb28d30ad7` | HarkinianPad-owned integration is all-rights-reserved unless a file says otherwise; third-party licenses vary | Proven native iOS source-port integration, Files flow, Metal, touch editor, packaging audit, lifecycle patterns | Architecture/UX reference only unless the owner explicitly licenses reusable files |
| Animal Crossing Online | https://animalcrossingonline.com/ — site build `a78f46fc` observed 2026-08-03 | Public site claims a native WebAssembly port; source repository/license not identified | Browser port imports ISO/GCM/CISO locally, caches data, has mobile touch and Dolphin-save import/export. It demonstrates behavior but not reusable provenance | Behavior/reference only; never embed its WebAssembly application |
| Vita port | https://github.com/Brendonm17/ACGC-Vita-Port — `master` `46fb6b4cc4beb187e898b04a7fb075d0bd93a463` | GitHub reports no machine-readable license; derives from PC port | ARM handheld/mobile-style platform experiment | Reference only until file-level licensing and provenance are verified |
| Experimental Android fork | https://github.com/YlPorts/ACGC-Android-Experimental-chatgpt-5.6- — `master` `99af0864b8508834b0aab6be740fd4af2e4def74` | GitHub reports no machine-readable license; described as experimental AI port | Recent Android experiment | Reference only; no reuse without audit and build evidence |

## Relevant branches, PRs, and issues

- PC-port PR #33 (`acc161f…`): first broad 64-bit/macOS/Arch effort; 228 files, reported working on multiple desktops, but abandoned and merge-conflicted.
- PC-port PR #48 (`915fb86…`): maintained full 64-bit migration. Reports include macOS ARM64 launch, Windows/Linux gameplay, audio, and save/reload. Known UI line artifacts remain and the PR is too large for upstream to merge without deeper review.
- PC-port issues show current gaps around RVZ, island/town travel, NES/slot B, letters/passwords, and several gameplay softlocks; tests must cover them rather than assuming title-screen success.
- Aurora history includes iOS time-overflow fixes, iPhone haptics, Metal warnings/fixes, GCI-folder and raw-card work, large-file fixes, controller persistence, and mobile GPU fixes.

## Architecture comparison

| Option | Evidence | Decision |
|---|---|---|
| Adapt current 32-bit Windows port directly | Most gameplay-complete, but hard-fails 64-bit and targets desktop OpenGL 3.3 | Use as behavior oracle and bug-fix source, not final platform base |
| Use 64-bit PC fork plus port OpenGL to iOS | Apple Silicon build evidence exists, but GCC-only truncation remains and desktop GL shaders/API do not map cleanly to iOS GLES | Use only to establish Milestone 1 |
| Use ACreTeam forest unchanged | Clean Aurora service integration, but Aurora GX is disabled and GX functions are no-ops | Not playable; reference only for platform integration |
| Combine mature PC game fixes with Aurora | Preserves working game adaptations while replacing bespoke platform code with tested Metal/iOS, disc, controller, RTC, and save layers | Selected, contingent on GX coverage spike |
