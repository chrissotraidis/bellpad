# Bellpad modernization qualification — 19 September 2026

## Scope and source

App baseline/public Preview 2: `c2bcbdedb1aa9b512c41f4a213716d1e085fb446`.
This change keeps that upstream version and the existing product. Source migration
is proposed for review; no merge, binary publication or physical installation is
part of this task. The fork pins, licensing boundaries, source export and rollback
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

## Remaining qualification

Simulator build, source archive restoration and failure-boundary tests, and
final package identities are recorded as they complete. No physical-device or
new gameplay acceptance is implied by build/test success. Existing public
Preview 2 and its prior acceptance remain separate from these local artifacts.

The established reconstructed-game rights question and original Bellpad's lack
of an outbound grant remain explicit. This task preserves those terms rather
than asserting clearance. No new binary release is authorized. Review/merge and
any future release decision remain follow-up actions.

## Issue #10

[File Browser Select issue](https://github.com/chrissotraidis/bellpad/issues/10)
reports iPhone 12 Pro Max on iOS 16.6.1. The downloaded Preview 2 executable has
`LC_BUILD_VERSION` minimum iOS 17.0, matching the documented supported baseline;
its Info.plist lacks `MinimumOSVersion`. This is a concrete packaging metadata
gap, not proof of the reported gesture failure's cause. The playable IPA uses
`BellpadGameOverlay.mm`, not the separate shell's picker. Do not lower the OS
target or claim the report fixed without supported-device evidence.
