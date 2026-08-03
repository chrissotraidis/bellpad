# Architecture

Last updated: 2026-08-03

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

## Address and data model

Host pointers are native-width. Game addresses, segmented N64 display-list addresses, file offsets, save fields, and on-disc structures remain explicitly fixed-width. Conversion crosses named, bounds-checked APIs; integer-to-pointer casts are not used as a generic address model.

The first Apple Clang portability pass makes DVD/audio callbacks, task payload copies, heap headers, memory archives, ARAM, retrace messages, allocation APIs, and Famicom buffers native-width where they carry host state. It deliberately does not widen serialized or guest-visible fields. Both Apple Clang and GCC builds pass, but sanitizers and the complete boundary inventory remain required evidence.

Legacy 32-bit GBI fields are recovered only when their low bits fall inside a measured host range. The arena interval is explicit, and macOS derives the exact loaded image interval from non-`__PAGEZERO` Mach-O segments plus the dyld slide. Recovery handles ranges that cross a 4 GiB low-word boundary. Unknown low texture or TLUT values are rejected before content hashing/decoding instead of being combined with guessed upper bits.

Host object pools must be sized for the largest native derived type, not the 32-bit base layout. The structure-actor pool therefore uses independently padded 0x400-byte slots: measured ARM64 layouts are 0x340 for the base and 0x348 for Shrine. This storage-only padding does not alter serialized or guest-visible structures.

Static display lists must ultimately be registered with the resolver at startup rather than detected from executable placement alone. The exact executable-range check is a bounded desktop-baseline safeguard, not the final guest-address model. ARAM becomes an allocated host buffer whose guest addresses are offsets, not truncated host pointers.

## Graphics

Animal Crossing retains an N64 display-list layer (`emu64`) that emits GameCube GX operations. The intended production path is:

```text
N64 GBI display list → emu64 → GX → Aurora → Dawn/WebGPU → Metal
```

The OpenGL 3.3 renderer remains a temporary reference for Milestone 1. It is unsuitable as the final iOS path because iOS exposes OpenGL ES rather than desktop OpenGL 3.3 and OpenGL ES is deprecated on Apple platforms.

Pinned Aurora has now crossed the first platform gate. Its GX example runs on
macOS ARM64 with Dawn selecting the Apple M2 Metal adapter, and an independently
linked ARM64 iOS Simulator build renders on both iPhone and iPad simulators.
This proves `GX → Dawn/WebGPU → Metal` is available on every intended Apple
platform family; it does not yet prove Animal Crossing's complete GX/GD call
surface or retained `emu64` display lists.

Aurora's released Dawn archive for iOS is device-platform only. Simulator builds
therefore compile Dawn from source with Ninja, vendored SDL3, protobuf disabled,
and Tint IR binary serialization disabled. At pinned commit `5027ed63…`, the
Xcode generator leaves Dawn object libraries without the final archives needed
by the app link, while Ninja emits `libwebgpu_dawn.a` correctly. Xcode remains
the product build/sign/package tool; this implementation detail is isolated to
the compatibility-layer dependency build until an upstream universal package
or generator fix is available.

## Disc and assets

The app bundle contains no retail data. The user selects a supported image through Files. A validator reads only the header and required metadata before a nod-backed disc reader indexes the filesystem. The initial preference is direct reading from a private Application Support copy or a durable security-scoped bookmark. Any derived cache is local, versioned by image hash, removable, and excluded from source and release packages.

The first product boundary is implemented: AppKit uses `NSOpenPanel`, UIKit uses
`UIDocumentPickerViewController`, and both call one portable validator. It reads
exactly the first 0x20 bytes of raw `.iso`/`.gcm`, checks the GameCube magic at
`0x1C`, the six-byte game ID, and revision byte, then closes the file. UIKit
balances security-scoped access around that read. No selected URL is persisted
and no image is copied yet. CISO/RVZ and hash verification wait for nod-backed
indexing and the final retention policy rather than pretending a raw header
reader supports compressed containers.

## Saves

GCI-folder mode is the initial canonical store because it gives one file per save and aligns with Dolphin import/export. Writes go to a temporary sibling, are flushed, validated, and atomically replaced; previous valid generations are retained. Save operations are serialized with lifecycle transitions.

## Platform integration

- The game loop will own game state on a dedicated thread or SDL main callback compatible with iOS. The current shell deliberately contains no second simulation clock.
- Bellpad now owns native AppKit and UIKit bundles. Their MetalKit views request 60 FPS, establish bundle/lifecycle ownership, and provide the surface that will be replaced or adopted by Aurora's Dawn path.
- UIKit owns the first adaptive touch overlay. Compact sizing is computed from actual safe-area width/height for iPhone and resizable iPad windows; an expanded layout activates only when an iPad window has sufficient space.
- Touch and external-controller sources now target one portable, mutex-protected normalized GameCube state. Buttons are ORed, the strongest absolute value wins per stick axis, and the maximum analog trigger wins. The game-core adapter will snapshot this state at `PADRead` boundaries rather than receiving UIKit callbacks directly.
- The touch source is cleared on resign-active. Presentation pauses while inactive and resumes on become-active. A physical controller hides touch on real devices while retaining an explicit user override; simulator virtual controllers do not hide the overlay so touch QA remains possible.
- UIKit text fields call the separated editor begin/end, UTF-8 commit, and command API; SDL desktop events delegate to the same functions.
- Rendering uses the SDL/CAMetalLayer surface supplied to Dawn.
- Wall-clock changes and timezone changes are observed explicitly.
- Backgrounding pauses presentation/audio and requests a safe save flush; foregrounding recreates transient resources.
