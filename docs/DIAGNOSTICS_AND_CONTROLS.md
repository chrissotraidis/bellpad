# Controls and diagnostic reports

Build 6 is a local review candidate, not a public release. The owner requested
this pass after the unchanged-product source migration and build 3 iPad update.
SunPad's grouped native menu and user-initiated reporting flow informed the design;
BellPad's runtime, existing save actions and persisted settings remain its own.

The three-dot menu groups render resolution/frame rate, controls, game data and
saves, diagnostic sharing and support. Display changes retain Native/1×/2×/3×/4×.
Export/import Dolphin GCI, change/reimport ISO/GCM, and confirmed removal retain
their existing implementation and validation. No new data migration is performed.

The movement stick is hidden until a thumb lands in empty space within the left
45% and lower 60% of the safe area. It appears exactly at that contact, starts
neutral, and follows only that thumb until release/cancellation, even outside
the activation region. Other controls take priority, so simultaneous buttons and
the fixed camera stick remain usable. Lift, open a menu, enter native text,
background, hide controls, connect an auto-hiding controller or resize/rotate to
release movement. Ordinary layout passes retain the active origin. The layout
editor shows the saved Move preview and adjusts its size; gameplay origins never
rewrite stored layout positions. Existing opacity, size and dead-zone settings
still apply.

Touch settings retain opacity, overall and per-control size, normalized positions,
hide controls and per-device reset. Editing stays usable with a connected controller,
identifies the selected control and has an always-visible Done button. Drag the
panel title to uncover controls while editing. Opening menus,
hiding controls, backgrounding and entering edit mode clear held touch input.
New preferences are optional haptics and a radial touch-stick dead zone (default 0,
range 0–30%). Automatic hiding with a controller remains the default; it can now
be disabled. Physical controllers remain owned by Aurora/SDL3; no duplicate UIKit
input path or controller remapping system is introduced. Haptics depend on hardware.

## What the report contains

Use **Report a Problem…** to describe the problem and its reproduction,
then choose **Share Report…** or **Report on GitHub** from the same prompt.
Both prepare diagnostics; GitHub opens a prefilled draft for your review. Attach
the diagnostic file using Share Report before submitting. Answers remain in
memory while the app runs so both actions can reuse them. The initial
game-data screen also exposes reports for picker/import problems. Opening the GitHub draft does not submit a report or upload a file. Review the text before sharing.

- Version/build, public source commit/component pins, executable identity,
  toolchain, OS version and hardware model (not the device name/identifier).
- Timestamped session IDs and import validation, save recovery/import/export,
  audio, lifecycle, controller connection and menu events.
- Aurora log callback messages and SDL warnings/errors, with repetition counts
  and a 128-kind bound. Additional event kinds are counted, not accumulated.
- A minute-level frame-loop/thermal/active/controller summary and the current
  report's display/control context. The optional FPS display measures the VI
  event-loop rate; it is not GPU timing or a performance benchmark.

Current and previous sessions each retain at most two roughly 256 KiB log segments.
A single report file is overwritten on export. Logs live in Application Support
under `Bellpad/Diagnostics`. Writes and snapshots are serialized; storage errors
must not crash the game. Reports never enumerate or attach game images, saves,
keyboard input or signing data. Paths, URLs, email addresses and UUIDs are redacted
from messages. User-written descriptions should still be reviewed before sharing.

This is not a signal-handler crash reporter or a complete stdout transcript.
An abrupt crash can leave the final breadcrumb incomplete; iOS crash reports may
still be necessary. Private game names or other personal prose typed into the
report description cannot all be inferred/redacted automatically.

## Verification

`./scripts/test-diagnostics.sh` checks privacy filters, repeated/unique event bounds,
concurrent writes, real rotation, bounded report generation and unwritable storage.
It runs in the source-release suite/CI.

`BELLPAD_TEST_SIMULATOR=<isolated-booted-id> ./scripts/test-ios-overlay.sh`
uses a separate `dev.bellpad.overlaytests` app without game data. It exercises the
real UIKit overlay's menu/data-action inventory, held-input clearing, edit-mode
input suppression, connected-controller layout editing, auto-hide override,
native text transitions and iPhone/iPad bounds. It does not claim real finger,
Bluetooth, haptic, share-destination or gameplay acceptance.

Post-migration PC dependency changes include commit
`f918823fd8743bf2e1dc67830a161469844cc020` on `bellpad/diagnostics-controls`:
the iOS build links the product logger and forwards existing Aurora logs/frame
notifications. Build 5 selects `dbbb789e3404c94fe17520fb7ad3f048a3870cdc`, which also corrects visible Apple runtime names to BellPad without changing storage paths. The upstream base and Aurora pin are unchanged. See
[SOURCE_MAINTENANCE.md](SOURCE_MAINTENANCE.md) for pins, source export and rollback.
