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
