# Maintained sources and reproducibility

BellPad remains the same app repository, product, bundle ID (`dev.bellpad.app`),
issues and release URLs. This migration does not upgrade upstream, change game
behavior or grant new licenses. The later owner-requested controls/reporting
refinements are delivered as iPhone/iPad Preview 3 (build 6). macOS is a local playable baseline; the native shell and
Aurora convergence/probe executables are development targets.

## Source ownership and exact baseline

| Component | Upstream base | Maintained source |
|---|---|---|
| Game and PC layer | [birabittoh/ACGC-PC-Port](https://github.com/birabittoh/ACGC-PC-Port) `915fb86ba9a6c2144dabda9143d93af7a3f92be7` | [chrissotraidis/ACGC-PC-Port](https://github.com/chrissotraidis/ACGC-PC-Port/tree/bellpad/diagnostics-controls), `source/acgc-64bit`, `dbbb789e3404c94fe17520fb7ad3f048a3870cdc` |
| Aurora | [encounter/aurora](https://github.com/encounter/aurora) `5027ed63a73dfba28de9eceed00481fb09a19c35` | [chrissotraidis/aurora](https://github.com/chrissotraidis/aurora/tree/bellpad/apple), `source/aurora`, `5a0b160e4bcc0a37316f55a02c0bb4a7e3ddfd67` |

Both fork-parent relationships were verified through GitHub. The PC port retains
FlyingMeta and ACreTeam history/credit; the Aurora fork retains encounter history.
`sources.lock.json` records immutable gitlinks and trees. `upstreams.lock.json`
continues to describe research/reference upstream bases, while
`product-dependencies.lock.json` describes linked third-party dependencies.
Reference-only forest, HarkinianPad, Vita and Android trees are not imported.

The old app baseline is `c2bcbdedb1aa9b512c41f4a213716d1e085fb446` (Preview 2).
All 50 PC-port and six Aurora patches map to ordinary source commits in
[source-maintenance/migration.json](source-maintenance/migration.json).
`python3 scripts/verify-migration.py` independently replays the historical patches
in temporary repositories and checks Git tree hashes, including file modes.
The migration checkpoint commits add only `BELLPAD.md` and build-output ignore
rules to those prepared trees. A later, separately authorized iOS controls and
diagnostics pass advances the PC pin by one ordinary commit: CMake adds the
product diagnostics implementation, and the existing Aurora log callback and
frame loop call its diagnostics bridge. No upstream revision or game algorithm
changes. Aurora remains at the parity checkpoint. The previous local PC checkout contained one extra blank line
in `emu64.c`; this is recorded and excluded from the reproducible baseline.
The old ignored checkouts are preserved and no longer consumed by builds.

## Build paths

- The playable macOS SDL2/OpenGL baseline and desktop tests consume
  `source/acgc-64bit`; SDL2 is a host dependency.
- The iPhone/iPad product and Simulator consume that same source plus
  `source/aurora` and Bellpad's tracked `apple/ios/BellpadGameOverlay.mm` and
  platform validators. Device uses hash-pinned prebuilt Dawn; Simulator builds
  the pinned Dawn source. Neither path embeds a game image.
- macOS Aurora, core/GX/platform probes and sanitizer paths consume the same
  maintained pins. Their existence is not a claim of another released product.
- The standalone Apple shell uses tracked `apple/` and `src/platform/` source;
  it is not the playable IPA implementation.

`fetch-desktop-baseline.sh` and `fetch-aurora.sh` now initialize missing submodules
and verify commits, gitlinks, URLs, trees and clean source. They refuse to reset
existing mismatched/dirty sources. Do not delete local work to satisfy a check.
All ordinary builds consume source directly. The `patches/` directory is retained
only for historical comparison; it is not a production preparation input.

Aurora still contains upstream dependency-package preparation: two SDL Android
patches (Android-only compiled paths), plus optional zlib-ng and RmlUi patches.
Bellpad's Apple product disables zlib-ng/RmlUi; those optional paths are not
shipping features. The SDL package scripts may modify Android source files in
the fetched archive, but do not change Apple-compiled source. Owner: Aurora's
upstream dependency integration. Validate this exception against a pristine SDL
archive and rerun the existing controller regression when changing the pin.
There is no game-source generator in the normal Apple build. CMake's generated
headers/shaders and Dawn build outputs are build products, not a private game
source input. Toolchain-dependent binaries are not claimed byte-reproducible.

## Updating source and contributing

```sh
git clone --recurse-submodules https://github.com/chrissotraidis/bellpad.git
cd bellpad
python3 scripts/maintained-sources.py verify
./scripts/verify-release-candidate.sh
```

Work on the component's `bellpad/apple` branch, compare against its recorded
upstream base, and commit fixes there. Push the dependency commit, select it in
the app submodule, update its `commit` and `tree` in `sources.lock.json`, stage
the gitlink, and run the checks. Keep the historical migration mapping unchanged.
Upstream upgrades require a separate review. Never use `submodule update --remote`
for a release or silently follow the fork default. App-specific and uncertain
bugs stay with Bellpad; only route a demonstrated upstream defect with its pin
and useful logs, and only with authorization to contact that project.

## Source delivery and license boundary

From a clean committed checkout:

```sh
python3 scripts/source-archive.py /tmp/Bellpad-source.tar.gz
mkdir /tmp/Bellpad-source-restored
tar -xzf /tmp/Bellpad-source.tar.gz -C /tmp/Bellpad-source-restored
python3 /tmp/Bellpad-source-restored/scripts/maintained-sources.py verify
```

This exports the exact app and both complete maintained component trees with
per-file SHA-256/modes and source identities. Gzip timestamps and filenames are
normalized, so repeated exports from the same clean commits are identical. It never copies ignored build
folders, ROMs, saves, signing material or the private checkout. Verification and
modified-source availability work without Git or network. Normal build scripts
also accept a verified export. Building still requires Xcode, host libraries and
the externally hash-pinned dependencies; the archive is **not a fully offline
SDK/dependency cache**. GitHub's automatic app ZIP omits submodule contents, so Preview 3
attaches this explicit source archive and checksums.
Every packaged product now includes `SourceProvenance.json` beside its component
`ThirdPartyNotices.txt`. Provenance binds the unsigned executable hash and bundle
identity to verified sources; offline exports are checked before provenance is
created or accepted. Development changes are marked and cannot be packaged as a
clean release. Signing changes the executable bytes; sign a private copy of the
audited unsigned app and retain both artifact hashes.

Upstream CC0/MIT, Aurora MIT, and per-component notices are preserved. Bellpad's
original changes retain the existing no-outbound-license terms; no blanket grant
is added. CC0 contributors cannot waive third-party rights in reconstructed game
material. That existing rights question remains open; a fork relationship and
ROM-free packaging do not resolve it. The current linked-component ledger does
not select GPL/AGPL code or an LGPL runtime; FreeType uses its FreeType License
option. This is scoped provenance evidence, not a general legal clearance or a
claim that Preview 2 has gained a new source asset.

## Rollback and acceptance

Before migration, a private full checkout backup (including Git history, ignored
nested source/builds, local changes, private inputs and accepted packages) was
copied and independently restored on the same physical disk. SHA-256 and mode
manifests match across 171,114 entries. A Git bundle was verified separately.
The anonymous Preview 2 download matches local and published SHA-256
`d9e9ebd5d17fa360de1775cf60deaccd8ca5b196b09842ea633a8ad353a8aaea`.
Private recovery locations are in the maintainer handoff, not this public guide.

To rehearse source rollback without touching the active checkout:

```sh
git clone /path/to/private/bellpad.bundle /path/to/disposable/rollback
git -C /path/to/disposable/rollback checkout --detach c2bcbdedb1aa9b512c41f4a213716d1e085fb446
cd /path/to/disposable/rollback
./scripts/fetch-desktop-baseline.sh
./scripts/fetch-aurora.sh
```

The full private restored checkout supplies the prior build outputs and inputs;
the bundle alone does not contain ignored files. Reinstall an accepted app only
in place with the same bundle/signing identity after a full app-data backup.
Never uninstall or clear data as rollback. This task does not install on physical
hardware, alter saves, or claim fresh gameplay/controller acceptance. See the
[qualification handoff](MODERNIZATION_HANDOFF.md) for actual validation results
and remaining release/reporter gates.
