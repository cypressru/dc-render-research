# Shenmue II (Dreamcast, Japan, Disc 1, 2001): renderer analysis

Developer: Sega AM2. Libraries:
- AM2's own layer between the game and Kamui: `NAOMI LIBRARY Ver 0.8 AM R&D`
  and `NLOBJPUT Ver 0.99` (about `0x8C1D6000-0x8C1EA000`; its state lives in a
  fixed GBR block at `0x8C2BDB80`).
- Kamui 1.11.0.1 (Sep 2000) and Shinobi `syCache` 2.01.
- CRI ADX/AHX/ADXF for audio and streaming.

The NAOMI library is shared with Dead or Alive 2 (version 0.9 there): the model
walker, bulk kernel, clip kernel and shadow code are the same instructions.
See [`../doa2/README.md`](../doa2/README.md).

Main executable `1ST_READ.BIN` (3.1 MB, load base `0x8C010000`). All findings
are from static analysis of the disc. Nothing was measured at runtime, so cycle
counts are estimates from instruction counts. Labels in the notes: [C]
confirmed in code or data, [P] probable, [?] guess.

| File | Contents |
|---|---|
| `notes-tnl.md` | Every transform and lighting kernel: model renderer, sea, characters and joints, shadows, particles, sphere map |
| `notes-system.md` | TA path, Kamui configuration, per-area buffers, cache, textures, frame pacing, debug pages |
| `notes-world.md` | Data formats (packs, MT7, MAPINFO, AREATBL, NPC tables), district loading, culling classes, NPC crowd control |
| `listings/tnl-loops.s` | Annotated disassembly (1550 lines, sections A-F), verified line by line against the binary |
| `tools/` | Parsers: `mt7.py` (models), `ipac.py` (PKS/PKF packs), `area.py` (AREATBL), `sm2walk.py` |

## Summary

Shenmue II draws a whole town district with one tuned model renderer. Speed
comes from four things:

- **A tight kernel with the divide hidden.** About 40 instructions (30-35
  cycles) per strip vertex. It handles two vertices per loop trip, so each
  FDIV's result is used about 20 instructions later. Le Mans and Soulcalibur
  both stall on it.
- **Data drawn as stored.** MT7 meshes go from disc to the store queues with no
  load-time conversion. Mesh headers already hold native PVR words.
- **Distance classes instead of LOD meshes.** Small clutter disappears at a
  short per-district distance, most other geometry at a long one.
- **A frame-time-driven crowd.** The number of NPCs drawn is recomputed every
  frame from the measured cost of drawing them, against a 32 ms budget (30 fps).

## 1. Vertex kernels

### One renderer for map, characters, props and sky

Entries (all in the 0x8c1d4620-0x8c1dd200 renderer):
- 0x8c1d6880, the main entry (25 code references: direct calls and stored
  draw pointers);
- 0x8c1d6980, an alpha variant;
- 0x8c1d71e0 / 0x8c1d72a0, the RGB multi-light path.

Callers: the map module (0x8c11a000-0x8c11e000), the character draw (0x8c0d9fc0)
and the sky (0x8c05647c). Only the sea has its own renderer (0x8c039b40).

**Vertices (MT7, read in place).**
- An inline vertex is 32 bytes `{x, y, z, nx, ny, nz, u, v}`, with the lowest
  bit of x as a tag.
- Any other entry is an 8-byte back-reference to a vertex already emitted in
  the strip run; its "y" word is always a NaN.
- There is no shared transformed pool: strip vertices are re-transformed, as in
  Le Mans. Back-references are about 6% of entries in a typical district.

**Bulk kernel 0x8c1d79b2: intensity-lit textured strips** (TA type 7, 32 B):

```
mov.l @r4,r0 ; tst #1,r0 ; bf inline     ; tag bit: inline vertex or back-reference
mov.l @(4,r14),r14 ; add r4,r14          ; back-reference: point at the earlier copy
fmov @r14+,dr4 / dr6 / dr0               ; 64-bit pair loads (fschg mode)
ftrv xmtrx,fv4                           ; vertex A; matrix rows permuted -> (w, X, Y)
fdiv fr4,fr7                             ; 1/w for A ...
fipr fv12,fv0                            ; N.L, light already in model space
...                                      ; vertex B is loaded and transformed (fv8)
fmul fr7,fr6 ; fmul fr7,fr5              ; ... A's 1/w is used ~20 instructions later
fmov fr2,@-r6 ; fmov fr0,@-r6 ; ...      ; written backwards
mov.l r2,@r6 ; mov r6,r2                 ; PCW = an SQ address (0xE0xxxxxx), the previous vertex's
pref @r6 ; add #64,r6
```

Tricks:
- **Free command words.** Each vertex's PCW is a store-queue address (the
  previous vertex's, kept in r2): `0xE0xxxxxx` is a valid vertex command, and
  end of strip is that address shifted right by one (`0xF0xxxxxx`). The sea,
  particle-quad and shadow code use the same trick.
- **Two vertices per trip.** fv4 and fv8 alternate, so the FDIV of one overlaps
  the transform of the next.
- **Lighting in model space.** One directional light plus ambient, rotated into
  model space once per mesh, so normals are never transformed. The map is lit
  at run time, not prelit (55,405 of the 60,613 meshes in the map entries of
  all district and interior packs are type 0 with unit normals). The result
  goes out as intensity, with no ARGB packing.
- **The PCW overwrites w.** The matrix rows are permuted so the transform yields
  (w, X, Y), and the PCW store then overwrites the w slot.
- **Near test on the integer pipe** (in the near-clip twins, not this kernel):
  one unsigned compare on w's raw bits.
- **No constant words are left in the store queues** by this kernel: all eight
  words, including the zero offset intensity, are written for every vertex by
  four pair stores. (The shadow kernel does leave its PCW in the queue.)

### Other kernels

| Kernel | Use | Cost |
|---|---|---|
| 0x8c1d7890 | unlit meshes | about 25-30 cycles |
| 0x8c1d7b06 | specular via a lookup table | 48-52 instructions |
| 0x8c1d9760 | mesh type -2, probably bump mapping (3 meshes on disc) | about 113 instructions |
| 0x8c1da1e0 | type -3, vertex colour | 66-104 instructions |
| 0x8c1d4620 | type -3 fast path (hook modes 1/2; type -3 is 184 meshes on disc) | about 30 instructions, 20-24 cycles |
| 0x8c1dad40 walker | RGB path with point and spot lights, 64 B vertices | about 70-80+ cycles |
| 0x8c039b40 | sea (`MISC/TRSEA4.MT6` as repeated tiles), colours baked | 30-35 cycles; 60-70 clipped |
| 0x8c03bf40 | sphere-map pass: rewrites u, v in the model before the normal draw | 31 instructions |

### Why 685 `fschg`

Most vertex loops have none; 64-bit mode stays on for the whole kernel. A few
loops do toggle per vertex: the specular kernel 0x8c1d7b06 (around its 32-bit
table load), the shadow kernel 0x8c1dd420 (two per strip vertex) and the sea
clip loop. The bulk of the count comes from three places:
- every kernel and clip helper toggles the mode twice, and kernel families
  exist in many copies;
- particle kernels save and restore the matrix around each particle's C
  callback (a 10-instruction idiom);
- the matrix library loads matrices straight into the back bank.

### Clipping and culling

- **Per mesh:** a bounding-sphere test (one FTRV, near and far, four side
  planes).
- **Back faces:** culled by the PVR, with the cull mode flipped for mirrored
  matrices.
- **Near plane:** meshes crossing it go to clip twins that clip inside the
  strip, as in Le Mans. That costs one FDIV per new vertex, about 50-60
  instructions per vertex.
- FDIV is always used for 1/w; FSRRA is used only for normalising and light
  falloff.

### Characters

- **Rigid meshes per bone.** Each bone has its own mesh, drawn with that bone's
  matrix by the ordinary kernels. There is no per-vertex matrix palette.
- **Joints are patched on the CPU before drawing**, by rewriting the child
  mesh's vertex records in place:

  | Routine | What it does | Cost |
  |---|---|---|
  | 0x8c0502fa | seam copy | about 17-20 cycles per joint vertex |
  | 0x8c0503dc | two-bone weighted seam (near characters only) | about 35-40 cycles |
  | 0x8c0504fc | multi-bone envelopes | about 35-40 cycles per influence |
  | 0x8c052860 (`HMT_HandCalcSkin`) | hands | about 26-30 cycles per influence |

- **Crowd LOD (0x8c0f6dd4).** Characters past a distance threshold skip the
  weighted passes and keep only the seam copy. There is no separate cheaper NPC
  kernel.

### Shadows and particles

- **Shadows** are modifier volumes built from the model's own strips
  (0x8c1dd298, kernel 0x8c1dd420). Each strip vertex becomes one 64 B volume
  triangle (about 43-46 instructions, 35-45 cycles), with no CPU back-face
  cull. Separate C box volumes live at 0x8c0ff0a4.
- **Particles** (driver 0x8c03a260):
  - Screen sprites cost about 45-50 cycles each. Rotated quads (0x8c03aa30)
    cost about 250-300, because the matrix is rebuilt per particle.
  - Update and draw are one pass: each particle's callback runs inside the draw
    loop.

## 2. Getting vertices to the PowerVR

- **Kamui configuration.** NL fills the struct at `0x8C30866C` (0x8C1E1F60) and
  calls `kmSetSystemConfiguration` (0x8C20C5A0): two framebuffers, default list
  shares 70/5/25/0/0% (opaque, opaque modifier, translucent, translucent
  modifier, punch-through).
- **Opaque streams direct.** Boot then makes opaque the direct list, streamed
  into the TA FIFO (0x8C1E2020). The other lists go by store queue into a RAM
  vertex buffer and then by DMA.
- **Same store-queue idiom as Soulcalibur.** Per-list pointer table
  `*0x8C317E44`, QACR0/1 = ptr >> 24, 32 B `pref` bursts. No `kmSetVertex`.
- **Per-area vertex buffers.** `MISC/AREATBL.BIN` is a small SH4 stub that
  returns 132 records of 32 bytes, keyed by 4-character area ID with `*`
  wildcards (lookup 0x8C057640, applied at 0x8C0C9640). Each record sizes the
  vertex buffer per list (size = sum of the buffered lists, doubled only when
  no list is direct; typically 320 KB at P2 `0xACEC0000`) and carries the
  district distances below.
- **Polygon headers** are pre-built in the model data and copied per mesh. The
  colour type is patched to packed when needed, and a forced alpha-blend TSP
  (`0x941000C0`) acts as the per-object fade.
- **Shadows** go to the opaque-modifier list. The C-built volumes use header
  `0x81000000`, triangles, then `0x81000040` + ISP `0x20000000` to close; model
  volumes use PCW `0x818c0000`.
- **Effects.** Cutscene data has chunk tags `BLUR WAVE FADE AFOG SHDW FILT
  LENS`. The framebuffer is read back through `0xA5000000` (probably for
  transitions or thumbnails). No render-to-texture was found.

## 3. Frame pacing and budgets

- **30 fps target.** Boot sets a 2-vblank interval (0x8C0C9DE0(30)). The
  frame-end task (0x8C0C9EA0) busy-waits on the vblank counter. A slow frame
  simply takes more vblanks; there is no frame skip. One mode switches to 60 Hz
  (0x8C07FC0A).
- **Live measurements.** Frame time is read from TMU0 every frame (32-entry
  history at 0x8C2E4710), and PVR render time comes from the render-end
  callback. TA list registers (`A05F8124-38`) are sampled every other frame
  (no peak); peaks are kept for the per-list byte counts.
- **Time-slicing.** Long NPC loops check the timer every 300 iterations and,
  past 15 ms, run the per-frame services before continuing (0x8C1056A0 and four
  similar loops).
- **Debug pages (0x8C0ADB80)** stay live in the shipping build:
  - `IVBS Opaque/OpaqueM/Trans/TransM/Punch`: bytes per list this frame.
  - `MVBS`: per-area high-water marks.
  - `FreeTexture`, `MaxBlockSize`, `Heap Rest/Max/Waste`.

## 4. Cache

- **CCR values.** `0x808` at startup, then `0x105` (ICE|CB|OCE). OCRAM and
  index mode are never enabled.
- **Cache off/on around overlays.** `0x8C04FC00` writes back every valid
  operand-cache line and sets CCR = 0; `0x8C04FC68` restores `0x105` from P2.
  They wrap overlay code loads (`AREATBL.BIN`, `SYSP` packs), the sub-game
  dispatch (0x8C122CA0: Hang-On, Out Run, After Burner, Space Harrier) and
  display-mode changes. The restore never sets ICI, so instruction-cache
  coherency rests on the off/on cycle.
- **`ocbi` / `ocbp` / `ocbwb`** are used only for DMA coherency, for example
  purging a texture before its upload (0x8C177820). There is no `movca.l` in
  game code.

## 5. Data formats

- **Packs.**
  - PKF (textures): `PAKF`, then `TEXN` entries (GBIX+PVRT), then an `IPAC`
    directory.
  - PKS (models): `PAKS` + `IPAC`, with 20-byte entries
    (`name[8] ext[4] ofs size`) of kinds `MAPM`/`CHRM`/`PROP`/`FLDD`/`LGHT`/
    `SNDP`/`SRCH`.
  - The district pack `MPK00.*` is gzip-wrapped (geometry about 4:1, textures
    1.2:1); other packs are mixed (in WT00, `WTP*`/`WTR0` raw, `WTK*`/`WTX*`
    gzip).
- **AFS:** `"AFS\0", n, (ofs,size) x n`, 2 KB aligned.
- **`STREAM/*.AFS` files are ADX voice audio, not geometry** (32,245 of 32,769
  entries are mono ADX; the rest are small `CHID`/`SPSD` records). `FREE01.AFS`
  (251 MB) has 25,039 entries, 24,803 of them "free talk" ADX clips, and the
  `.IDX` files map cue names to entries.
- **MT7 models** (`MDO7` map; `MDC7`/`MDL7`/`MDP7` characters and props).
  Parser: `tools/mt7.py`.
  - Node (0x40 B): flags (low nibble = cull class), float position, int32
    rotation (0x10000 = 360 degrees), scale, and model/child/sibling/parent
    offsets.
  - Model: a bounding sphere, then its meshes.
  - Mesh: real PVR PCW/ISP/TSP/TEX words, a bounding sphere, a texture index
    and 9 colour floats.
  - Strip: `u32 flags, u32 n`, where flag 0x10 is a strip and 0x08 a triangle
    list.
  - Shape: 79% of strips are 4-vertex quads; mean length about 4.7; 61-72 bytes
    per triangle stored (WT00 blocks).
  - Heavy instancing through the node tree: WT00 MAP01 has 336 nodes and 179
    models, 10.8k unique triangles drawn as 35.1k.
- **Textures.** 23,745 PVRT headers on the disc (9,860 distinct): RGB565
  18,388, ARGB4444 4,155, ARGB1555 1,195. VQ 73%; mostly 128x128 and 64x64.
  Only 17 have mipmaps. Uploads go by DMA ch2 to `0x11000000`, or a 64-bit
  CPU copy when unaligned (Kamui 0x8C2179A0).
- **Sizes.**

  | Item | Triangles | Geometry | Notes |
  |---|---|---|---|
  | WT00 district (MAP..MAP05) | about 83k instanced | 2.5 MB | + 1.32 MB textures (198) |
  | Interiors (WTP0, WTK0, WTX2) | 5.7k-10.5k | 0.3-0.55 MB | separate packs |
  | NPC types (776) | median 863 (130-2,798) | about 50 KB | median 33 nodes, 6 textures (about 107 KB) |

- **`MAPINFO.BIN`** is a chunk list: `FLDD` collision, `LGHT`, `ECAM`, `DOOR`
  room pairs, `WTHR` region polygons, `SCEX`, `CHRD`. There are no PVS,
  occlusion or LOD tables.

## 6. World and visibility

- **A district is one resident pack.** The loader builds `scene/%02d/%c%c%c%c`
  (0x8C11C76E) and loads all `MAP`/`MAP%02d` blocks into 32 slots of 108 B
  (0x8C2ACFDC). Blocks are 60-220 m spatial chunks, switched on and off as
  whole units through bitmasks (0x8C2AE15C), apparently from event code rather
  than by distance.
- **Interiors** have their own collision, lights and geometry and are tied to
  the `DOOR` table, so they likely load on door transitions.
- **No predictive geometry streaming.** Only voice audio and NPC models stream
  continuously.
- **Map draw** (0x8C11B000 -> 0x8C119B80 -> node walker 0x8C1199E0) runs a
  hand-assembly sphere/frustum test per node (0x8C04E0D8 / 0x8C04E124 /
  0x8C04E1B4). It transforms the centre with FTRV, then tests near, far and
  |x|, |y| against a slope. The constants are set each frame from the camera
  and the district distances (0x8C04DF60).
- **Cull-distance classes instead of mesh LODs.** The node flag nibble indexes
  a table at 0x8C254ED8:
  - Class 6 (small clutter, about 1.1 m radius) is culled at farB.
  - Flag 9 (large objects; 1,770 nodes in the district packs) gets no far
    test (0x8C04E170).
  - Everything else is culled at farA.
  - Classes 2/3/8 are hidden or special.
  - A "visible only beyond farB" test exists but no flag value selects it.
- **farC** starts the fade of fading objects, with +-0.5 m hysteresis
  (0x8C0D74F8).
- **District distances (AREATBL):**

  | District | farA | farB | farC |
  |---|---|---|---|
  | WT00 | 80 | 35 | 30 |
  | WK00 | 115 | 25 | 30 |
  | AR02 | 155 | 30 | 30 |
  | WE00 | 280 | 40 | 30 |

## 7. NPC crowds

- **Types and loading.** `HUMANS.IDX/AFS` holds 776 NPC types: AFS entry 2i is
  the texture pack, 2i+1 the model pack. There is one model per type (two
  types carry a second `CHRM`), with no LOD versions. The IDX stores each
  type's texture size, so memory checks need no reads.
- **Model cache** (0x8C102C40), with per-type states idle / requested /
  reading / resident:
  1. Refuse (-4) if the texture pack + 0xC18 exceeds the largest free texture
     block.
  2. Refuse (-3) if it doesn't fit the largest free heap block minus a 14 KB
     reserve.
  3. Otherwise queue an async read of both entries (52-slot queue,
     0x8C126580), poll it, and bind.

  If memory is short, the NPC simply doesn't spawn.
- **Spawn rules** (0x8C10DCA0 / 0x8C10E2C0):
  - Spawn within 25 m and on screen; some points also need more than 6.5 m.
  - Keep within 30 m always, or within 75 m while on screen.
  - Fade in and out at +-0.05 alpha per frame.
- **Population cap** (0x8C1066C0): `max(min, max - int(max*f*0.5))`. Per-area
  max/min come from `NPCAREA.BIN` (WT00 32/26, ARSF 46, one scene 50); f is a
  global scalar, possibly weather. Each type has a weight byte that counts
  against the cap.
- **Adaptive draw count** (task `DRWH`, 0x8C06FF20):
  1. Humans are insertion-sorted by view depth into a 50-entry list.
  2. `N = (32000 us - (frame - humanCost)) * drawnLast / humanCost - 1`, at
     least 6, using frame time from TMU0.
  3. The nearest N fade in and the rest fade out. Anything with alpha above
     0.001 is still drawn.
  4. The population cap is reset to (N+1)*2 each frame.

## 8. Comparison with the other games here

| | Shenmue II | Soulcalibur | Test Drive Le Mans | WSB 2K2 |
|---|---|---|---|---|
| Vertex sharing | none (back-references within a strip run) | pools + indexed strips | none | pool of at most 256, OCRAM |
| Bulk kernel | about 40 instructions, 2 vertices per trip, FDIV hidden | about 88 per unique vertex + 30 per strip vertex (stage) | 30-44, FDIV stalls | 4-deep pipeline |
| Source vertices | 32 B floats as stored on disc | 16 B floats | 24-32 B floats (strips de-indexed at load) | 3 B palette indices (models), floats (playfield) |
| Lighting | 1 directional + ambient in model space, intensity | 4 coloured lights in 2 FTRV | baked intensity / 1 FIPR | 3 diffuse + specular per FTRV, intensity |
| PCW | the previous vertex's SQ address | kept in the store queues by most emitters | register constant | header PCW from the material cache (`_iMatPCW`) |
| Characters | rigid per-bone meshes + CPU seam patching | per-bone weighted lists | (cars) | quantized blended matrices |
| Culling | sphere per node and mesh | sphere per chunk | sphere tree | 8 corners per area (`Ren_CheckVisible`) + FIPR test on each strip's leading triangles |
| LOD | cull-distance classes per district | none found | distance layers + car LOD budget | |
| Budget | crowd size from measured frame time (32 ms) | | 37k strip vertices | |
| Shadows | modifier volumes from the model strips | modifier volumes | | modifier volumes |
| Cache | default (off/on around overlays) | `movca.l` pool writes | default | OCRAM + OIX |

## Uncertainties

- The rule choosing the intensity or the RGB lighting path.
- Header intensity modes, specular table indexing, the point-light falloff
  constant.
- The bump-map reading of mesh type -2.
- The shadow volume's source mesh.
- The exact crowd-LOD distance test.
- What toggles the map-block masks.
- The interior load trigger (inferred from the file layout).
- The NPC cap scalar f.
- Animation-rate LOD for NPCs (not examined).
- The meaning of some MT7 model fields and strip flag bits.
- The two Kamui setup paths keyed on `*0xA05F689C`.

How strip vertices share positions was not measured, so totals per triangle
are not estimated.
