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

The app executes compiled C/C++ game code directly on Apple ARM64. Aurora is a source-level SDK compatibility layer, not a CPU/GPU emulator. The existing WebAssembly port is research material only and will not be embedded.

## Address and data model

Host pointers are native-width. Game addresses, segmented N64 display-list addresses, file offsets, save fields, and on-disc structures remain explicitly fixed-width. Conversion crosses named, bounds-checked APIs; integer-to-pointer casts are not used as a generic address model.

The first Apple Clang portability pass makes DVD/audio callbacks, task payload copies, heap headers, memory archives, ARAM, retrace messages, allocation APIs, and Famicom buffers native-width where they carry host state. It deliberately does not widen serialized or guest-visible fields. Both Apple Clang and GCC builds pass, but sanitizers and the complete boundary inventory remain required evidence.

Static display lists must be registered with the resolver at startup rather than detected by assuming a low/fixed executable address. ARAM becomes an allocated host buffer whose guest addresses are offsets, not truncated host pointers.

## Graphics

Animal Crossing retains an N64 display-list layer (`emu64`) that emits GameCube GX operations. The intended production path is:

```text
N64 GBI display list → emu64 → GX → Aurora → Dawn/WebGPU → Metal
```

The OpenGL 3.3 renderer remains a temporary reference for Milestone 1. It is unsuitable as the final iOS path because iOS exposes OpenGL ES rather than desktop OpenGL 3.3 and OpenGL ES is deprecated on Apple platforms.

## Disc and assets

The app bundle contains no retail data. The user selects a supported image through Files. A validator reads only the header and required metadata before a nod-backed disc reader indexes the filesystem. The initial preference is direct reading from a private Application Support copy or a durable security-scoped bookmark. Any derived cache is local, versioned by image hash, removable, and excluded from source and release packages.

## Saves

GCI-folder mode is the initial canonical store because it gives one file per save and aligns with Dolphin import/export. Writes go to a temporary sibling, are flushed, validated, and atomically replaced; previous valid generations are retained. Save operations are serialized with lifecycle transitions.

## Platform integration

- The game loop owns game state on a dedicated thread or SDL main callback compatible with iOS.
- UIKit owns import/settings/touch overlays and forwards normalized events.
- Rendering uses the SDL/CAMetalLayer surface supplied to Dawn.
- Wall-clock changes and timezone changes are observed explicitly.
- Backgrounding pauses presentation/audio and requests a safe save flush; foregrounding recreates transient resources.
