# Reference patches

These patches preserve small, evidence-backed changes against pinned upstream research baselines. They are not applied automatically and do not turn the reference port into the final Bellpad architecture.

`pc-port/0001-handle-aligned-read-tail.patch` applies to `birabittoh/ACGC-PC-Port` commit `915fb86ba9a6c2144dabda9143d93af7a3f92be7`:

```sh
git -C ref/upstream/acgc-64bit apply --unidiff-zero \
  ../../../patches/pc-port/0001-handle-aligned-read-tail.patch
```

The affected `pc/` compatibility-layer code is MIT-licensed by that upstream. The patch contains no game data.

`pc-port/0002-latch-keyboard-button-edges.patch` preserves non-repeating
keyboard button-down events until the next `PADRead`. This prevents a short
native event from falling entirely between GameCube pad polls and proves the
edge/state split required by the future shared touch/controller input layer.

Both patches are applied idempotently by:

```sh
./scripts/fetch-desktop-baseline.sh
```

`pc-port/0010-lock-simulation-to-native-60hz.patch` removes the accidental
desktop 2×/uncapped paths and constrains the current coupled game/presentation
loop to its native 60 Hz cadence. High-refresh presentation remains future
work and must not add simulation ticks.

`pc-port/0011-package-playable-macos-app.patch` packages the actual ARM64 game
core as an opt-in `Bellpad.app`, adds a native macOS disc picker, validates an
explicit image as GAFE01 disc 0 revision 0, and resolves its two clean shader
files from bundle resources. It does not add or copy retail data. Build it with
`./scripts/build-playable-macos-app.sh`.

`pc-port/0012-use-application-support-on-macos.patch` creates and enters
`~/Library/Application Support/Bellpad` before loading settings or saves. A
development-only `BELLPAD_DATA_HOME` override enables isolated persistence
tests. Disc and shader paths remain absolute/bundle-resolved; no retail data is
copied into Application Support by this patch.

`pc-port/0013-size-gx-objects-for-aurora.patch` expands the PC-side opaque
`GXTlutObj` storage to Aurora's required size. The existing `GXTexObj` storage
was already larger than Aurora's implementation. This makes the compiled core
safe for an Aurora link without changing the GameCube-target structure sizes.

`pc-port/0017-connect-aurora-keyboard-and-virtual-pad.patch` supplies the
desktop keyboard defaults that Aurora deliberately leaves unbound, preserves
an existing user mapping when present, and forwards Bellpad's normalized
virtual-pad state into Aurora's PAD merger. The same API boundary now accepts
desktop diagnostics and the future iPhone/iPad touch overlay without separate
game-facing input implementations.

`pc-port/0018-fix-aurora-colors-and-dialogue.patch` unpacks N64 primitive and
environment colors explicitly before passing them to Aurora, avoiding the
little-endian union layout that reversed RGBA channels. It also routes message
glyphs through the working polygon-font path and reinstalls the screen-space
font matrix after the transformed message window. Runtime comparison against
the OpenGL oracle verifies correctly colored, positioned multi-line K.K. text.

`pc-port/0019-pull-normalized-input-on-game-thread.patch` polls Bellpad's
mutex-protected normalized snapshot from the Aurora game thread before event
processing, then updates Aurora's virtual PAD there. A weak false-returning
fallback keeps the standalone convergence executable independent until it is
linked with the strong UIKit/AppKit product implementation. This avoids writing
Aurora's unguarded virtual-pad storage from UIKit controller/touch callbacks.

`pc-port/0023-make-gci-save-commits-durable.patch` flushes and synchronizes a
complete temporary GCI before rotating backups and atomically renaming it into
place. Apple/POSIX builds then synchronize the parent directory so the rename
survives interruption; Windows uses `_commit` for the file and retains the
existing replacement behavior.

`pc-port/0024-pause-audio-with-aurora-lifecycle.patch` consumes Aurora's
pause/unpause events and pauses or resumes the SDL3 audio stream. Aurora remains
the single owner of UIKit/window lifecycle and presentation state.

`pc-port/0025-use-prebuilt-dawn-for-ios-device.patch` keeps source-built Dawn
for iOS Simulator, where Aurora publishes no compatible archive, and selects
Aurora's pinned prebuilt `ios-arm64` Dawn package for physical-device builds.
Both routes retain static linkage and the same Aurora/Metal API boundary.

`pc-port/0026-connect-mobile-render-resolution.patch` polls Bellpad's persisted
mobile render-resolution preference on the game thread and applies it through
Aurora's framebuffer-scale API. Native follows the Metal drawable; 1× through
4× change the internal framebuffer without changing the fixed 60 Hz simulation.

`pc-port/0027-resume-audio-after-ios-activation.patch` consumes Bellpad's
one-shot UIKit resign/activation edges on the game thread. This pauses audio
when UIKit actually resigns active and resumes only after
`UIApplicationDidBecomeActive`; Aurora's earlier window-unpause event can occur
before iOS finishes the audio interruption, causing CoreAudio to remain paused.

`aurora/0001-complete-acgc-gx-compatibility.patch` applies to Aurora commit
`5027ed63a73dfba28de9eceed00481fb09a19c35`. It implements the five GX calls
used by the compiled game core that the pinned Aurora library did not export:
software-FIFO frame abort, texture-copy clamping, scissor-box offset, the
source port's single-thread ownership contract, and hardware-counter fallback
for the original GP hang diagnostic. `./scripts/fetch-aurora.sh` applies the
ordered Aurora patch series idempotently.

`aurora/0002-support-host-endian-tluts.patch` makes palette provenance explicit
for source ports that generate or byte-swap 16-bit TLUT entries in host memory.

`aurora/0003-fix-emu64-texture-lifetime-and-batching.patch` applies that
byte-order contract to static as well as dynamic paletted textures, connects
`GXInvalidateTexAll` to Aurora's cache invalidation, and disables draw merging
for the emu64 integration until the merge key represents reused texture and
matrix dependencies. The patch contains no game data.

`aurora/0004-correct-webgpu-front-face-winding.patch` selects counter-clockwise
front faces for the WebGPU render target. A controlled title-scene comparison
showed that Aurora's clockwise setting culled the visible side of the game's
geometry; disabling culling restored the scene, and the corrected winding
restored it while preserving the game's requested front/back cull modes.
