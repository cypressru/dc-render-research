# World Series Baseball 2K2 (Dreamcast, 2001): renderer source

Developer: Blue Shift, Inc. Renderer by John Brooks. SDK: Kamui2.

Unlike the other games in this repository, this folder has the **original
source** of the renderer, released publicly:

| File | Revision | Contents |
|---|---|---|
| `source/Render.c` | `$Id: Render.c,v 1.88 2000/11/17` | C side: model and playfield drawing, chunk culling, clipped strips, shadows, bump mapping, weighted matrices, projection |
| `source/Render.s` | `$Id: Render.s,v 1.34 2000/11/17` | Hand-scheduled SH4 assembly: vertex transform, lighting, strip processing, shadow emit, matrix/material loads, cache split |

Both files are Copyright (c) 2000 Blue Shift, Inc. and are included unmodified
(SHA-256 `4eba82abc8fc764e8668f03ab57e8ae91c2966607b07babb155863b070c8225c`
and `80f77f1aa676e003ba033a7283ec4d2679b4c4cbdbcf144d9055bab4b973d435`).
The notes below describe the techniques and where to find them.

## Pipeline

Each visible chunk is a "vertex pool" of at most 256 vertices:

1. **Batch transform into on-chip RAM** (`_Ren_TransformVertices`, Render.s
   426; float variant `_Ren_TransformFloatVertices`, 202).
   - Every vertex of the pool is transformed in one hand-scheduled loop and
     written to OCRAM.
   - Model positions are 3 bytes per vertex: one signed byte per axis,
     indexing a shared 256-entry byte-to-float table (a coordinate palette:
     the `fCvtChar` array at the start of the normal table, passed as
     `&pNormalTable[128]`, Render.c 339). Playfield areas use float positions
     and the float variant.
   - The loop is software-pipelined four deep across FV0/FV4/FV8/FV12. In one
     step vertex N is in FTRV, N-1 in the FDIV (true 1/z), N-2 is projected and
     N-3 is stored.
   - Most instructions carry a comment with a cycle count and pipe (`1X`, `2L`,
     `13F`, ...), so the dual-issue pairing is explicit.
2. **Strip walk with screen-space back-face culling** (`_Ren_ProcessStrips`,
   Render.s 980).
   - Strips are byte indices into the pool.
   - For each new strip vertex, the triangle's winding comes from two FIPRs and
     one FCMP. FIPR computes `x0*y1+x1*y2+x2*y0` and `x0*y2+x1*y0+x2*y1` as two
     4-element dot products, and comparing the sums gives the area's sign.
   - Six unrolled variants rotate which register holds which coordinate, so no
     data moves as the strip advances and strip parity costs nothing.
   - Leading back-facing triangles are skipped. At the first front-facing
     triangle the walk enters the emit path, which starts a new TA strip there
     and streams the rest of the strip to the store queues with no further CPU
     test.
3. **Chunk culling** (`Ren_CheckVisible`, Render.c 2295, called per
   playfield area at 1878). The 8 corners of the cube around the area's
   bounding sphere are transformed with `_Ren_TransformFloatVertices` and
   classified with integer compares on the float bit patterns. A batched
   version for many areas, `_CullPFBBoxes` (Render.c 1557), is compiled out
   (`#if 0`); it tests `(bits & 0x7fffffff) < limit` as `|x| < limit`.
4. **Materials** (`_Ren_LoadMaterials`, Render.s 2310). 16-byte material
   records (range bytes plus ISP/TSP/TCW) are copied into a 64-entry table in
   OCRAM. A material switch in the strip stream emits a new polygon header
   from that record, with the PCW from `_iMatPCW` in the `_Ren_MaterialCache`
   block (Render.s 1345, in normal RAM).
5. **Clipped chunks** take a separate builder (`Ren_BuildClippedStrip`,
   Render.c 1180; the second definition at 1377 is the disabled `#else`
   branch). The fast path assumes every vertex is in front.

## SH4 techniques

- **OCRAM** (`__VCCPU_SplitCache` / `__VCCPU_UnsplitCache`, Render.s 2379/2492).
  - Setting CCR.ORA after purging the affected lines turns half of the 16 KB
    operand cache into 8 KB of zero-wait RAM, mirrored at 0x7C000000-0x7FFFFFFF.
    The renderer uses 0x7DFFF000-0x7E000FFF (layout comment at Render.s 986).
  - The transformed vertex pool, specular, material table and UVs live there.
    `__VCCPU_UnsplitCache` purges the lines and clears ORA again (OIX stays
    set), so the split can be limited to the draw; the callers are not in
    these two files.
- **Cache partitioning with index mode.** CCR.OIX (set together with ORA,
  Render.s 2411) makes address bit 25 choose the cache half. Main RAM is mirrored every 16 MB, so XOR-ing a pointer with
  0x02000000 puts a hot table (the normal table, Render.c 273) in the other
  half, where streaming vertex data cannot evict it.
- **Integer work paired with FP work.** The SH4 issues two instructions per
  cycle from different groups. Bounds tests, index math, address arithmetic and
  table lookups are done on the integer and load/store pipes, so they pair with
  the FTRV/FDIV/FIPR stream. In the C culling code the stated reason for
  integer compares on float bits is speed ("Int compares are much faster than
  float compares...", Render.c 2374).
- **True FDIV for 1/z** is affordable when the pipeline hides its latency.
- **64-bit paired FPU moves** (FSCHG) for matrix and material loads; the
  matrix goes straight into the back bank with FRCHG (`_Ren_LoadMatrix`,
  Render.s 2269).

## Transform and projection

- **Projection folded into the matrix** (`View_CreateProjectionMatrix`,
  Render.c 2932). The matrix carries the focal scale and the screen centre, so
  after FTRV the screen position is X/Z, Y/Z: one multiply per coordinate.
- **Centre at 0 for the playfield** (Render.c 1720). The projection is rebuilt
  with centre 0 ("so polys can be clipped"), which makes on-screen tests
  symmetric (the disabled `_CullPFBBoxes` tests |x| < 320 as one integer AND
  and compare on the float bits). The real centre is stored in
  `_fCenterX/_fCenterY` (Render.s 1356; set at Render.c 1725) and added only
  at emission (FADD, Render.s 1541).
- **Near test on the integer pipe, divide skipped.** The float transform moves
  Z to an integer register through FPUL and compares it with the bit pattern of
  1.0. Vertices behind the near plane skip the FDIV, and their 1/z is left at
  1.0, which later acts as a "behind" sentinel compared as an integer
  (`_SkipDivLabel`; `_FltClip` is an unused early exit). The routine returns
  how many vertices are in front.
- **Two-level visibility.** Per area, `Ren_CheckVisible` rejects areas off
  screen or behind the camera; then the area's transform reports how many of
  its vertices are in front (Render.c 1895).
  - All in front: every strip takes the fast path.
  - Some behind: `Ren_BuildClippedStrip` splits strips into an all-visible
    list (fast path) and a list of single triangles touching the near plane
    (Render.c 1995-2019).
- **No geometric near-plane clipping.** Partly-behind triangles are emitted
  with the sentinel vertices, and fully-behind ones are dropped. This suits a
  stadium camera.

## Strips and materials

- Strip header byte: `(triangle count << 1) | parity` (parity is free).
- **Material changes live in the strip stream.** A negative strip byte (-1 to
  -64) switches to that material from the OCRAM material table, so faces carry
  no material field.
- Polygon headers use strip length 6 (`KMY_GROUP_STRIP6`) with TA user clipping
  disabled (`KMY_GROUP_CLIP_DISABLE`, Render.c 277).

## Emission

- **Intensity colour mode** (`KMY_OBJ_INTENSITY1 | KMY_OBJ_OFFSET |
  KMY_OBJ_16BITUV`, Render.c 277-278). Vertices carry a float intensity and a
  specular offset with the base colour in the header, so lighting goes to the
  TA without packing float to ARGB per vertex.
- **Store queues.** Each vertex is one 32-byte block, so successive vertices
  alternate between the two queues, and `PREF` on the SQ address sends each
  one (`Ren_PrepStoreQ`, Render.c 2229, sets QACR0/1 and returns the SQ-area
  address). A disabled alternative emitter (`#else` branch, Render.s
  1649-1852) is padded with NOP blocks; the source gives no reason, but
  throttling to TA bandwidth is the likely one.

## Lighting (models, `_Ren_LightVertices`, Render.s 698)

- **Normals as a 1-byte index** into a 256-entry normal table stored as
  separate X/Y/Z arrays after the byte-to-float array (layout as in
  `Ren_CopyNormalTable`, Render.c 2203).
- **Four light lanes in one FTRV.** XMTRX holds four light directions in joint
  space, one per column, with a bias in the first row (Render.c 3330-3347).
  One FTRV of (1, nx, ny, nz) gives three diffuse terms and, in lane 2, the
  specular term. A FIPR with the constants (SmallFrac, SmallFrac,
  ClampOffset + ambient, SmallFrac) sums the diffuse terms into one intensity
  (macro `_mLightVertices`, Render.s 734). There are no light colours: the
  colour comes from the header.
- **Branchless clamp via the FPU.** Each diffuse lane adds `MaxNeg`
  (-FLT_MAX). In round-to-zero mode (set at entry because "round-to-nearest
  give +- infinities", Render.s 808) a negative N.L saturates at -FLT_MAX
  instead of becoming -Inf. Scaling by the smallest normal float
  (`_LTScaleDown`, 0x00800000) and adding `_LTClampOffset` (about 3 x 4) then
  leaves each light in 0..1, with back-facing lights at zero (constants and
  comments at Render.c 107-113).
- **Specular power on the integer pipe** (`_Ren_ProcessStrips`, Render.s
  1538). An ADD and an SHLD on the float's bit pattern, with the shift picked
  per material from `Strip_SpecTable` (Render.s 1363, "Exp==1" to "Exp==32"):
  exponent arithmetic approximates x^(2^k).

## Skinning (`Ren_RenderNonMorph`, Render.c 246; `Ren_BuildWeightedMatrices`, 3033; `Ren_Debug_Build_Matrices`, 3254)

- Vertices are grouped into runs per weight set. Each run loads one matrix and
  transforms with one FTRV per vertex.
- Weighted vertices use precomputed blended matrices. Weights are quantized to
  100 / 75 / 50 / 25 % between a joint and its parent, giving 4 matrices per
  joint (blended per frame at Render.c 3360, selected by `iWeightOffset >> 6`
  at 327).
- Each matrix already includes projection x view x bone, so skinning and
  projection are the same FTRV.
- Whole-model early out: after each run, if its first vertex is behind the
  camera or nearer than `_CULL_SEGMENT_DISTANCE` (2.5, tested on 1/z), the rest
  of the model is skipped (Render.c 341).

## Other

- **Shadows** (players and playfield shadow areas) are PVR modifier volumes in
  the opaque modifier list (`Ren_ShadowStrips` Render.c 379,
  `Ren_ShadowNonMorph` 1066; assembly variant `_Ren_DrawShadow` Render.s
  1905), with strip length 1 and `KMY_OBJ_LAST_MODIFIER` closing each volume.
  The receiving polygons set `KMY_OBJ_SHADOW_POLYGON` in their PCW
  (Render.c 277).
- **Bump mapping** for players (`Ren_BumpmapNonMorph`, Render.c 2777) is
  compiled out (`#if 0`) in this revision.
- **Visibility test:** `Ren_CheckVisible` (Render.c 2295), used here for
  playfield areas.

## Caveat: the FIPR-pair back-face test

This is our own precision analysis; the source does not discuss it. The two
FIPR sums are large in screen coordinates (about 1e5) while their difference
is the triangle's area. For small triangles far from the screen
origin, rounding (and FIPR's reduced hardware precision) can flip the sign.
The test appears to suit WSB's chunky stadium geometry. Dense meshes with small
triangles need the subtracting form,
`(x1-x0)(y2-y0) - (x2-x0)(y1-y0)`, or coordinates re-centred per triangle.

## Comparison with the other games here

| | WSB 2K2 | Test Drive Le Mans | Soulcalibur |
|---|---|---|---|
| Vertex sharing | pool of at most 256, OCRAM | none | pools + indexed strips |
| Transform loop | 4-deep software pipeline, pipes annotated | unpipelined | unpipelined |
| Source positions | 3 B palette indices (models), floats (playfield) | 24-32 B floats | 16 B floats |
| CPU back-face cull | FIPR pair, leading triangles of each strip | none | shadow volumes only |
| Lighting | 3 diffuse + specular per FTRV, intensity mode | baked intensity / 1 FIPR | 4 coloured lights in 2 FTRV, packed ARGB |
| Skinning | quantized blended matrices | rigid | per-bone weighted lists |
| Near plane | 1/z sentinel, no clip | in-strip clip | +Inf multiply / C clip |
| Cache | OCRAM + OIX during the draw | default | `movca.l` pool writes |
