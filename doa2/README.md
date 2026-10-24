# Dead or Alive 2 (Dreamcast, USA, 2000): renderer analysis

Developer: Team Ninja / Tecmo. Main executable `1ST_READ.BIN` (1.8 MB, load
base `0x8C010000`). All findings are from static analysis of the disc. Nothing
was measured at runtime, so cycle counts are estimates. Labels in the notes:
[C] confirmed in code or data, [L] likely, [?] guess.

| File | Contents |
|---|---|
| `notes-tnl.md` | Kernels, the draw API, soft accessories, morphs, stage light baking, shadows |
| `notes-system.md` | Kamui configuration, TA path, frame pacing and frame skip, cache, data formats, frame level |
| `listings/tnl-loops.s` | Annotated disassembly (1545 lines, sections A-I), verified line by line against the binary |
| `tools/chr.py` | `.CHR` model parser (all 86 files parse) |
| `tools/aux_formats.py` | `.APV` (morph), `.SUP` (joint welds), `.ACS` parsers |

## Summary: it uses Sega AM2's NAOMI library

DOA2's 3D renderer is not Tecmo code. It is Sega AM2's "NAOMI library":
- strings `NAOMI LIBRARY Ver 0.9 AM R&D`, `NLSPRITE Ver 0.2`,
  `NLOBJPUT Ver 0.99`;
- code at `0x8C0F8000-0x8C10E5C0` (matrix library, sprites, walkers and
  kernels, with some SHC runtime and sound glue mixed in), plus a second
  math/draw layer at `0x8C110EA0-0x8C1132C0`;
- Kamui2 16,3,2,0, mainly at `0x8C11A000-0x8C11E000` and
  `0x8C12A000-0x8C133000` (CRI ADX and Shinobi code sit in between).

It is the same library that Shenmue II (version 0.8) uses. The kernels match
nearly instruction for instruction once branch targets and literal addresses
are normalised:

| Routine | DOA2 | Shenmue II | Identical instructions |
|---|---|---|---|
| Model walker | 0x8c101540 | 0x8c1d7480 | 1081 / 1120 (the rest: literal pools, a Shenmue-only hook) |
| Bulk diffuse kernel | 0x8c101a52 | 0x8c1d79b2 | 151 / 151 |
| Near-clip kernel | 0x8c101ca2 | 0x8c1d7c02 | 431 / 431 |
| Fast packed-colour path | 0x8c10a5ea... | 0x8c1d442a... | 1364 / 1376 |
| Shadow volumes | 0x8c10d980 | 0x8c1dd220 | 1559 / 1568 |
| Batch projector | 0x8c107d10 | 0x8c1de5d0 | 152 / 152 |
| RGB multi-light walker | 0x8c102660 | 0x8c1dad40 | 398 / 400 (unreachable from DOA2's game code) |

The game code itself (`0x8C010000-0x8C0F8000`) contains no FTRV, FSRRA or
FSCA, and writes neither the store queues nor the TA. All 242 FTRV are in the
library.

So the kernel-level findings in [`../shenmue2/README.md`](../shenmue2/README.md)
apply here. In particular:
- the two-vertex software-pipelined kernel that hides FDIV;
- each vertex's command word being its own store-queue address, with
  end of strip as `shar` of it (`0xF0xxxxxx`);
- 64-bit pair stores;
- light rotated into model space once per mesh;
- intensity-mode output;
- MT7-style 32-byte vertices with 8-byte back-references.

This README covers what DOA2 adds.

## 1. Kernels and the draw API

| Kernel | Use | Cost |
|---|---|---|
| 0x8c101a52 | diffuse (bulk) | 79 instructions per 2 vertices on back-references (85 on inline vertices); about 30-35 cycles per strip vertex |
| 0x8c101ba6 | specular: most character meshes | about 40-45 cycles |
| 0x8c101930 | unlit | about 25-30 cycles |
| 0x8c10a7e0 | packed vertex colour | about 20-24 cycles |
| 0x8c108372 | diffuse + an offset brightness term (enabled by 0x8c103b60), possibly a hit flash | about 6 instructions more; the draw API bypasses it |

- **Draw API.** The game draws its models almost entirely through four entry
  points: 0x8c111680, 0x8c1116a0, 0x8c111580 and 0x8c111560 (about 710 call
  sites; the NL slot entries 0x8c103920/80 have 6 more).
  - The 0x8c111580/60 variants first move the eye vector into model space,
    for specular.
  - The shared tail (0x8c1116c0) rearranges the projection so FTRV returns
    (w, X, Y, -w), then calls the walker (0x8c101542).
- **Culling.** One sphere test per mesh against the near plane and four side
  planes (0x8c101708-0x8c10174e). Only meshes that cross the near plane use
  the clipping kernels.
- **Per-frame estimate.** Two characters (about 20-22k strip vertices) are
  about 0.8M cycles, and a large stage 0.6-1.0M before culling. That is
  roughly 40-60% of a 60 fps frame with cache hits.

## 2. Characters

- **Rigid limbs, no skinning.** Most costumes (40 of 42) are 42-59 limb
  models, about 8.9k triangles, with an average strip length of 9.5. There
  are no weights, no matrix palette and no skinning loop anywhere.
- **Joint welds (`.SUP`).** 7-14 node pairs per costume (10 in KAS00, for
  example 1-0, 0-2, 3-7), each with 3-44 seam vertices stored as
  `{CHR offset, position, normal}`. They are probably written into the meshes
  so the limbs join, but the code that applies them was not found.
- **Morph targets (`.APV`).** Vertex offsets land on CHR object vertices. In
  KAS00 the sets are face (303 vertices x 4 position blocks, 345 x 18, base
  included), torso (256, base only) and four sets of about 520 vertices that
  probably match the hands; most files are 285-500 KB (three costumes have
  empty APVs). Blend helpers at 0x8c0cf8fa-0x8c0cfa16 (18-37 instructions per
  vertex) match the layout. Facial animation is the likely use; no caller was found.
- **Soft accessories (probably set up by `.ACS`: hair, ribbons, cloth).**
  - The accessory module (0x8c0c4000-0x8c0c7c00) runs particle chains with a
    constraint solver (0x8c0c6278, six copies) of 81 scalar instructions per
    link.
  - 0x8c0c5996 then transforms each particle into its bone's space (one FTRV,
    about a 4-cycle stall) and writes it straight into the vertex records,
    about 45 instructions per particle.
  - So the physics deforms the mesh data in place and the ordinary rigid
    kernels draw it.
- **Shadows per limb.**
  - Driver 0x8c0d3df0 calls 0x8c0d43e8 / 0x8c0d4462 15 times per character
    (straight-line code). Each call shears a volume model between two joints
    along the light and draws it as a modifier volume, about 35-45 cycles per
    triangle.
  - The run of 15 untextured hulls in most costumes (models 33-47 in AYA00;
    the index varies, and WBA00/YTI00 have none) are probably these volumes.
  - Stage floor meshes carry the shadow bit in their command word; characters
    don't.

## 3. Stages

- **One file holds every tier** (3k-24k triangles in most stages, 27.5k in
  STAGE23; STAGE26 and STAGE30-40 are identical 200-triangle placeholders).
  Name-to-object tables (for example at 0x8c19dc40: `ag_buila*_top/_mid/_und`,
  `ag2_2f..6f`) drive the stage modules.
- **Lights baked into the vertices every frame.**
  - The pass at 0x8c10d360 (walker 0x8c10d120, entry 0x8c104240, called from
    six stage draw functions) lights each unique vertex with directional,
    point and spot lights.
  - It writes packed base and offset colour into the vertex itself (light
    above 1.0 spills into the offset colour) and retypes the mesh, so the
    transform then uses the cheapest kernel (packed colour).
  - Cost: about 135 instructions (110-130 cycles) per unique vertex, plus about
    50 per point light. 0x8c104290 undoes it.
  - Lighting cost is paid once per unique vertex, not per strip vertex, and
    the draw itself runs the cheapest kernel.
- **Reflections.** A sphere-map UV pre-pass only (0x8c112560, 31 instructions
  per vertex). No mirrors, no particle kernel (effects are ordinary models from
  `EFC0.CHR` / `FIX.CHR`), no dedicated water or snow loop.

## 4. Getting vertices to the PowerVR

- **Kamui configuration** (struct at 0x8C2B6CE8, filled by 0x8C0F92F0 and
  edited at boot 0x8C012474-0x8C0124A0; `kmSetSystemConfiguration` at
  0x8C11B7A0):
  - two framebuffers and two vertex banks;
  - vertex buffer at `0xACE80000`, size 0x180000, ending exactly at
    `0x8D000000`;
  - opaque is the direct list; the other shares are opaque modifier 16.7%,
    translucent 66.7%, translucent modifier 16.7%, punch-through 0%, giving
    128 / 512 / 128 KB per bank.
- **Store-queue path.**
  - Opaque is configured as Kamui's direct-transfer list, so it probably
    streams to the TA FIFO. The other lists go by store queue to RAM and are
    sent by DMA ch2 at end of pass.
  - The walker (0x8C101542) takes the list from bits 24-26 of each pre-built
    mesh header and reloads QACR only when the list changes.
- **Lists used.** Across all 86 CHR files meshes use only opaque and
  translucent; there is no punch-through. Objects with alpha below 1 are moved
  to the translucent list with SRC_ALPHA / INV_SRC_ALPHA.
- **Render to texture.** The library can create a surface (Kamui 0x8C11C440,
  type 0x901; begin 0x8C0FC4F0, end 0x8C0FC600, which also sets FB_X/Y_CLIP).
  One game module uses it (0x8C0C28C4, 0x8C0C2E80, 0x8C0C3352); what it
  renders is unknown (two of the four shadow-driver calls sit inside its
  passes).
- **Overlap.** The library's frame end (0x8C0F8A60) runs EndPass, Render and
  EndScene, then immediately BeginScene and BeginPass. The game builds frame
  N+1 while the PVR renders frame N.
- **Display.** Mode 9 (NTSC) / 19 (PAL): 640x480 non-interlaced with flicker
  filter. No field rendering.

## 5. Holding 60 fps: frame skip by patching code

Main loop 0x8C0125EC-0x8C01279C, vsync count 1:
1. Kamui's metrics give the last PVR render time in microseconds (8-entry
   TCNT0 ring at state+0x914).
2. If `(vsync + late) x 16000 us` is less than that render time, 0x8C012A74
   overwrites the first word of 11 draw entry points with `rts; nop`, writes
   each cache line back with `ocbwb`, then invalidates the I-cache
   (0x8C1177EE).
3. One logic tick then runs with no drawing.
4. The next iteration restores the code, skips the render and waits for
   vblank.

Logic stays at 60 Hz and only the display drops a frame. Logic also loops
vsync-count times per frame (0x8C08E866).

## 6. Cache

- **CCR** is `0x105` (OCE | CB | ICE), set via P2 (0x8C11868C -> 0x8C117798).
  ICI at startup; a full off and address-array clear at 0x8C1186FA.
- **No OCRAM, no index mode.** The only `0x7C000000` user is syCache's
  8 x 1 KB OCRAM allocator (0x8C117FF8), which nothing calls. Most raw counts
  of these constants in the file are data, not code.
- **`movca.l`** has one real use, in Shinobi. `ocbi` / `ocbp` / `ocbwb` serve
  DMA coherency and the code patching:
  - `ocbi` before loads (0x8C08E068);
  - an in-place 565 -> 4444 repack of 256 KB (0x8C0D869C), then `ocbp`
    before DMA;
  - Kamui `ocbwb` before texture DMA (0x8C129ED8).
- None of these sit inside a vertex loop.

## 7. Data formats

- **`.CHR`** (parser `tools/chr.py`):
  - Header `{0x18, objtab, textab, n_obj, n_tex}`. Object pointers are
    pre-linked to `0x0C300000` (characters) or `0x0C400000` (stages,
    effects) and relocated at load.
  - Texture entries are 12 B `{w, h, PVRT format, offset into .BIN}`; each
    `.BIN` is exactly the sum of its textures, as raw pre-twiddled VRAM images.
  - Mesh: PCW, ISP, TSP, TEX, a bounding sphere, an 11-word material (`mat[0]`
    texture index, a signed light-type byte) and a size.
  - Strip flags: bit 4 = strip (otherwise a triangle list), bit 7 = chained.
  - Vertices: 32 B floats `{x,y,z,n,u,v}` tagged by bit 0 of x, or 8 B
    back-references (the same scheme as Shenmue II's MT7, which the parser also
    reads).
- **Counts.**
  - 42 costumes have 6,011-10,739 triangles each (average 8,357, shadow hulls
    excluded).
  - Kasumi KAS00: 56 objects, 145 meshes, 1,405 strips, 7,241 inline vertices +
    4,603 back-references, 8,184 triangles.
- **Textures.** 3,836 entries, 65% VQ (1,009 of those mipmapped, mostly stage
  textures). No palettised or small-VQ textures.
- **No compression.** Models, morphs and VRAM blobs are stored raw; the only
  load-time conversion found is the 565 -> 4444 pass.
- **Other files.**
  - `.MOT`: 44 packed variable-length channel tracks per motion (keys not
    decoded).
  - `.ACS`: a (type, offset) list plus float limits.
  - `Snn_DAT`: u16 grids, probably stage floor or wall maps.
  - `*_C?.BIN`: DTPK sound banks.
- **No LOD.** No lower-resolution copies exist, and nothing selects by distance.
- **Debug menu.** The pause/debug menu code is compiled in (0x8C0193DA-
  0x8C01B47C: "Camera Move", "Fog Chng", "Stg Undulate", "MorfStop",
  "Stg Bank Chng", light editors); whether it is reachable was not checked.

## 8. Comparison with the other games here

| | DOA2 | Shenmue II | Soulcalibur | Test Drive Le Mans | WSB 2K2 |
|---|---|---|---|---|---|
| Renderer | AM2 NAOMI library 0.9 | AM2 NAOMI library 0.8 (same kernels) | Namco, in-game | Melbourne House, in-game | Blue Shift, in-game |
| Bulk kernel | about 40 instructions per strip vertex, 2-wide, FDIV hidden | same code | about 88 instructions per unique vertex + 30 per strip vertex (stage) | 30-44 instructions, FDIV stalls | 4-deep pipeline |
| Vertex sharing | none (back-references within a strip run) | same | pools + indexed strips | none | pool of at most 256 |
| Characters | rigid limbs + seam welds + morphs + soft accessory chains | rigid per-bone meshes + CPU seam patching | per-bone weighted lists | (cars) | quantized blended matrices |
| Lighting | per mesh; stage lights baked per unique vertex each frame | 1 directional + ambient | 4 coloured lights in 2 FTRV | baked intensity / 1 FIPR | 3 diffuse + specular per FTRV |
| 60 fps handling | measured PVR time -> patch draws to `rts` for one frame | 30 fps target, no skip | no vsync wait or frame skip in game code | fixed 30 Hz sim step, render skipped while catching up | |
| LOD | none | cull-distance classes | none found | distance layers + car budget | |
| Shadows | per-limb sheared modifier volumes | modifier volumes from strips | modifier volumes (one winding) | | modifier volumes |
| Cache | default | default | `movca.l` pool writes | default | OCRAM + OIX |

## Uncertainties

- The per-frame call site that draws the character models is unconfirmed (all
  draw-API calls sit in 0x8c08c000-0x8c0e1000).
- The 15 hulls being the shadow volumes is inferred.
- `.APV` as facial animation is a guess; the blend helpers have no confirmed
  caller.
- The meaning of the offset-brightness twin.
- The condition that turns stage light baking on.
- Whether the opaque list really goes straight to the TA (the configuration
  says so; the runtime list pointer was not traced).
- Which stages edit water or snow in place.
- What the render-to-texture module draws.
- The ACS and MOT encodings.
- Real per-frame triangle counts need runtime state.
