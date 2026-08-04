# Architecture

Last updated: 2026-08-04

## Layers

```text
UIKit / Files / GCController / AVAudioSession
                    |
       Bellpad Apple platform adapter
                    |
  normalized input | lifecycle | paths | keyboard
                    |
       portable Animal Crossing game core
        (ACreTeam decomp + port fixes)
                    |
 Aurora OS / VI / MTX / PAD / DVD / CARD / GX
                    |
 SDL3 + nod + Dawn/WebGPU + CoreAudio + Metal
```

### Frame pacing contract

The current source port advances game simulation from VI retraces. Its core
therefore runs at a fixed 60 Hz NTSC cadence: 120 Hz or uncapped execution is
an overclock that doubles gameplay speed, while reducing the coupled loop to
30 Hz would halve it. Bellpad must request a 60 Hz mobile display cadence even
on ProMotion hardware. Any later 30/60/120 Hz presentation modes require a
separate render scheduler and interpolation that never changes the number of
simulation ticks.

The app executes compiled C/C++ game code directly on Apple ARM64. Aurora is a source-level SDK compatibility layer, not a CPU/GPU emulator. The existing WebAssembly port is research material only and will not be embedded.

The current implementation has two deliberately visible tracks. The macOS `Bellpad.app` remains the complete playable ARM64 behavior oracle using temporary SDL2/OpenGL. The Aurora production track now packages the complete game as both a native macOS convergence executable and a universal iOS/iPadOS `Bellpad.app`. On mobile, SDL3/Aurora owns `UIApplicationMain`, the UIKit window, lifecycle events, and the Metal surface; Bellpad attaches its native controls to that existing view. Representative gameplay rendering and product services are not yet complete, so the OpenGL oracle remains until those gates pass.

## Address and data model

Host pointers are native-width. Game addresses, segmented N64 display-list addresses, file offsets, save fields, and on-disc structures remain explicitly fixed-width. Conversion crosses named, bounds-checked APIs; integer-to-pointer casts are not used as a generic address model.

The first Apple Clang portability pass makes DVD/audio callbacks, task payload copies, heap headers, memory archives, ARAM, retrace messages, allocation APIs, and Famicom buffers native-width where they carry host state. It deliberately does not widen serialized or guest-visible fields. Both Apple Clang and GCC builds pass. A bounded ASan/UBSan title run subsequently repaired native heap-header alignment, 64-bit audio-message destinations, sentinel indexing, array aliasing, and resampler-state serialization; the complete guest/native boundary inventory and broader sanitized gameplay remain required evidence.

Legacy 32-bit GBI fields are recovered only when their low bits fall inside a measured host range. The arena interval is explicit, and macOS derives the exact loaded image interval from non-`__PAGEZERO` Mach-O segments plus the dyld slide. Recovery handles ranges that cross a 4 GiB low-word boundary. Unknown low texture or TLUT values are rejected before content hashing/decoding instead of being combined with guessed upper bits.

Host object pools must be sized for the largest native derived type, not the 32-bit base layout. The structure-actor pool therefore uses independently padded 0x400-byte slots: measured ARM64 layouts are 0x340 for the base and 0x348 for Shrine. This storage-only padding does not alter serialized or guest-visible structures.

Static display lists must ultimately be registered with the resolver at startup rather than detected from executable placement alone. The exact executable-range check is a bounded desktop-baseline safeguard, not the final guest-address model. ARAM becomes an allocated host buffer whose guest addresses are offsets, not truncated host pointers.

## Graphics

Animal Crossing retains an N64 display-list layer (`emu64`) that emits GameCube GX operations. The intended production path is:

```text
N64 GBI display list → emu64 → GX → Aurora → Dawn/WebGPU → Metal
```

The OpenGL 3.3 renderer remains a temporary reference for Milestone 1. It is unsuitable as the final iOS path because iOS exposes OpenGL ES rather than desktop OpenGL 3.3 and OpenGL ES is deprecated on Apple platforms.

The mobile product links Aurora, Dawn, SDL3, libpng, and the remaining bundled
third-party implementation code statically. Only Apple system frameworks and
libraries under `/usr/lib` may remain dynamic. Build and IPA packaging gates
reject any other install name and every `LC_RPATH`, so a simulator-accessible
checkout directory cannot accidentally become a device runtime dependency.

Pinned Aurora has now crossed the first platform gate. Its GX example runs on
macOS ARM64 with Dawn selecting the Apple M2 Metal adapter, and an independently
linked ARM64 iOS Simulator build renders on both iPhone and iPad simulators.
This proves `GX → Dawn/WebGPU → Metal` is available on every intended Apple
platform family. A separate compiled-object audit now inventories 112 GX/GD
symbols required by 3,905 game-core objects; the pinned Bellpad Aurora patch
provides all 112. The five additions preserve software-FIFO abort behavior,
texture-copy clamp state, scissor-box offset commands, single-render-thread
ownership semantics, and a zeroed fallback for unavailable hardware-only hang
counters.

The structure boundary is compiled and checked as well. GX value types match
size/alignment exactly. The core's opaque `GXTexObj` storage is 88 bytes versus
Aurora's 64-byte implementation, and its PC-only `GXTlutObj` storage is expanded
to Aurora's required 40 bytes. This closes symbol and object-storage gates, but
was sufficient to link the real target. A runtime PAD crash exposed a second
ABI boundary: Aurora's host `PADStatus` is 16 bytes rather than the SDK's 12,
so the game-side array now includes Aurora's extension field and retains the
same stride. With that fixed, the complete game reaches the interactive title
menu through Metal. Explicit JSystem EFB clearing now prevents successive frames
from accumulating. Aurora's static and dynamic palette paths share the same
byte-order normalization, and `GXInvalidateTexAll` bounds the static texture
cache at the frame boundary. A culling isolation test proved matrices and vertex
placement were sound: disabling culling restored every missing scene component,
and selecting counter-clockwise WebGPU front faces retained them with normal
front/back culling. N64 primitive/environment colors are unpacked explicitly
before crossing the Aurora boundary so their byte significance is independent
of host endianness. Message glyphs use the working polygon-font path and restore
the identity font model-view after the transformed window is drawn. This makes
the K.K. scene and multi-line dialogue agree with the OpenGL oracle; water,
choices, and representative gameplay scenes remain in the renderer audit.

The entire game source has dedicated `AURORA` compile and link targets.
That build follows the original JSystem frame lifecycle, retains host/ARM64
pointer, heap, color, texture-cache, and `GXEnd` behavior, and imports none of
the legacy OpenGL batch/frame hooks or renderer counters. One source-level
extension remains deliberately explicit: `AuroraInitTlutObjHost` marks palettes
generated by `emu64` in native byte order. Aurora carries that flag through its
GX command stream and normalizes entries before both static and dynamic texture conversion; palettes
read from retail GameCube data continue through standard big-endian
`GXInitTlutObj`. This avoids renderer-specific global state and preserves the
same intended palette semantics on macOS, iOS, and iPadOS. Corrected title/tree
colors provide runtime evidence for that boundary; the separate winding fix now
provides complete title-scene geometry, and the explicit color/font boundary
produces correctly colored and positioned K.K. dialogue. Broader scene output
remains under audit.

The PC integration's fixNES emulator produces a linear 256×240 host framebuffer
with red in the low RGB565 bits. The Aurora path crops the same eight top rows as
the proven OpenGL presenter, swaps the red/blue bit fields, writes big-endian
pixels in GameCube 4×4 tile order, invalidates the GX texture cache, and draws a
nearest-filtered 256×224 quad through Aurora. The existing NES aspect preference
selects Aurora's stretch or 4:3-fit viewport policy and cleanup restores the
normal game policy. The conversion is deterministic and compiler-tested on all
Apple targets; an actual NES-furniture session is still required before runtime
rendering is marked passed.

The convergence target deliberately uses SDL3 only. Its audio adapter exposes
the game's 32 kHz stereo DMA stream through an SDL3/CoreAudio stream and producer
thread. Aurora owns window creation, event acquisition, frame begin/end, Dawn,
and Metal. JSystem's GameCube VI-message wait is bypassed on this synchronous
host path because it otherwise deadlocks before the first draw. The Aurora executable installs keyboard defaults
only when no user mapping exists. Touch and GameController callbacks write one
mutex-protected Bellpad state using the exact GameCube PAD button mask; they never
call Aurora from UIKit's thread. Instead, patch 19 asks the strong product-side
`bellpad_copy_normalized_pad_state` function for a snapshot from the game thread,
then updates Aurora's virtual PAD before event processing. The standalone macOS
game provides a weak false-returning fallback; the mobile game bundle links
Bellpad's strong implementation directly.
This avoids a data race in Aurora's unguarded virtual-pad storage and preserves
one game-facing input representation. Rising button edges are retained until a
game-thread snapshot consumes them, preventing very short UIKit taps from falling
between 60 Hz polls.

Aurora's released Dawn archive for iOS is device-platform only. Simulator builds
therefore compile Dawn from source with Ninja, vendored SDL3, protobuf disabled,
and Tint IR binary serialization disabled. At pinned commit `5027ed63…`, the
Xcode generator leaves Dawn object libraries without the final archives needed
by the app link, while Ninja emits `libwebgpu_dawn.a` correctly. Xcode remains
the product build/sign/package tool; this implementation detail is isolated to
the compatibility-layer dependency build until an upstream universal package
or generator fix is available.

## Disc and assets

The app bundle contains no retail data. The user selects a supported image through Files. The implemented raw-image path reads directly from a private Application Support copy; nod-backed compressed containers and a hash-versioned derived index remain future work. Any later derived cache stays local, removable, and excluded from source and release packages.

The first product boundary is implemented: AppKit uses `NSOpenPanel`, UIKit uses
`UIDocumentPickerViewController`, and both call one portable validator. It reads
the first 0x20 bytes of raw `.iso`/`.gcm`, checks the GameCube magic at `0x1C`,
the six-byte game ID, disc number, and revision byte, requires either the exact
trimmed-payload or standard full-disc length, and streams SHA-256 over the entire
meaningful payload. The full and trimmed forms share that payload fingerprint;
full-disc padding is not executed game content. UIKit balances security-scoped
access around source validation and copy.
It copies to `Game Data/Animal Crossing.importing.iso`, validates the completed
copy, and atomically installs `Game Data/Animal Crossing.iso` under Bellpad's
Application Support directory. Failure removes only staging and preserves the
previous retained image. Normal launch validates and reuses that path before
presenting Files; the development-only explicit `--disc` argument bypasses it.
CISO/RVZ and nod indexing remain unavailable rather than pretending the raw
reader supports compressed containers.

SDL3's traditional iOS entry point currently invokes the game main function on
UIKit's main thread. While the core waits for first-run import, Bellpad pumps the
default and UI-tracking run-loop modes so the document picker, security-scoped
copy progress, and modal dismissal remain responsive. Once import completes,
normal SDL3/Aurora event ownership resumes; no second application delegate or
renderer is created. Mid-game save import/export uses the same ownership rule:
UIKit keeps pumping while the Aurora render loop is intentionally held, and Metal
submission resumes only after the system document picker has left the window.

## Saves

GCI-folder mode is the initial canonical store because it gives one file per save and aligns with Dolphin import/export. Writes go to a temporary sibling, are flushed and synchronized, then atomically replace the canonical file after three previous generations rotate; the parent directory is synchronized on Apple/POSIX hosts. Load-time checksums and orphan-temp/backup recovery reject or repair interrupted saves. The same Bell/Cove GCI has completed desktop creation/relaunch, iPhone rewrite/relaunch, an isolated Dolphin 5.0-17995 GCI-folder read, and Bellpad pre-boot installation/loading of the Dolphin-managed copy. Mobile export creates a validated immutable snapshot for Files; real iPhone/iPad exports matched the canonical bytes. Import accepts only exact-size GAFE01 version 5/6 GCI data with the expected block count, town-ID mask, and zero-sum town checksum; it durably stages the file, installs it before the next game startup, and retains the previous canonical file as a pre-import backup so live game state is never swapped underneath the core. A fully UI-driven iPhone Files import selected, staged, and installed the canonical byte-identical GCI before normal startup. A versioned in-place Simulator update preserved the exact save and retained-image inodes/hashes plus `NSUserDefaults`, and the replacement bundle loaded that state normally. The retail save dialogue and recovery UI remain validation gates.

## Platform integration

- SDL3's iOS main callback owns the game thread and UIKit lifecycle. Bellpad does not create a second application delegate, window, Metal view, or simulation clock.
- Aurora/Dawn renders through SDL3's existing `CAMetalLayer`; the UIKit overlay is transparent and returns hits only for controls, leaving the render view and keyboard/event path intact.
- The full desktop core also has an opt-in native macOS app-bundle target. Its `NSOpenPanel` and explicit disc-path API launch real game code, shaders resolve from bundle resources, and settings/GCI paths live under Application Support. This is the playable migration baseline; it still uses SDL2/OpenGL and does not yet provide user-facing save import/export.
- UIKit owns the adaptive touch overlay. Compact sizing is computed from actual safe-area width/height for iPhone and resizable iPad windows; expanded iPad sizing is visibly proven over the real game target. `NSUserDefaults` stores separate iPhone/iPad opacity, size, manual visibility, normalized control centers, and render resolution. Move mode disables gameplay input while dragging, clamps every control to the current safe area, and reset removes only that device-class profile. The game thread polls the resolution preference and calls Aurora's framebuffer-scale API: Native follows the full drawable, while 1× through 4× select scaled internal EFB dimensions without adding simulation ticks. A scale may supersample above the drawable or render below it depending on device pixels and aspect ratio.
- Touch and external-controller sources now target one portable, mutex-protected normalized GameCube state. Buttons are ORed, the strongest absolute value wins per stick axis, and the maximum analog trigger wins. The linked game-core adapter snapshots this state on the game thread before Aurora PAD/event processing rather than receiving UIKit callbacks directly.
- The touch source is cleared on resign-active. Presentation pauses while inactive and resumes on become-active. A physical controller hides touch on real devices while retaining an explicit user override; simulator virtual controllers do not hide the overlay so touch QA remains possible.
- The real mobile adapter observes the separated editor lifecycle and shows one native UIKit text-field proxy only while a game editor is active. UIKit callbacks append bounded UTF-8/Backspace/Enter events to a mutex-protected queue; the Aurora game thread drains them into the existing editor API before PAD/event work. UIKit never mutates game editor state directly, and the proxy never becomes the canonical text store. This path has passed the player-name editor on both simulator families; editor-specific behavior beyond names remains.
- One opaque, original 1024×1024 icon is the branding source of truth. Apple's `actool` compiles it into `Assets.car` plus iPhone/iPad primary-icon renditions and plist metadata; the macOS build deterministically resizes the same source into the standard 16–1024 px iconset before producing `Bellpad.icns`.
- Rendering uses the SDL/CAMetalLayer surface supplied to Dawn.
- The GameCube RTC is local civil time in 40.5 MHz ticks. A subsecond host wall-clock sample establishes the local epoch while an absolute SDL performance counter advances it without overflow-prone multiplication. The game thread refreshes the offset every minute and immediately after iOS activation, `UIApplicationSignificantTimeChangeNotification`, or `NSSystemTimeZoneDidChangeNotification`; UIKit only latches those edges and never mutates game time directly.
- Backgrounding pauses presentation/audio and clears transient input. Aurora restores the Metal presentation path; a UIKit activation edge is consumed on the game thread to resume CoreAudio only after `UIApplicationDidBecomeActive`, avoiding an early resume that iOS immediately re-pauses. Bellpad deliberately does not manufacture an out-of-band Animal Crossing save because the game's save routine has gameplay-visible side effects.
