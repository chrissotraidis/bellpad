# Legal and clean-room boundary

Last updated: 2026-08-04

Bellpad is an unofficial compatibility project. It is not affiliated with or endorsed by Nintendo. “Animal Crossing,” Nintendo, and GameCube names are used only to describe compatibility; their trademarks and copyrighted works remain their owners' property.

## Allowed inputs and code

- Publicly documented, independently reverse-engineered or decompiled code with a usable license.
- Independently written compatibility layers with verified provenance and license notices.
- User-supplied, legally obtained supported retail data used locally.
- Original Bellpad integration code and branding.

## Prohibited material

- Leaked proprietary source code or unauthorized development materials.
- Retail disc images, extracted retail assets, or playable derived archives in Git, releases, documentation, fixtures, CI artifacts, app bundles, or IPAs.
- User saves, credentials, signing certificates, provisioning profiles, or private keys.
- Unlicensed code copied from reference projects.

HarkinianPad-owned integration code is all-rights-reserved by default and is therefore an architecture/UX reference only. ACreTeam `forest` currently tracks a 16 MiB `aram.bin`; Bellpad will not reuse or redistribute it unless its generation and contents are proven clean and necessary.

## Distribution model

The application is ROM-free. A user selects their own supported image after installation. Validation and any indexing/extraction occur inside that user's app container. Release audits must reject original or derived copyrighted game data.

Gameplay screenshots may be retained solely as documentation when captured from
locally supplied data. They are not game-data files or extracted assets, and do
not change the rule that disc images, saves, extracted assets, and playable
derived archives must never be committed or distributed.

Bellpad may embed non-copyrightable compatibility metadata such as expected file
lengths and cryptographic fingerprints. It never embeds bytes from the retail
image; validation streams user-owned data locally and retains no hash input in
Git, fixtures, logs, bundles, or release artifacts.

## Original branding

The Bellpad app icon was generated from a text-only brief with no retail image,
official artwork, character, logo, typography, or third-party icon supplied as
input. It uses an original brass handbell and abstract folk-art sunburst and
deliberately excludes official leaves, houses, currency bags, characters, and
platform marks. The source constraints and generation provenance are recorded
beside the tracked 1024×1024 icon.

## License handling

Every incorporated upstream is pinned. `upstreams.lock.json` records inspected
top-level projects, while `product-dependencies.lock.json` records every
non-system implementation component linked into Apple product binaries,
including version/commit, source or package SHA-256, purpose, reused component,
required changes, and disposition. `THIRD_PARTY_NOTICES.txt` reproduces the
applicable license texts and is installed into macOS, iOS, and iPadOS product
bundles, including the separate BSD terms for SDL's compiled HIDAPI and
yuv2rgb portions. Build and package audits require a byte-identical notice
file.

Bellpad's root `LICENSE` describes the repository's mixed-license boundary and
does not invent an outbound license for original files whose authors have not
provided one. “CC0” applies only to rights the contributors can waive; it does
not grant Nintendo assets, trademarks, patents, or other third-party rights.

This document records project policy and provenance; it is not legal advice.
