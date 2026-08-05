# Technical debt and device findings

Last updated: 2026-08-05

This document tracks player-visible defects that still require diagnosis or
physical-device acceptance. A successful build, install, or live process is not
enough to close an item. Retail screenshots and user data remain outside Git.

## Data-safety boundary

- The first physical-iPad town is the canonical personal save on virtual memory
  card A. It must never be replaced by development data.
- A stopped-app snapshot of Bellpad's Application Support data and preferences
  was copied to ignored local storage under
  `ref/runtime-data/device-backups/20260804-231541-chris-ipad-pro/` and verified
  before this investigation began.
- Card B was empty in that snapshot. Do not inject a test town until Bellpad's
  card-selection behavior is proven to keep card A isolated and recoverable.
- Device installs remain in place. Do not uninstall Bellpad or clear its data as
  part of testing.

## P0: blocks normal play or risks player data

### Native text entry is not usable on physical iPad

Status: Simulator text path and GameCube keyboard rendering fixed; physical
keyboard-transition acceptance remains open.

- The train name editor displays Bellpad's native text proxy at the same time as
  the game's on-screen GameCube keyboard.
- The GameCube keyboard's character cells render blank.
- Backspace stopped working after detaching the keyboard case.
- Bellpad's Done button did not visibly finish the editor.
- Typed characters eventually reached the game and appeared in subsequent Rover
  dialogue, so commit is partially wired; presentation, deletion, completion,
  and hardware/software-keyboard transitions are not.
- The native proxy now retains visible typed text, mirrors Backspace locally,
  and safely clears itself between editor lifecycles without queuing accidental
  deletions. The corrected build compiles for Simulator and device.
- The isolated iPad Simulator editor now renders its prompt, cursor, and complete
  letter/punctuation grid. Native insertion changed both the proxy and game
  value, Backspace changed `Ada` to `Ad`, and Done exited to Rover dialogue
  while the process remained live. Patch 45 selects polygon glyphs for Aurora
  instead of the unsupported texture-rectangle primitive.
- Bellpad observes physical-keyboard disconnect while an editor is active and
  requests the software keyboard again. A real keyboard-case detach remains a
  physical-device acceptance gate; no Simulator host-keyboard capture is used.
- Required acceptance: software keyboard, attached hardware keyboard, detach
  while editing, Backspace, Return, Done, cancel/re-entry, player name, town
  name, and letter editor.

### Repeated gameplay actions

Status: not reproduced in the corrected build; physical-touch acceptance remains open.

- One mailbox interaction can replay more than once.
- House entry/exit and door-close sequences can replay two to four times.
- One fruit pickup can replay roughly four times.
- The input merger preserves a quick touch edge for exactly one emulated poll,
  then clears the latch. Its focused unit test verifies that the following poll
  is neutral.
- Headless iPad Simulator traces now cover the reported scenes without opening
  Simulator.app or capturing the Mac keyboard:
  - One bounded A edge drove the current player's mailbox through actions
    `1 -> 3 -> 4 -> 0` exactly once. It did not begin a second open cycle while
    left idle.
  - One bounded A edge drove the house actor through actions `1 -> 2 -> 3`
    exactly once and produced one interior load. Walking out produced one
    outdoor return.
  - One bounded B edge on a real dropped orange produced exactly one pickup
    request, one pickup setup, and one item-get sound. The orange was absent
    afterward and all three debugger breakpoints retained a hit count of one.
- These traces distinguish a single input edge and single simulation action
  from the earlier player-visible repetition. No speculative gameplay patch was
  added because the current corrected product does not exhibit the defect.
- Required acceptance: one short A tap produces exactly one action for mailbox,
  door, fruit, dialogue advance, inventory use, and menu selection.

### Missing game text, item icons, and inventory fields

Status: shared Aurora font cause fixed; populated-inventory acceptance pending.

- The train keyboard shows blank character cells.
- Inventory slots and item/name fields can appear blank or white even though the
  surrounding UI and player model render.
- Ordinary K.K. and Rover dialogue text renders in other scenes, so this is not
  a universal font failure.
- Patch 45 restores every Aurora font caller that previously used the blank
  texture-rectangle primitive while preserving its original display-list and
  matrix. The full GameCube keyboard grid is now visible in Simulator.
- The exact protected save copy loaded in Simulator, and its current pocket
  inventory is genuinely empty. That run cannot prove missing item icons; use a
  known populated local test town to verify inventory names and icons before
  closing this item.
- Required comparison: the same save and scene on the OpenGL behavior oracle,
  Aurora macOS, iPhone Simulator, iPad Simulator, and physical iPad.
- Candidate areas include indexed textures/TLUT state, texture-cache lifetime,
  copy/filter state, and scene-specific display-list coverage.

## P1: touch and settings usability

### Physical controller support needs hands-on acceptance

Status: implementation present; physical-device mapping proof pending.

- Bellpad already consumes extended GameController profiles and maps both
  sticks, A/B/X/Y, D-pad, Start, Z, analog L/R, and digital shoulder presses.
- A connected controller hides touch controls on a physical device; disconnect
  must clear controller state and restore touch without leaving a held input.
- Required acceptance: connect, launch, navigate, play, suspend/resume,
  disconnect/reconnect, and verify every GameCube input on the physical iPad.

### Controls cannot be resized individually

Status: implemented and Simulator-smoked; physical touch acceptance pending.

- The current Size slider applies one global scale to every touch control.
- Required behavior: while editing, select an individual button or stick and
  resize it without changing unrelated controls. Persist overrides separately
  for iPhone and iPad while retaining a usable global default.
- Move mode now lets a tap or drag select one control, highlights that selection,
  and enables a separate Selected size slider persisted per control and device
  class. The existing All sizes control remains available.
- Physical-controller input must remain merged and must not inherit touch-layout
  editing state.

### Move Controls remains active after settings closes

Status: fixed in the deployed build; physical acceptance pending.

- Closing the gear panel can leave layout editing enabled.
- Required behavior: closing settings always exits move mode, clears selection,
  clears transient touch input, and returns controls to gameplay immediately.
- Closing the gear panel and leaving it for a data/save action now use the same
  close path, which switches move mode off and clears the selected control.

### Reset This Device Layout has no confirmation

Status: fixed in the deployed build; physical acceptance pending.

- Required behavior: present a destructive-action confirmation naming the
  current device class. Cancel must leave every stored center and size unchanged.
- Reset now presents an iPad/iPhone-specific destructive confirmation; Cancel
  performs no reset, and confirmation also clears per-control sizes.

### Touch overlay obstructs the in-game keyboard

Status: fixed in Simulator; physical acceptance pending.

- The D-pad, sticks, and face buttons overlap the GameCube keyboard and its
  Backspace/OK regions.
- Required behavior: use an editor-specific touch layout or temporarily hide
  controls that are not needed for the active editor without making the editor
  impossible to operate when no hardware controller is attached.
- While native text entry is active, Bellpad now clears and hides gameplay
  controls plus the gear button, closes settings/move mode, and restores the
  overlay after the editor exits. Simulator screenshots prove both the hidden
  state and the unobscured GameCube keyboard.

## P1: platform settings

### Desktop graphics settings are exposed on iOS

Status: provenance confirmed and iOS behavior corrected.

- The inherited PC-port settings menu contains Display, VSync, FPS limit, MSAA,
  Resolution, texture preload, and NES aspect entries.
- These are port settings, not original GameCube options.
- Bellpad separately owns the native UIKit Render scale control.
- Required behavior: on iOS/iPadOS, hide desktop-only or ineffective settings
  and expose each supported graphics option in one place with one source of
  truth. MSAA must not imply a live change if Aurora requires restart or ignores
  the PC setting.
- Patch 44 removes the desktop Video tab from iOS builds. Audio and Gameplay
  remain available; Bellpad Settings is the sole iOS render-scale UI.

## P2: save-slot and test-town support

Status: card semantics confirmed; test-town data and runtime proof pending.

- The physical device currently contains one card-A GCI and no card-B GCI.
- In this port, card A is the player's home town and card B is the second town
  used by the game's travel flow. Card B is not a generic second selectable
  save slot: visiting can write both cards and mark the card-A player away.
- Locate or create a legally local further-along GCI, validate its game/version,
  and test it only in an isolated Simulator data container first.
- If card B is supported, back up card A again immediately before transfer,
  copy only the validated card-B file, read it back byte-for-byte, and prove that
  normal card-A launch still loads the personal town.

## Acceptance order

1. Preserve and re-verify the physical card-A backup.
2. Reproduce text, inventory, and repeated-action defects in an isolated
   Simulator profile.
3. Fix one input or rendering cause at a time with focused tests.
4. Validate signed in-place deployment without replacing device data.
5. Run physical touch, keyboard, controller, audio, lifecycle, and save/relaunch
   acceptance before closing any hardware item.

## Latest protected deployment

- The corrected Simulator and device products built successfully on 2026-08-04.
- An isolated iPad Simulator received byte-identical ROM and card-A copies and
  loaded the `Chris` player in `BUDAPEST`; the physical device was not used for
  development-state experiments.
- The signed device app was installed in place and launched as PID 4287.
- Card A matched SHA-256
  `6a91dc254f8af35e654ca28d6a40d4989a0399b907b8dbec45d4cacfec164773`
  before install, after install, after launch, and in a final readback on
  2026-08-05. PID 4287 remained live during that final check. Card B remained
  absent.
