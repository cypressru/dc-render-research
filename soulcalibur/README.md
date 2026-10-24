# Soulcalibur (Dreamcast, 1999): renderer analysis

Developer: Namco. SDK: Kamui 1.06 (Feb 1999), Shinobi 1.43, syCache 1.52,
Ninja. Main executable `1ST_READ.BIN` (3.6 MB, load base `0x8C010000`). Game
code is `0x8C010000-0x8C103000`, Kamui/Shinobi about `0x8C21A000-0x8C246000`.
All findings are from static analysis of the USA disc. Nothing was measured at
runtime, so cycle counts are estimates.

| File | Contents |
|---|---|
| `notes-tnl.md` | Detailed notes on every transform and lighting loop (stage, characters, shadows, effects, skeleton) |
| `notes-system.md` | TA path, Kamui configuration, cache, disc formats, frame level |
| `listings/tnl-loops.s` | Annotated disassembly of 24 routines (about 1800 lines) |
| `tools/lz.py` | Port of the game's LZ decoder (0x8C0EE76C) plus olnk / inner-pack listing |

## Summary

Soulcalibur's design is close to the opposite of Test Drive Le Mans, and close
to WSB 2K2: it **shares vertices**. Le Mans re-transforms every strip
vertex from float source data in one pass. Soulcalibur instead uses three passes:

1. Each unique vertex is transformed once into a 16-byte pool entry.
2. A lighting pass writes a second pool of colours.
3. A strip emitter copies pool entries into 32-byte TA vertices by index, with
   no FPU work at all.

Its speed comes from cheap lighting and skinning:
- **Four coloured lights for 2 FTRV per vertex.** XMTRX holds 4 light
  directions, so one FTRV gives all four N.L. A second FTRV, with XMTRX holding
  the 4 light colours, sums them to RGB.
- **Skinning with one FTRV per bone influence and no matrix blending.** Each
  bone owns a list of vertices stored pre-multiplied by their weight.
- **Normals are never rotated.** Per bone, XMTRX = light directions x bone
  rotation gives N.L directly from the model-space normal.
- **Constants stay in the store queues.** Most emitters write the PCW and
  constant colour words once into both 32-byte store-queue halves and leave
  them there across bursts (the rain streak writes a PCW per vertex instead).

Like Le Mans, nothing is software-pipelined and 1/z always uses FDIV (never
FSRRA), so every projection stalls about 9 cycles. No OCRAM or cache tricks
are used.

## 1. Vertex pipeline

### Stage and rigid meshes

| Pass | Address | Instructions / vertex | What it does |
|---|---|---|---|
| Position | 0x8c03a9cc | 30 | 16 B `{x,y,z,attr}` floats -> `{x/z+320, y/z+240, k/z, attr}`; one FTRV, FDIV for 1/z |
| Lights | 0x8c03aa3c | 29 | XMTRX = 4 light directions: one FTRV gives 4 N.L, clamped at 0 (4 branches) |
| Colour | 0x8c03aa84 | 29 | XMTRX = 4 light colours: one FTRV sums RGB; integer ambient; saturate to packed `0x00RRGGBB` (alpha is added by the emitter) |
| Strip emit | 0x8c03ab1c | 30 per strip vertex | 8 B per strip vertex `{u16 pos index, u16 colour index (bit 15 = end), u32 packed 16-bit UV}` -> packed-colour 16-bit-UV TA vertex |

- Total cost is about 88 instructions per unique vertex (about 70 cycles) plus
  30 per strip vertex (about 20 cycles).
- `attr` bytes 2 and 3 become the base and offset alpha (byte 3 is possibly fog).
- **Near plane.** A vertex behind the eye is multiplied by +Inf instead of
  clipped. The position pass counts vertices with |x/z| < 320 and skips the mesh
  if there are none.
- **Culling.** One FIPR bounding-sphere test per stage chunk (0x8c03be20).
- **Render modes per stage.**
  - Mode 1: no clipping.
  - Mode 2 (0x8c03b140): clips triangles against z = 0.25 in C and sends
    independent triangles.
  - Mode 3 (0x8c03b700): adds per-vertex distance lighting from the fighters.

### Characters (skin 0x8c03cea0, draw 0x8c03cf60)

**Skinning (0x8c03c920).** Each bone owns a list of `{w*x, w*y, w*z, w}`. The
destination pool index is hidden in the low 12 mantissa bits of `w`:

```
mov.w @(12,r5),r0 ; shld #4,r0 ; and #0xfff0,r0 ; add pool,r0   ; offset = index*16 from w's bits (first-influence list: once, then sequential)
fmov @r5+,fr0..fr3
ftrv xmtrx,fv0                ; XMTRX = view x bone: gives w*M*p
tst r0,#0x1f ; bf ; movca.l r0,@r0   ; meant to allocate a 32 B line; tested after add #12, so it never fires
fmov fr2,fr1,fr0 -> @-r0      ; first influence: plain store (15 instructions, 14 executed)
...
fmov @r0+,fr4..fr6 ; fadd x3 ; store   ; later influences: read, add, write back (20 instructions)
```

This is linear-blend skinning with one matrix per bone and no per-vertex matrix
work. The low-bit index costs at most about 1/2048 relative error (4095 ulp)
in the weight.

The rest of the character pipeline:
- **Normals (0x8c03c9ec).** The same scheme against XMTRX = light directions x
  bone rotation (built at 0x8c03c7c0 with 3 FTRV). Costs 34 instructions for
  the first influence and 34 for each added one (30 plus one per lit lane
  executed). The low byte of nz carries a per-vertex highlight factor.
- **Colour pack (0x8c03ca9c, about 41 instructions).** The base colour is the
  saturated sum. The overflow above 255 becomes the offset colour,
  `((c-255)^2 >> 8) * factor >> 8`: a cheap additive highlight. It needlessly
  reloads three zero literals per vertex.
- **Projection (0x8c03c998).** 18 instructions plus the FDIV stall.
- **Emitter (0x8c03cc1a, 27 instructions per strip vertex).** Output is TA
  type 3 (packed base and offset colour, float UV). UVs are two truncated
  16-bit floats: u is the raw word, v is `word << 16`. A per-strip bitmask
  hides parts, and an optional per-strip UV scroll exists.
- **Metal Model (0x8c03fac0 / 0x8c03fcca, emitter 0x8c03cdee, 33 per strip
  vertex).** A screen-space environment map: u = X/640 - n'x, v = Y/480 - n'y.
- **Weapons (0x8c03d720).** The same skin pass, with a ramp-table fake
  lighting per bone (FIPR + FSCA).
- **Estimated cost.** About 100 cycles per unique vertex with one influence,
  about 50 per extra influence, plus about 20 per strip vertex.

### Matrix work (why there are 376 `frchg`)

- `frchg` is used for matrix concatenation, not vertex loops. A matrix is loaded
  into the back bank, 4 FTRVs over the second matrix's columns build the
  product, and a final `frchg` makes the product current without storing it.
- Uses:
  - the skeleton, where the parent stays loaded while its children reuse it
    (51-74 instructions per bone);
  - view x bone and lights x bone per bone (about 120 instructions of setup);
  - two-bone IK on four limbs;
  - hit volumes and effects.
- **Animation (0x8c043000-0x8c05f000).**
  - Euler angles are converted to matrices with FSCA (0x8c03dfa0).
  - Keyframes (0x8c043200) are u8 frame durations plus 15-bit values used as
    16-bit angles (wrapping at 65536), interpolated by a cubic in t.
  - Pose blending interpolates matrices and re-orthogonalises them (0x8c042ee0,
    about 120 instructions per bone), not slerp.

### Shadows (0x8c03da98 -> 0x8c03cd18)

PowerVR modifier volumes:
- The fighter is skinned again with a shadow matrix, projected, and sent to the
  opaque modifier-volume list (PCW `0x81800031`, ISP `0x20000000`). Two effect
  routines (0x8c071eb0, 0x8c0729aa) send an effect mesh, projected with
  fighter 1's shadow matrix, through the same emitter with PCW `0x81800040`.
- The emitter tests each triangle's facing on the CPU (64-bit `fschg` loads of
  X,Y) and sends only triangles of one winding (presumably the front faces), as
  64 B records.
- The likely reading, not verified: the flattened character forms a thin slab
  straddling the floor, so front faces alone shade the floor and the volume
  needs half the triangles.

### Effects

- **Projectors.** 0x8c0610a0 (25 instructions) and 0x8c0c0942 (37 on the
  common path, 40 static).
- **Weapon trails.**
  - A 16-entry ring of tip and base points per trail (sampler 0x8c0c1d40,
    driver 0x8c0adf80).
  - Points are smoothed in screen space by midpoint subdivision. It divides by
    2.0 with FDIV instead of multiplying by 0.5.
  - The textured ribbon costs about 25.5 instructions per vertex (0x8c0ae774),
    the gradient about 33 (0x8c0aea46).
- **Particles.** TA sprites (32 B header + 64 B quad) at an estimated 140-200
  instructions of compiled C each. One ring effect draws its odd segments on
  one frame and its even segments on the next (masks `0xAAAAAAAA` /
  `0x55555555` over 32 segments).
- **Not rendering.** 0x8c0ee620 is the 8x8 IDCT for the image/movie decoder
  (16 FTRV + 2 FIPR per output pixel, 64 pixels per block).

## 2. Getting vertices to the PowerVR

- **The game writes the TA itself through the store queues; it never calls
  `kmSetVertex`.** About 60-80 routines (the count depends on how function
  boundaries are drawn) do the same thing:
  1. read the current list pointer from `*(0x8C266C10+0x6F4)`;
  2. set QACR0/1 = ptr >> 24;
  3. write 32 B blocks to `0xE0000000 | (ptr & 0x3FFFFFF)` and `pref` them;
  4. write the advanced pointer back.
- **The same kernel writes either to the TA FIFO or to RAM.** Kamui sets the
  direct list's pointer to `0x10000000` (0x8C222A9C); the other lists point at RAM.
- **Kamui configuration** (0x8C041754 -> 0x8C228F00): two framebuffers, an 832
  KB uncached vertex buffer, and these buffer shares per list:

  | List | Share |
  |---|---|
  | opaque | 0% (direct to the TA) |
  | opaque modifier volume | 35% |
  | translucent | 60% |
  | translucent modifier volume | 0% |
  | punch-through | 5% |

- **Flush (0x8C2246A0).** It sends the direct list's end-of-list by store queue,
  then walks the buffered lists in hardware order and DMAs each to `0x10000000`
  on ch2 (CHCR2 `0x12C1`). Modifier-volume lists get a header block first when
  a Kamui flag (0x8C379EF8) is 1; its size is a variable (0x8C379F00).
- **Banked vertex buffers** (bank index at 0x8C379E20), so frame N+1's opaque
  list streams while frame N renders. This reading is likely, not certain.
- **Other DMA.** Textures go to `0x11000000` (CPU fallback through
  `0xA4000000`); YUV movies go to `0x10800000`.
- **Main loop (0x8C031420).** Pad, update (0x8C031800), 3D draw (0x8C03ED00:
  fighters and stage), Kamui (0x8C222D20), draw (0x8C02014C), Kamui
  (0x8C224BE0), flush. The begin/end roles of the two Kamui calls are not
  confirmed. No vsync wait or frame skip in game code.

## 3. Cache

- CCR = `0x105` (ICE | OCE | CB), set by syCache. ORA and OIX are never enabled.
- syCache's OCRAM page allocator (0x8C23391C, 8 x 1 KB) is linked but unused.
- **`movca.l`** appears in game code only in the 6 transform loops that write
  pools, to allocate each 32-byte output line without reading it from memory.
  In the skinning loop (0x8c03c920) the line-start test comes after `add #12`,
  so it never passes and that `movca.l` never runs; 5 loops really use it.
  That saves a cache line fill per two 16-byte vertices, which is the main
  memory trick in this game.
- `ocbi`/`ocbp`/`ocbwb` appear only in syCache and Kamui DMA helpers.

## 4. Disc data

- **Containers.** An `olnk` pack (count, `'olnk'`, header size, total,
  offset/size pairs) wrapping an inner pack of end offsets.
- **Compression.** Most data is LZ (decoder 0x8C0EE76C, ported in `tools/lz.py`;
  stage 0's geometry block decodes 71232 -> 124064 bytes):
  - flag byte read LSB first, 1 = literal, with a sentinel stop bit;
    0xFF = 7 raw bytes; 0 = end;
  - back-references are big-endian u16 with `len = ((v>>11)-1 & 31) + 1` and
    `dist = ((v-1) & 0x7FF) + 1`.
- **Characters (`HUMAN.DAT`, 210 entries).**
  - Skeletons use 16-bit fixed point (0x3FFF = 1.0).
  - Mesh vertices are float x,y,z (pre-multiplied by the bone weight) plus w =
    the weight with the vertex index in its low 12 mantissa bits
    (`0x3F800000 | i` for a full-weight vertex), ready for `ftrv`.
  - Each model has four 256x256 16-bit texture pages.
- **Stages (`STAGE.DAT`, 23 stages).**
  - Each holds one LZ geometry block, a few small TIM textures (mostly
    LZ-compressed), and 9-15 256x256 16-bit pages (stage 13 has 2). Stages are
    about 1.4-2.3 MB (stage 13: 0.34 MB).
  - Strip records are `u16 index, u16 index | 0x8000 (end), u16 V, u16 U`: one
    little-endian u32 with U in the high half, each the top half of a float
    (the PVR 16-bit UV format).
  - Polygon headers are per-mesh templates with per-object bits ORed in.
- **Textures.**
  - Mostly PlayStation TIMs (4/8 bpp + palette) drawn as PVR palettized
    textures (`0x28000000 | pal<<21` for 4 bpp, `0x30000000` for 8 bpp).
  - No VQ. Textures are managed as whole pages (`"Free Texture Page = %d/%d"`),
    and `PalBlink` animates palettes.

## 5. Frame level

- **Shadows.** Opaque modifier volumes, matching the 35% buffer share.
- **HUD.** TA sprites (PCW `0xA2840009`). Additive blending (`0x84000000`, 52
  sites) and normal alpha (`0x94000000`, 53 sites).
- **Stage effects** are per-stage objects (`TakiObj`, `Hamon`, `Ripple`,
  `SuiMen`, `Snow`, `LgtBlur`, `PalBlink`).
- No profiler, polygon counters or LOD strings were found. Dev overlays exist:
  `"#X#Y motion_cnt=%d"`, `"Motion monitor for dev."`.

## 6. Comparison

| | Soulcalibur | Test Drive Le Mans | WSB 2K2 |
|---|---|---|---|
| Vertex sharing | yes: pools + indexed strips | no | yes (pool of at most 256, OCRAM) |
| Passes | 3 (position, lighting, emit) | 1 | 2 |
| Emitter FPU work | none (integer copy) | all | strip walk + cull |
| Lighting | 4 coloured lights in 2 FTRV, packed ARGB | baked intensity / 1 FIPR | 3 diffuse + specular per FTRV, intensity mode |
| Skinning | per-bone weighted vertex lists, 1 FTRV per influence | rigid cars | runs per weight set, quantized blends |
| 1/w | FDIV, unpipelined | FDIV, unpipelined | FDIV (1/z), 4-deep pipeline |
| Near plane | +Inf multiply; C clip on some stages | in-strip clip | sentinel |
| Pool writes | `movca.l` per 32 B line (5 of the 6 pool writers; the skinning loop's check never fires) | none | OCRAM |
| Shadows | modifier volumes (one winding) | | modifier volumes |

## Uncertainties

- The shadow-slab reading.
- The meaning of stage render mode 3.
- `attr` byte 3 as fog.
- Whether any list besides opaque goes straight to the TA.
- Exact Kamui config field names.
- Stage culling and LOD were not analysed in depth.
