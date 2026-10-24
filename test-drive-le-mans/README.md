# Test Drive Le Mans (Dreamcast, 2000): renderer analysis

Developer: Infogrames Melbourne House ("Vertigo" engine). SDK: Kamui2
(NEC, Oct 1999) and Shinobi 1.68. Main executable `LEMANS24.BIN` (2.2 MB,
load base `0x8C010000`); `1ST_READ.BIN` is a loader. All findings are from
static analysis of the USA disc (disassembly and data files). Nothing was
measured at runtime. Addresses are virtual addresses in `LEMANS24.BIN`.

Listings (`listings/`):

| File | Contents |
|---|---|
| `tnl-loops.s` | The bulk vertex kernels (PIT and PNT no-clip), the near-clip strip kernel, an SDK-style transform loop (probably from Sega sample code) for comparison |
| `pct-argb-lerp.s` | Packed-colour clip path: two ARGB channels per register with 8.8 fixed point |
| `more-vertex-kernels.s` | 16-bit truncated-float vertices, outline effect, in-place end-of-strip PCW, car env-map lighting pre-pass |
| `scene-and-lod.s` | LOD layer cull node, sphere/frustum test, strip-vertex count, car LOD budget controller |

## Summary

The game is fast because each vertex costs little and every scene is held
under a budget, not because it sustains huge polygon counts. The Le Mans
track's four layers hold about 54k triangles (plus about 18k in instanced props). There is no evidence in
the binary for the "5 million polygons per second" figure. At 60 fps that would
be 83k triangles per frame. A CPU-only estimate for the bulk kernel is about
30-34 cycles per vertex, about 6M vertices/s at 200 MHz, but that is a peak for
the transform loop alone.

1. **Small hand-written kernels, one per vertex format.** The track's prelit
   kernel is 30 instructions per vertex (31 on a strip's last vertex). It goes from float source data to the
   store queues in one pass, with no intermediate buffer and no per-vertex
   decision except end of strip.
2. **No per-vertex culling.** Each object is tested once: bounding spheres
   against the frustum, then a box against the near plane. Objects wholly in
   front of the near plane take a no-clip twin kernel, and objects crossing it
   take a near-clip kernel that clips inside the strip.
   Screen edges, back faces and depth are left to the PVR.
3. **Intensity colour mode.** Track lighting is baked offline as a float
   intensity per vertex. Cars compute one FIPR (ambient + N.L) plus a
   float-bit specular. The colour comes from the polygon header, so these
   kernels pack nothing to ARGB per vertex (the car-paint pre-pass and the
   PCT class are the exceptions).
4. **Opaque straight to the TA, the rest buffered.** The opaque list is
   written by store queue directly into the TA FIFO while the PVR renders the
   previous frame. Translucent and punch-through vertices are buffered in RAM
   by Kamui and sent by DMA ch2 at the end of the pass.
5. **Budgets and layers instead of LOD swaps.** Track "LODs" are distance
   layers (far-plane multipliers 1.0 / 0.55 / 0.23). A fixed budget of 37000
   strip vertices per frame is enforced by stepping car LODs only, farthest
   car first (and, as a last resort, dropping the farthest cars).
6. **Content shaped offline.** The track uses 9 distinct render states, 115
   texture names and 50 distinct material blocks, one header per mesh and
   material, and strips cut by the track tool.

No OCRAM, operand-cache index mode or other cache tricks are used.

## 1. Vertex kernels

### Format classes

Each Kamui geometry class has its own kernel pair (names from RTTI/vtables).
Counts are instructions per vertex on the common path (one more on a strip's
last vertex; ranges are without/with specular):

| Class | Input vertex | TA output (32 B) | No-clip twin | Near-clip kernel |
|---|---|---|---|---|
| PIT (track) | 24 B {x,y,z,I,u,v} | textured intensity, base = I, offset 0 | 0x8c061fc0 (30 instr) | 0x8c0b0be0 |
| PNT (lit) | 32 B {x,y,z,nx,ny,nz,u,v} | base = ambient + N.L, offset = specular | 0x8c061d40 (37-44) | 0x8c0b0260 |
| PNT_c | 16 B, truncated 16-bit floats | as PNT | 0x8c061e00 (46-53) | 0x8c0b0260, after expanding to 32 B |
| PNTX | pointer list | as PNT | 0x8c061ee0 | 0x8c0cde20 |
| PN | 24 B {P,N} | untextured, base = ambient + N.L | 0x8c062160 | 0x8c0b1440 |
| PNX | pointer list | as PN | 0x8c062220 | 0x8c0cd660 |
| P | 12 B | flat (header colour) | 0x8c062060 (25) | 0x8c0b1be0 |
| PT | 20 B {x,y,z,u,v} | base = offset = 1.0 (the no-clip twin leaves the offset word unwritten) | 0x8c0620e0 (28) | 0x8c1bddc0 |
| PCT | 24 B {x,y,z,ARGB,u,v} | packed colour | 0x8c061fc0 (shares PIT's) | 0x8c15a320 |
| PITX | pointer list | base 1.0, offset = I | | 0x8c149e80 (no twin) |
| Reflective | pointer list, 28 B {P, base, offset, u, v} | packed ARGB | 0x8c165b80 (30) | 0x8c164b40 |
| Outline (PN, PNX) | {P,N}, P += width*N | intensity 1 | 0x8c0ce740 (34) | 0x8c0ce880; PNX uses 0x8c124600 for both |

Common argument block (`r4`): strip-length byte list, vertex (or pointer)
array, store-queue destination, then a light vector `{Lx, Ly, Lz, ambient}`.
Each strip-list byte is a triangle count (vertices = n + 2), and 0 ends the
list. PCWs are not in the vertex data: `0xE0000000` and `0xF0000000` (end of
strip) are register constants, selected by `cmp/eq #1,r0` on the last vertex.

### Bulk path: PIT no-clip (0x8c061fc0), 30 instructions per vertex

```
fschg                      ; SZ=1: fmov moves 64-bit pairs
fmov @r2+,dr4              ; (x, y)
fmov @r2,dr6               ; (z, I)   no post-increment
fldi1 fr12
fldi1 fr7                  ; overwrites I: fv4 = (x, y, z, 1)
ftrv xmtrx,fv4             ; -> (w, -, Y, X): matrix rows permuted
fmov @r2+,dr8              ; the same pair again: fr9 = I
cmp/eq #1,r0 ; bf.s ; mov r4,r7 / mov r5,r7   ; PCW E0 or F0
mov.l @r2+,r8 ; add #64,r6 ; mov.l @r2+,r9    ; u, v as raw words (integer pipe)
fdiv fr4,fr12              ; 1/w
pref @r3                   ; prefetch the next source vertex
fschg
; written backwards into the SQ: offset, base, v, u, 1/w, Y/w, X/w, PCW
dt r0 ; bf.s loop ; pref @r6   ; SQ burst in the delay slot
```

Tricks:
- **Overlapping pair loads.** `fmov @r2,dr6` then `fmov @r2+,dr8` read the
  same pair twice, so vectors are built with no moves. In PIT, three pair
  loads and one `fldi1` give fv4 = (x,y,z,1) and fr9 = I; in PNT, four pair
  loads and two `fldi1` give fv4 = (x,y,z,1) and fv8 = (1,nx,ny,nz).
- **UVs on the integer pipe.** U and V are copied as raw 32-bit words with
  `mov.l` and never touch the FPU.
- **Backwards writes.** `@-r6` stores fill the 32-byte vertex from the end, so
  the PCW goes in last and `pref` sends it right away.
- **Not software-pipelined.** Only five instructions separate the FMUL by
  1/w from the FDIV, so each vertex probably stalls about 8 cycles. Estimate:
  30-34 cycles per vertex with cache hits.

### Lighting (PNT family)

- `fipr fv0,fv8` with fv0 = {ambient, Lx, Ly, Lz} and fv8 = (1, nx, ny, nz)
  gives ambient + N.L in one instruction.
- **Specular on the integer pipe.** If the result exceeds 0.5,
  `offset = (bits(d) << 4) + bits(65536.0f)`. Exponent arithmetic on the
  float's bit pattern approximates pow(x, 16). Instructions (near-clip
  kernel): `flds; sts fpul; shll2; shll2; add; lds; fsts`; the no-clip
  kernels use `mov #4; shad` instead. The PN no-clip kernel shifts by 6 with
  the same bias, which gives about 0; its offset word is probably unused
  (untextured).
- Output is intensity mode: base intensity = diffuse, offset intensity =
  specular, with the colour in the header.

### Near-clip strip kernel (0x8c0b0260 and the 0x8c0b0be0-0x8c0b2250 family)

One state machine (apparently macro-generated, partly unrolled), with one
copy per class:
- A ring of the last three clip-space vertices (r6/r7/r8, rotated with four
  `mov` per vertex) lets the kernel emit intersection vertices inside the
  strip without breaking it.
- Visibility test: `fldi1 fr0; fcmp/gt fr0,fr4` (visible if w > 1).
- Intersection: `t = (1 - wa)/(wb - wa)` with one FDIV, then an `fsub + fmac`
  lerp of every attribute. The new point lies exactly on w = 1, so it needs no
  divide (`fldi1 fr4; fldi1 fr5`).
- **1/w from the matrix.** The matrix rows are arranged so one output lane is
  the constant 1: `fdiv fr4,fr5` yields 1/w directly.
- **Deferred SQ flush.** `pref @r9; mov r2,r9; add #64,r2`: the queue holding
  the previous vertex is flushed while the next fills. At the end of a strip
  the PCW is rewritten in place before its burst (`mov.l r11,@r9; pref @r9`,
  0x8c0b137e). The first flush targets the stack (`mov r15,r9`) and is
  harmless.
- About 47 (PIT) to 55-62 (PNT) instructions per unclipped vertex, of which
  up to 27 are memory operations (loads, stores and prefetches, including the
  ring copy).

### Packed-colour clip lerp (PCT, 0x8c15a44e-0x8c15a4ac)

Two channels per register, 8.8 fixed point (full listing in
`listings/pct-argb-lerp.s`):

```
rb  = c & 0x00FF00FF          ; R at bits 16-23, B at 0-7, 8 empty bits above each
g   = c & 0x0000FF00
t8  = ftrc(t * 256)
out = (((A_rb*(256-t8) + B_rb*t8) >> 8) & 0x00FF00FF)
    | (((A_g *(256-t8) + B_g *t8) >> 8) & 0x0000FF00)
```

The weights sum to 256, so each channel stays under 255*256 and never carries
into its neighbour. Four `mul.l` lerp R, G and B together. Observations:
- Alpha is masked out (neither mask covers `0xFF000000`): clipped vertices get
  A = 0. Masking G and A together (`(c >> 8) & 0x00FF00FF`) would keep alpha
  at the same cost.
- Six registers are spilled to the stack around the lerp.
- The offset colour is not lerped. It is a literal in the routine's own
  constant pool that a render-state setter (0x8c0e32fa) writes directly
  (self-modifying data).

### Other kernels

- **PNT_c (0x8c061e00): 16-bit truncated floats.** Each coordinate stores the
  high half of an IEEE float. `mov.w` + `swap.w` puts it in the top 16 bits,
  and a store/load through the stack moves it to an FP register, with no
  int-to-float conversion. That is about 7 bits of mantissa: fine for car
  meshes, too coarse for world positions.
- **Outline effect (`vlxKamuiOutlineEffect`).** Extrudes P += width*N with
  three `fmac` before the FTRV.
- **Car paint (0x8c164960, 0x8c1652c0).** A RAM-to-RAM pre-pass costing about
  135-150 instructions per vertex: V = P - eye; reflection R = V - 2(N.V)N,
  normalised with `fipr` + `fsrra`; a Fresnel-like (1-|N.V|)^2; (R.L)^4 and
  (R.L)^16 by squaring; a sphere map (R*0.5+0.5). XMTRX is reused as a 4x4
  colour-mixing matrix (`ftrv xmtrx,fv0`). RGB is saturated with a
  branch-free trick: `and 0x808080` finds the overflowing channels, then
  shift, subtract and or.
- **SDK-style loops (0x8c0eaace-0x8c0eacde).** Simpler transform loops,
  probably from Sega sample code, linked in but apparently unused (no
  references found): one FTRV per vertex, FDIV overlapped with integer
  loads, SQ output.

### Bugs and oddities

- The PN-family clip kernels (0x8c0b1440, 0x8c0ce880) advance the prefetch
  pointer by 32 bytes on a 24-byte stride, so the prefetch drifts 8 bytes
  further ahead with every vertex of the object. It still touches every line,
  only earlier; how much that costs was not measured.
- Clip and no-clip twins disagree on the offset value: PIT writes 1.0 when
  clipping and 0.0 when not; PN writes 1.0 instead of the specular
  (probably harmless: see Lighting).
- A useless `fmul fr3,fr3` (x3, computing 1.0^8) in the PN outline clip
  kernel (0x8c0ce90c).

## 2. Getting vertices to the PowerVR

- **Configuration.** The game fills the Kamui config itself (builder
  0x8c0614b8, then `kmSetSystemConfiguration` 0x8c226bc0): two framebuffers,
  one pass, opaque as the direct-transfer list, and RAM buffers of 50% each
  for the translucent and punch-through lists. The vertex buffer is addressed
  through P2 (uncached) when a flag is set (0x8c1f7a48, set to 1).
- **Store-queue pattern.** Each draw method takes the current list's write
  pointer (table 0x8c27a940, list = header word0 bits 24-26), sets
  QACR0/1 = ptr >> 24 and writes `(ptr & 0x03ffffff) | 0xE0000000`. The same
  kernels therefore write to the TA FIFO (opaque, presumably pointer
  0x10000000; the table is filled from Kamui at run time) or to RAM (buffered
  lists).
- **Headers.** Pre-built Kamui state blocks (`CreateStateBlock`, 0x8c0e6db8).
  A 32- or 64-byte header (mask `0x1400`) is copied only when the state
  pointer is non-NULL; NULL continues under the current header.
- **DMA.** `kmEndPass` (0x8c227a80) queues each buffered list to the TA via
  DMA ch2 (Kamui code at 0x8c232b4a: SAR2 and DMATCR2, CHCR2 `0x12c1`,
  DMAOR `0x8201`, then SB_C2DSTAT 0xA05F6800, SB_C2DLEN and SB_C2DST
  0xA05F6808).
- **Overlap.** Each frame runs EndPass, kmRender, then kmBeginPass right away,
  so the CPU streams the next frame's opaque list while the PVR draws the
  current one.

## 3. Cache

- CCR is configured once, by Shinobi start-up code (0x8c21e600, probably
  `syCacheInit`), with `0x105` (ICE|OCE|CB) from a variable at 0x8c23c67c.
  The other CCR writes only reset the caches or set the ICI/OCI invalidate
  bits. ORA (OCRAM) and OIX (index mode) are never set.
- The Shinobi OCRAM page allocator and its `movca.l` helper are linked but
  unreferenced.
- `ocbi`/`ocbp`/`ocbwb` appear only in cache-maintenance helpers (Shinobi,
  Kamui and the debug-adapter library), presumably for DMA and I/O buffers;
  none are in the render path.

## 4. Scene, culling and LOD

- **Offline bounding-sphere tree.** `lemans` -> `L_1..L_4` -> nested
  `MultipleMaterialsMesh` nodes up to 10 deep (12 levels below the file
  root), 0-4 children each: a 4-ary tree built by the track tool. Meshes are
  grid tiles (`grid418`, `skin531`) with a median bounding radius of about 16
  (7-49 by layer; units presumably metres).
- **Two spheres per node.** One bounds the subtree (outside: skip the
  children), the other the node's own geometry. `m_optimiseTrackBoundingVolumes`
  (on) presumably recomputes them at load.
- **Frustum test (0x8c060e54; 0x8c060f74 for the own-geometry sphere).** One
  FTRV for the centre, radius scaled by the matrix column length (`fipr` +
  `fsqrt`), six compares. It returns an outside code or a straddle mask.
  A fully inside parent sets a flag (0x8c23de78) that skips tests for its
  whole subtree. Estimated cost: about 105 instructions per test plus about 40
  in its helpers (matrix load into XMTRX, column length), and very roughly
  100 more for the walk, which pushes a 48-byte matrix per node.
- **Near-plane box test (device draw, 0x8c0e4794).** The no-clip or near-clip
  kernel is chosen per object by an object-space box test against w = 1, which
  sets a flag (0x8c27ab80) read by every draw method. Boxes wholly behind the
  near plane are not drawn.
- **No PVS, portals or occlusion found.** `veOcclusionZone` / `veBoxZone`
  appear to be audio zones (they sit with `veSound` and `veReverbZone`).
- **Layers as far-plane multipliers.** `lmTrackLODCullNode::Cull` (0x8c0d2868)
  culls its subtree with far = max(far * k, near + 0.001):

  | Layer | k | k (split-screen) | Meshes |
  |---|---|---|---|
  | L_1, L_2 | 1.0 | 0.5 | 753 |
  | L_3 | 0.55 | 0.275 | 657 |
  | L_4 | 0.23 | 0.115 | 289 |

  Small detail objects live in the short-range layers.
- **Budget controller** (`lmCarLODController`, 0x8c0f0850):
  1. The track's strip vertices are summed from precomputed per-mesh counts
     of the meshes actually drawn (0x8c1be54c).
  2. The cars' budget is 37000 (`m_totalStripVertBudget`) minus that sum.
  3. Cars have 7 distance LODs (7.5-75, presumably metres; computed outside
     the controller) and are bubble-sorted by a per-car float, presumably
     distance.
  4. If over budget, cars step down one level each, farthest first, until
     the total fits, for up to 2 passes (at most 2 levels per frame; the
     second pass steps at least one car even if the first pass fitted). If
     under, cars step back up, at most 1 level per frame.
  5. If still over budget, the farthest cars are dropped from the frame
     until it fits.
  6. The track is never adapted.
- **Instancing.** 848 `~Instance` nodes in per-layer quadtrees
  (`null_inst_<depth>_<quadrant>`) point at shared prototypes.

## 5. Data and load time

- `DATA.ZIP` (3552 entries; the central directory and its end record are at
  the front of the file, so readers that search from the end fail).
  Models are `.VBIN` "FISH" serialized Vertigo scene graphs.
  `LEMANS.VBIN`: 536 SceneNodes, 848 Instances, 1699 VertexSets, 6160
  MeshFaceSets.
- **Track vertices:** float `PositionArray` + baked `IntensityArray` +
  `TextureCoords`. **Cars:** `NormalArray` (lit at runtime).
- **Strips:** u16 `IndexArray`, length-prefixed: 16,162 strips with a mean of
  5.3 vertices (60% are quads), 86K strip vertices, 53.7K triangles.
- **Load conversion** (`vlKamuiGeometrySet` 0x8c0e21f0 -> 0x8c0e8c64): strips
  are de-indexed into a flat u32 index stream per strip vertex plus a byte
  length table. "Soft verts" are strip vertices transformed directly, with no
  vertex cache. The strip optimiser `GenTriStrip_Optimise` exists, but
  `m_optimiseTrack` = 0: the offline tool already stripped the track.
- **Materials:** 9 distinct RenderStateGroups, 115 texture names and 50
  distinct Material blocks for the whole track.
  Submission is in traversal order; no sort pass was found.
- **Mipmaps:** `ELEMENTBEHAVIOUR.TXT` sets a per-texture `MipMapBias`; its
  comments say bias 1 "hinders framerate" and the default 4 is "best
  framerate".

## 6. Frame structure

- `m_executionStrategy` = 1: a fixed 30 Hz simulation step, with rendering
  skipped while the simulation catches up, never more than one frame in a row.
  Strategy 2 renders every pass; 0 renders every second pass with a vblank
  wait (reading less certain).
- A "25Hz" / "30Hz" (50/60 Hz) setting stores 25.0 or 30.0 in a rate field;
  replays are probably recorded at that rate (PAL/NTSC) (not traced).
- On-screen profiler: `CPU= / PVR= / MVT= / DMA=`,
  `Cars (sv %d tri %d) Track (sv %d tri %d)`,
  `SV Limit (Total %d Track %d Car %d)`.

Compiled-in defaults (config ctor 0x8c042d48; `LEMANS.INI` can override,
shipped INI sets only `m_aiCars 23`):

| Setting | Default |
|---|---|
| `m_totalStripVertBudget` | 37000 |
| `m_trackDrawDistance` | 700 |
| `m_numCarLODs` | 7 |
| `m_lodStartDistance` / `m_lodFinishDistance` | 7.5 / 75.0 |
| `m_adaptiveLoddingUp` / `Down` | 1 / 1 |
| `m_maxAdaptiveLODStepUp` / `Down` | 1 / 2 |
| `m_useMergedLODs` | 1 |
| `m_optimiseTrack` / `m_optimiseCars` | 0 / 0 |
| `m_optimiseTrackBoundingVolumes` | 1 |
| `m_executionStrategy` | 1 |

## 7. Comparison: WSB 2K2

| | Test Drive Le Mans | World Series Baseball 2K2 |
|---|---|---|
| Vertex sharing | none: strip vertices re-transformed | indexed pool of at most 256, in OCRAM |
| Passes | 1 (source -> SQ) | 2 (batch transform, strip walk) |
| Source format | 24-32 B floats | 3 B coordinate-palette indices (models), floats (playfield) |
| Per-vertex culling | none (sphere per object) | FIPR-pair back-face test on each strip's leading triangles |
| Per-vertex cost | 30 (prelit) to 44 (lit) instructions | hand-paired 4-deep pipeline |
| Lighting | baked intensity, or 1 FIPR | 3 diffuse + specular per FTRV, intensity mode |
| Near plane | in-strip clipping | none (sentinel 1/z) |
| Cache | default | OCRAM + index mode |

## Method

1. Extract the disc: `tools/gdrom_extract.py game.cue outdir`. The files live
   in data tracks 3 and 5; track 5 starts at LBA 423396.
2. Find the load base by matching 32-bit words against string offsets
   (0x8C010000 here).
3. Disassemble as little-endian (`sh-elf-objdump -D -EL -b binary -m sh4`);
   the default big-endian decode is garbage.
4. Locate hot code by clustering `ftrv`/`fipr`/`pref`/`frchg`/`fschg` and
   literal references to 0xE0000000 (SQ), 0xFF000038/3C (QACR), 0x10000000
   (TA FIFO), 0xFF00001C (CCR), 0x7C000000 (OCRAM) and 0xFFA00020 (DMAC).
5. Name functions from surviving C++ RTTI and vtable strings.
6. `tools/listing.py BIN BASE START [END]` prints a routine.
