# Bellpad modernization qualification — 19 September 2026

## Scope and source

App baseline/public Preview 2: `c2bcbdedb1aa9b512c41f4a213716d1e085fb446`.
This change keeps that upstream version and the existing product. Source migration
is proposed for review; no merge or binary publication is part of this task.
Later owner-authorized hardware and controls/diagnostics scope is recorded below. The fork pins, licensing boundaries, source export and rollback
procedure are in [SOURCE_MAINTENANCE.md](SOURCE_MAINTENANCE.md).

## Verified evidence

- Exact GitHub identity `chrissotraidis/bellpad`; clean main at the baseline.
  Ignored PC/Aurora checkouts have replayed changes and cached builds. Only one
  whitespace-only PC difference exists beyond a clean replay; it is preserved
  privately and not imported.
- Real GitHub fork parents: PC port → birabittoh/ACGC-PC-Port; Aurora →
  encounter/aurora. Upstream history and notices retained.
- Historical replay matches PC tree `9e158781cfdc52dbc97dac4f0892d00558564309`
  (50 patches) and Aurora tree `11edea7d78583e936c919c1f7aefae4c0136ea71`
  (six patches), including tracked file modes. The selected maintained trees
  add only source-ownership documentation and local build ignore rules.
- Full private checkout backup independently restored: 171,114 entries with
  matching SHA-256/modes; verified Git bundle. Same physical disk, not off-device
  disaster recovery. Private game/build inputs remain private.
- Anonymous public Preview 2 IPA equals the local accepted artifact:
  `d9e9ebd5d17fa360de1775cf60deaccd8ca5b196b09842ea633a8ad353a8aaea`.
  Product identity: `dev.bellpad.app`, version 0.1.0, build 2; unsigned.
- Source-release suite passes: native input tests, controller lifecycle,
  RTC, disc-reference persistence, NES/GX conversion, content/notices and shell
  checks. Both maintained dependency pins verify cleanly.
- Apple Silicon macOS SDL2/OpenGL baseline and ARM64 iOS device product build
  successfully with the maintained sources. Device build audits ARM64/IOS,
  system-only dynamic dependencies, no runtime search paths, exact notices,
  and absence of prohibited data/signing files.

## Final source/package qualification

Code/artifact commit: `ee986f320be21d391da20946358fbfd68b9311a0`.
[Review PR #11](https://github.com/chrissotraidis/bellpad/pull/11) remains unmerged.
The following documentation-only checkpoint does not change the binaries.

| Local artifact (not published) | SHA-256 |
|---|---|
| `Bellpad-qualified-unsigned.ipa` | `0766c2ec474ff834378bde348f8ec233154ee057c10cfb7b81a4c31d88872775` |
| `Bellpad-qualified-source.tar.gz` | `0c7fc5c2ffda2158f0234769500d958ee0b83c5ff94fc79bce2bc06d32d363aa` |

The IPA retains `dev.bellpad.app`, 0.1.0/build 2, is unsigned, and has matching
executable/plist minimum iOS 17.0. Source provenance identifies the clean artifact
commit and both dependency pins. It is an internal qualification candidate,
not a new release or a replacement for Preview 2.

- Device and Simulator builds/package audits pass under Xcode 27.0 (27A266a).
  Device uses its pinned Dawn package; Simulator builds Dawn source. Native macOS
  baseline builds against the host SDL2 2.32.10; no macOS binary was published.
- All 6,952 exported files restore and verify with SHA-256 and normalized Git
  executable modes without Git/network. Both modified dependency trees are
  included. Corrupted/unrecorded source, wrong pins, dirty dependency source,
  stale package provenance, and missing/mismatched OS metadata are rejected.
- Restored baseline Git bundle checks out the old commit; old PC/Aurora fetch
  scripts and the 50-patch regression replay pass in a disposable checkout.
  Supplemental PC/Aurora history bundles verify complete upstream ancestry.
- SDL 3.4.10 fetched archive SHA-256 matches the lock. Comparing its prepared tree
  to the pristine archive finds only `SDL_gamepad.c`'s Android-guarded mapping
  block and Android `SDLActivity.java`. Controller regressions pass. Optional
  zlib-ng/RmlUi package patches remain disabled for the product.
- [Hosted Apple ARM64 check](https://github.com/chrissotraidis/bellpad/actions/runs/35408311699)
  passed for the initial PR. The final documentation/code head is checked again
  by the PR workflow; use its current result as authoritative.
- A fresh iPhone Simulator on iOS 26.5 installs/launches the playable app and
  reaches “Choose your game data.” The computer-use connection could not access
  Xcode's Simulator, so actual file-picker taps/import are **not verified**.
  No physical device was installed, no private game/save state changed, and no
  new gameplay/controller acceptance is claimed.

The source archive is not an offline Xcode/third-party dependency cache and does
not establish byte-identical binary reproduction across toolchains. The existing
reconstructed-game rights question and original Bellpad's lack of an outbound
grant remain explicit. No new release is authorized. Next action: review PR #11;
reporter evidence is needed before claiming issue #10 resolved, and any later
binary publication requires its own authorization and qualification.

## Issue #10

[File Browser Select issue](https://github.com/chrissotraidis/bellpad/issues/10)
reports iPhone 12 Pro Max on iOS 16.6.1. The downloaded Preview 2 executable has
`LC_BUILD_VERSION` minimum iOS 17.0, matching the documented supported baseline;
its Info.plist lacks `MinimumOSVersion`. This is a concrete packaging metadata
gap, not proof of the reported gesture failure's cause. The playable IPA uses
`BellpadGameOverlay.mm`, not the separate shell's picker. Do not lower the OS
target or claim the report fixed without supported-device evidence.

The metadata correction is implemented independently of the source migration,
with rejection checks in IPA packaging. [Investigation reply](https://github.com/chrissotraidis/bellpad/issues/10#issuecomment-5737689176)
asks for the exact IPA/installer, local versus cloud storage, and whether the
file is greyed out. The issue remains open; no game image or save was requested.


## Follow-up review and hardware deployment

On 19 September the owner authorized continued review and an in-place update of
the existing hardware iPad, preserving its imported ISO, saves and settings. This
supersedes the earlier no-install scope; binary publication remains unauthorized.

Review found and corrected two source-delivery gaps: nondeterministic gzip
headers, and provenance that did not bind the actual executable/bundle identity.
Exported source is now revalidated when provenance is generated or accepted.
`tests/SourceDeliveryTests.py` exercises deterministic export, executable/version
tampering, modified offline source and dirty-checkout rejection in CI. iOS build
3 identifies this local candidate; upstream/component pins remain unchanged.

Before installation, the current hardware app was verified as 0.1.0/build 2.
All 13 container files (36,458,717 bytes), including one ISO, two GCI saves,
settings and preferences, were copied twice using independent transfer paths.
Hashes match and a separate local restore matches. Existing signing/team,
application identity and keychain groups are preserved; the matching profile
covers this hardware. No app uninstall or container replacement is needed.
Build 3 (`e3961c237cdfa4b35d91b0b2a27aa94df746e4aa`) installed in place.
Installed certificate, bundle identity, keychain groups and entitlements match the
prior app exactly. Post-startup readback keeps the ISO, both GCI files, settings
and preferences byte-identical; changed files are Dawn caches and iOS scene state.
The physical screen shows rendered game dialogue. This is startup evidence,
not new controller/gameplay acceptance. Its unsigned IPA SHA-256 is
`fc7023bf17719f3be8d00ce5eed5437a4d4519bfa860bd3b4b8b19cfdf4d63d1`;
source archive SHA-256 is
`10f83d302ab5bef6286482f3a883a08219a4bb802420fe1eddb4c33c2f0d58de`.
Two differently named exports match, and all 6,953 files restore offline.

The owner then explicitly expanded scope to improve persistent diagnostics,
controls and the native menu, retaining existing features. Build 4 is a separate
feature candidate described in [DIAGNOSTICS_AND_CONTROLS.md](DIAGNOSTICS_AND_CONTROLS.md).
The behavior-preserving migration checkpoint remains available independently;
these later changes must not be described as part of its tree-parity proof.
