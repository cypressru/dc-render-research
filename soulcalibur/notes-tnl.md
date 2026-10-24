# Soulcalibur (Dreamcast, 1999): transform and lighting loops

Namco, USA disc. Libraries: Kamui 1.06 (Feb 1999) and Shinobi 1.43. The main
executable is `1ST_READ.BIN` (3.6 MB, load base `0x8C010000`):

- Game code: about `0x8c010000-0x8c103000`
- Data: from about `0x8c103000`
- Libraries: about `0x8c21a000-0x8c246000` (plus non-SDK library code at
  about `0x8c1f2000-0x8c20d000`)

Everything here comes from static analysis of the disassembly. Nothing was
measured. Cycle figures are estimates from instruction counts and SH4 latencies
(FTRV issues at 1 per cycle with 4-5 cycles latency, FDIV about 12 cycles
latency). Annotated loops are in `listings/tnl-loops.s`.

## Summary

1. **One shared pipeline for the stage and the characters, in 2-3 passes.**
   - Pass 1 transforms positions into a pool of 16-byte entries.
   - Pass 2 lights the normals into a colour pool: 4 directional lights with
     2 FTRV per vertex.
   - Pass 3 walks indexed strips and copies the pool entries into TA vertices
     through the store queues. This pass does no floating-point work.

   This is the same split as WSB 2K2, and unlike Le Mans, where each strip
   vertex is re-transformed.
2. **FTRV lighting with 4 lights.** XMTRX rows hold 4 light directions, so one
   FTRV gives all four N.L values, each clamped at 0. A second FTRV with XMTRX
   = 4 light colours (columns) gives the RGB sum, and an integer ambient term
   is added. The result is a packed ARGB colour. No intensity mode is used.
3. **Skinning by weight pre-multiplied partial vertices.** Each bone owns a
   list of vertices stored as `{w*x, w*y, w*z, w}`. FTRV by view*bone gives
   `w*M*p`. The first influence is stored, and later influences are added into
   the pool entry, with the destination index hidden in the low 12 mantissa bits
   of the `w` float. This is linear blend skinning with one matrix per bone and no
   per-vertex matrix work. Normals use the same scheme, against a per-bone
   "light directions x bone rotation" matrix, so normals are never rotated
   into view space.
4. **The FRCHG count comes from matrix work, not vertices.** FRCHG pairs load a
   matrix into the back bank. The 4x4 product is then built with 4 FTRV over
   the second matrix's columns, and a final FRCHG makes the product XMTRX
   without a store. It is used for:
   - parent*local in the skeleton (0x8c043098, with XMTRX cached while the
     parent stays the same)
   - view*bone and lights*bone for each bone, before its vertex lists
   - IK, collision volumes and effect matrices

   The IK code appears to be repeated for each of the four limbs (not checked
   in detail), which also adds to the count.
5. **Per-vertex culling and clipping are minimal.**
   - Stage chunks are culled by bounding sphere with one FIPR plane test
     (0x8c03be20).
   - The position pass counts vertices with `|x/z| < 320`. If the count is 0,
     the mesh is skipped.
   - Vertices behind the eye are multiplied by +Inf (a sentinel), not clipped.
   - Each stage picks a render mode: mode 1 has no clipping. Mode 2
     (0x8c03b140) clips each triangle against z = 0.25 in C, with one FDIV per
     output vertex, and emits independent 3-vertex strips.
   - Back faces are culled on the CPU only for shadow volumes.
6. **Output path.** The game writes into Kamui's per-list vertex buffers
   directly, through the store queues:
   - The buffer pointer table is at `*(0x8c267304)`, which is `0x8c266c10+0x6f4`.
   - QACR0/1 are set to `ptr>>24`, and the store-queue address is
     `(ptr & 0x3ffffff) | 0xE0000000`.
   - The advanced pointer is written back to the table.
   - Kamui's end-of-pass loop (0x8c2245a0) sends the 5 list buffers to the TA
     (0x10000000) through 0x8c237c68, which programs DMA channel 2 (SAR2/DAR2
     at 0xffa00020, SB_C2DSTAT 0xa05f6800).
   - No `kmSetVertex` call is used.
7. **PCW and constant words stay in the store queue.** Each emitter writes PCW
   `0xE0000000`, and any constant colours, into both 32-byte SQ halves once.
   The SQ keeps its contents after a burst, so per vertex only the changing
   words are written. Only the last vertex of a strip is overwritten with
   `0xF0000000`. Most emitters use this; the rain streak (0x8c06beb2) instead
   writes a PCW per vertex from a table.
8. **`movca.l`** is used in game code only by the pool writers. A cache line
   is allocated (no fetch for ownership) when the output pointer reaches a
   32-byte boundary (`tst #31` then `movca.l`, every other vertex). In the skinning loop
   0x8c03c920 the test is made on entry+12, which is never 32-byte aligned for a
   16-byte-aligned pool, so its `movca.l` never runs. Outside syCache, the other
   `movca.l` hits (0x8c11ad66-0x8c20b010) are data decoded as code.

## 1. Frame orchestration (0x8c03ed00-0x8c03f0c0)

For each of the two fighters (draw structs 0x8c25e058 and +0x45dc), it
chooses by mode bytes:

| Byte | Value | Routine |
|---|---|---|
| +0x198 (body) | 1 or 3 | 0x8c03cf60, normal skinned body (3 = additive TSP 0x84100000) |
| +0x198 (body) | 2 | 0x8c03fe20, **Metal Model** (screen-space env map) |
| +0x19a | 1 | 0x8c03d720, weapon and parts |
| +0x19a | 2 | 0x8c03fe44, metal weapon |
| +0x199 / +0x19b | | 0x8c03da98, **shadow modifier volume** (body with `r7 = -1`; weapon with the part mask from +0x1b0) |

Then the stage object (ctx+36) is drawn by the mode at +74:

| Mode | Routine |
|---|---|
| 1 | 0x8c03b4e0, unclipped |
| 2 | 0x8c03b140, triangle near-clip |
| 3 | 0x8c03b700, per-vertex distance lighting from the fighters (fsqrt; only for a fighter whose +0x5c30 field in the 0x8c24a958 / +0x86dc blocks is 19). Also taken when +74 is non-zero and `*0x8c25b8bc == 14` |

After that come the chunked stage meshes (0x8c03bb44 + 0x8c03bc40, with the
0x8c03bd7e chunk cull), dynamic stage objects (0x8c03be92, with 0x8c03c886
object matrix and FIPR cull) and a scrolling-UV extra layer (0x8c03ae6e, near
clipped). The fog colour is written to 0xa05f80b0/b4.

## 2. Stage and rigid meshes

| Routine | Role | Instr/vertex |
|---|---|---|
| 0x8c03a9cc | pos {x,y,z,attr} -> pool {X+320, Y+240, k/z, attr}; returns on-screen count | 30 (1 FTRV, 1 FDIV) |
| 0x8c03a9a0 | view-space only (clip path) | 17 |
| 0x8c03aa3c | normal -> 4 clamped N.L | 29 (1 FTRV, 4 branches) |
| 0x8c03aa84 | 4 N.L -> 0x00RRGGBB via the colour matrix + ambient, saturate | 29 (1 FTRV; 32 if all three saturate) |
| 0x8c03ab1c | strip emitter, TA type 4 (packed colour, UV16), 32 B | 30 per strip vertex, 0 FP |
| 0x8c03abb0 | same, with per-vertex offset colour (colour entry word 1) | 31 |

- **Source vertex: 16 B floats `{x, y, z, attr}`.**
  - Byte 2 of `attr` becomes the base alpha and byte 3 the offset alpha
    (probably the fog factor). The emitter does this with
    `shll8 & 0xff000000`.
  - Normals are 16 B `{nx, ny, nz, pad}`.
- **Strip vertex: 8 B** `{u16 pos idx & 0x3fff, u16 colour idx | bit15 = end
  of strip, u32 UV16}`, after a 4-byte strip header.
  - The header's byte 0 low nibble selects one of 16 material headers (64 B
    each at ctx+0x764+40). Bit 6 selects translucent (list 2) instead of
    opaque (list 0).
  - The 32-byte TA header is written to the SQ from the material (PCW, ISP,
    TSP | fog bits, texture) before each strip group.
- **Per-vertex cost:** about 88 instructions per unique vertex plus 30 per strip
  vertex. Estimate 70 cycles (one FDIV stall of about 9 cycles, 2 FTRV, mostly
  load/store bound) plus about 20 cycles per strip vertex. With strips about
  1.5 times as long as the unique vertex count, that is about 100 cycles per
  unique vertex.

## 3. Characters (0x8c03cea0 skin pass, 0x8c03cf60 draw)

For each bone (count at mesh+28, 32-byte bone records from mesh+32, 64-byte
matrices at `*(char+0x1d4)+0x80`; weapon and attachments at +0x1800):

1. 0x8c03c81c: XMTRX = view x bone (4 FTRV).
2. 0x8c03c920: skin positions. 15 instructions per first influence (sequential
   destination; 14 run, because its `movca.l` test never passes), 20 per extra
   influence (indexed read-modify-write).
3. 0x8c03c7c0: XMTRX = light directions x bone (3 FTRV).
4. 0x8c03c9ec: normals. 34 instructions first, 34 to accumulate (the `fadd` of
   an unlit lane is skipped). The
   sign of the low half of `w` selects the path. The low byte of `nz` is a
   per-vertex highlight factor, copied into byte 0 of the colour entry.

After the bones:

- 0x8c03ca9c packs the colours: base = saturated sum. The overflow above 255
  becomes the **offset colour**: `((c - 255)^2 >> 8) * factor >> 8` per
  channel, which gives a cheap additive highlight. About 41 instructions on
  the common path. It loads three zero constants from the literal pool per
  vertex (`mov #0` would do).
- 0x8c03c998 projects the pool: 18 instructions plus the FDIV stall.
- 0x8c03cf60 emits each strip group through 0x8c03cc1a: TA type 3 (packed
  base and offset, float UV), 27 instructions per strip vertex.
  - UVs are two truncated 16-bit floats in one word: u is the raw word, and
    v is the word shifted left by 16.
  - A per-strip bitmask hides parts, through the header's bit index.
  - A second path adds a per-strip UV scroll.
  - Headers are chosen per strip: opaque, or translucent (TSP 0x94100000)
    when the alpha byte is below 0xfc.
- **Cost:** about 108 instructions per unique vertex (one influence), about
  54 more for each extra influence, and 27 per strip vertex. Estimate 85-100
  cycles per vertex, plus about 20 per strip vertex. Per bone there are about
  120 instructions of matrix setup.
- **Skeleton** (from the 0x8c043000-0x8c05f000 pass):
  - Euler angles to matrices with FSCA (0x8c03dfa0).
  - Keyframes (0x8c043200) are u8 frame durations plus 15-bit values
    (`& 0x7fff`, `<< 1`) used as 16-bit angles that wrap at 65536,
    interpolated by a cubic in t (t, t^2, t^3) and stored as u16.
  - Pose blending is matrix nlerp with Gram-Schmidt re-orthogonalisation
    (0x8c042ee0, about 120 instructions per bone, using `fipr`+`fsrra`
    normalize).
  - Two-bone IK on the four limbs (0x8c043400 and 0x8c044920).
  - Concatenation is 0x8c043098.
  - There is no matrix palette for each vertex: blending happens only through
    the accumulated partial vertices.
- **Metal Model** (0x8c03fac0 + 0x8c03fcca, string "METAL MODEL"):
  - Normals are transformed with the translation zeroed (0x8c03cba0) and
    scaled by 1/z (loop 0x8c03fc4e).
  - The emitter 0x8c03cdee sets `u = X/640 - n'x`, `v = Y/480 - n'y`: a
    screen-space env/refraction map.
  - The colour is constant and written once into the SQ by the caller. 33
    instructions per strip vertex.
- **Weapon and parts** (0x8c03d720): the same skin pass. Per bone there is a
  FIPR of the light against an axis, FSCA, then a lookup in a ramp table that
  chooses the material colours (a fake lighting ramp for the weapon).

## 4. Shadows: modifier volumes (0x8c03da98 -> 0x8c03cd18)

- The fighter's mesh is re-skinned with a shadow matrix (char+0x1dc x bone),
  then projected.
- It is emitted to list 1 (opaque modifier volume) with header
  `0x81800031 / ISP 0x20000000`.
- 0x8c03cd18 walks the strips as triangles:
  - It loads `(X, Y)` pairs with `fschg` 64-bit moves and tests the signed
    area, so only triangles of one winding (presumably front-facing) are
    emitted.
  - Each emitted triangle is a 64-byte TA modifier-volume record
    `{PCW 0xF0000000, A, B, C}`. The PCW is written once, because each record
    is exactly two SQ halves.
- **Interpretation (uncertain):** the matrix flattens the character into a
  thin closed slab that straddles the floor. Only front faces are needed for
  the floor pixels, which halves the number of volume triangles.
- The same emitter is reused by an effect routine (0x8c071d5c, and its twin at
  0x8c0729aa) that projects an effect mesh with fighter 1's shadow matrix
  (0x8c25e058+0x1dc) and sends it with header 0x81800040. Which effect it is
  (fire?) is not confirmed.

## 5. Effects

- **Shared batch projector 0x8c0610a0:** like 0x8c03a9cc but with no counter
  and no `movca.l`. 25 instructions, about 30 cycles per vertex. Used by
  stage particles, the mesh effect and others.
- **Effect point projector 0x8c0c0942** (with 0x8c0c08f2 and 0x8c0c09ae):
  37 instructions on the common path (40 static), about 35 cycles per point.
  A point behind the eye gets 1/z = FLT_MAX (sentinel at 0x8c1382bc).
- **Weapon trails** (0x8c0c1d40 sampler, 0x8c0adf80 driver):
  - Each trail keeps a 16-entry ring of {tip, base} points in world space.
  - The points are projected, then smoothed in screen space by midpoint
    subdivision (0x8c0ae216, which uses FDIV by 2.0 instead of a multiply).
  - Textured mode (0x8c0ae774): about 25.5 instructions per vertex, with a
    fade ramp table.
  - Untextured gradient mode (0x8c0aea46): about 33 instructions per vertex,
    with colour steps from 8 FDIVs per trail.
  - Output goes to list 2 (translucent).
- **Particles:** TA sprites only (32 B header + 64 B quad), with rotation by
  one `fsca` (0x8c0b5da0). Each costs 150-200 instructions of compiled C.
  - Bone-attached aura sprites are stretched between joints (0x8c0b62c0).
  - A 32-segment ring effect draws its odd segments on one frame and its even
    segments on the next (mask 0xAAAAAAAA / 0x55555555, 0x8c0b196e).
  - The effect dispatcher (0x8c0700ec) handles beams, billboards, polygons
    of up to 8 vertices (count-1 masked with 7; 14 instructions per
    vertex) and mesh effects (0x8c06f9e2, 46 instructions per vertex,
    compiled C).
  - The stage effects (Sakura, Rain, Fire, Leaf, Snow, Sand...) are C code
    on top of these emitters.
- **Not T&L:** 0x8c0ee620 is an 8x8 IDCT (16 FTRV + 2 FIPR per output pixel)
  for the movie or image decoder. 2D/UI emitters are at 0x8c063aba,
  0x8c06e54e and 0x8c0c9b5e+.

## 6. Where the time goes

**Likely most of the vertices: the two fighters through the 0x8c03c920 /
0x8c03c9ec / 0x8c03ca9c / 0x8c03c998 skin passes plus the 0x8c03cc1a
emitter.** Estimates:

- About 100 cycles per unique vertex for single-influence vertices, plus
  about 40 per extra influence.
- About 20 cycles per strip vertex for the emitter.
- Then the shadow volume pass skins the positions again (15-20 instructions
  per influence plus 18 to project, plus about 26 per triangle tested and 22
  more per emitted triangle).

The stage (0x8c03a9cc / aa3c / aa84 + 0x8c03ab1c) costs about 70 + 20 cycles,
and may well carry as many polygons. The binary does not give the scene sizes.

The loops have these properties:

- No software pipelining.
- FDIV for 1/z in every loop, never FSRRA, with about 9 stall cycles each.
- No pairing of loads ahead of use.
- Hand-written but simple.

The design wins come from vertex sharing, 2 FTRV for 4 coloured lights, and
the emitter carrying no floating-point work.

## Uncertainties

- The mode-3 meaning and the value 19 (a per-player field, possibly a
  character id) are not identified.
- The modifier-volume flattening interpretation (section 4).
- Whether any list pointer is the TA FIFO directly (Kamui direct mode) rather
  than a RAM buffer. The code handles both, but the DMA loop exists.
- Offset alpha from `attr` byte 3 as fog is a guess.
- The strip-to-unique vertex ratio is unknown, so the per-polygon totals are
  unknown.
