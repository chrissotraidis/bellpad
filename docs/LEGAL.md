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

## Original branding

The Bellpad app icon was generated from a text-only brief with no retail image,
official artwork, character, logo, typography, or third-party icon supplied as
input. It uses an original brass handbell and abstract folk-art sunburst and
deliberately excludes official leaves, houses, currency bags, characters, and
platform marks. The source constraints and generation provenance are recorded
beside the tracked 1024×1024 icon.

## License handling

Every incorporated upstream is pinned. Its license text, notices, exact commit, modifications, and purpose are included in release materials. “CC0” applies only to rights the contributors can waive; it does not grant Nintendo assets, trademarks, patents, or other third-party rights.

This document records project policy and provenance; it is not legal advice.
