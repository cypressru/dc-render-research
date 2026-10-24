# Shenmue II (Dreamcast, 2001): transform and lighting loops

Sega AM2, Japanese disc 1. Libraries: Kamui 1.11 (Sep 2000), Shinobi-era
syCache/sySq, CRI ADX/SJ, libsnd 1.05e. Main executable `1ST_READ.BIN`
(3.1 MB, load base `0x8C010000`):

| Range | Contents |
|---|---|
| 0x8c039000-0x8c03c800 | hand-written asm: sea renderer, particle/billboard kernels, light culling |
| 0x8c04a000-0x8c054000 | character joint/skin passes, hand skinning (asm) |
| 0x8c054000-0x8c1d3000 | compiled C game code |
| 0x8c1d3600-0x8c1df200 | hand-written asm: the MT7 model renderer, shadow volumes, matrix library |
| 0x8c206000-0x8c21b000 | Kamui 1.11 |
| from about 0x8c220000 | data |

Everything here comes from static analysis of the disassembly plus a scan of
the MT7/MT6 files on the disc. Nothing was run or measured. Cycle figures are
estimates from instruction counts with the usual SH4 latencies (FTRV 1/cycle
issue and 4-5 cycles latency, FDIV about 12 cycles latency, LS group single
issue). Annotated loops are in `listings/tnl-loops.s` (sections A-F are named
below).

## Summary

1. **One model renderer draws almost everything.** "Renderer B"
   (0x8c1d7480 mesh walker, called through 0x8c1d6880 / 0x8c1d6980 /
   0x8c1d71e0 / 0x8c1d72a0) draws:
   - map and area geometry (the map module at 0x8c11a000-0x8c11e000)
   - characters and NPCs (task MTWK -> 0x8c0d9fc0)
   - props and items
   - the sky dome (MOON / DOM0 / AIR0 code at 0x8c05647c)

   Only the sea has its own renderer (renderer A, 0x8c039b40,
   `MISC/TRSEA4.MT6`).
2. **The MT7 data is the vertex stream, as stored.** The kernels read it
   straight from the file:
   - An inline vertex is 32 B `{x,y,z,nx,ny,nz,u,v}` floats. **The LSB of x is
     forced to 1 in the data and serves as the tag.**
   - Any other 8 B entry `{even word, s32 offset}` is a back-reference to an
     earlier inline copy.

   Strips are de-indexed with dictionary-style back-references, and every
   strip vertex is re-transformed: there is no vertex pool, and no load-time
   conversion exists.
3. **Lighting is runtime and per vertex, mostly in intensity mode.**
   - The light is rotated into model space once per mesh, so the normal is
     never transformed. One FIPR per vertex gives `ambient + max(0, N.L)`.
   - Output is TA vertex type 7 (textured intensity), with the colour from the
     header (material colour x light colour).
   - Even the map is lit this way: 55,405 of the 60,613 meshes in the map
     entries of all packs are mesh type 0 with unit normals, not prelit.
   - A second path does RGB with multiple point and spot lights (64 B floating
     colour vertices).
   - Minor paths: specular through a lookup table, bump mapping (type -2), and
     packed vertex colour (type -3).
4. **The bulk kernel: 0x8c1d79b2.**
   - About 40 instructions per vertex: 1 FTRV, 1 FIPR, 1 FDIV.
   - **Two vertices per loop trip, software-pipelined** so that the FDIV of
     vertex n is consumed about 20 instructions later, after vertex n+1 has
     been loaded and transformed. That hides the divide.
   - Estimate **about 30-35 cycles per strip vertex** lit (type 0) and about
     25-30 cycles unlit (0x8c1d7890, type -1).
   - That is the same cost per strip vertex as Le Mans's prelit kernel, but it
     also lights each vertex. Soulcalibur's strip emit is cheaper per strip
     vertex (about 20 cycles) but it first pays about 70 per unique vertex.
     Shenmue loses vertex sharing, which Soulcalibur has.
5. **Store-queue tricks, with no constants:**
   - **The PCW is a store-queue address** (the previous vertex's, held in r2;
     0xE0xxxxxx parses as a vertex parameter).
   - **End of strip = `shar` of that address** (0xF0xxxxxx).
   - With FPSCR.SZ=1 for the whole kernel, each 32 B vertex is written
     backwards with four 64-bit pair stores. The matrix rows are permuted so
     FTRV yields `(w, X, Y, -)`: the pair `(w, X/w)` lands at +0, and the PCW
     `mov.l` then overwrites w.
   - No word stays constant in the queues: each pair store rewrites all eight
     words, including offset intensity 0. (The shadow kernel does leave its PCW
     in the queue, since its 64 B records always land on the same SQ halves.)
6. **Skinning is rigid per bone plus CPU joint patching.**
   - A character is a node tree with one rigid mesh per bone, each drawn with
     its own matrix through the normal kernels. There is no per-vertex matrix
     palette in T&L.
   - Before a child mesh is drawn, its joint vertices are rewritten in place in
     the MT7 stream (with x LSB re-forced to 1):
     - seam copy from the parent (2 FTRV, about 17-20 cycles per seam vertex)
     - for near characters, a two-bone weighted seam (blended matrix, about
       35-40 cycles per vertex)
     - multi-bone "WBTR" envelopes (about 35-40 cycles per influence)
     - a dedicated hand-skinning pass (`HMT_HandCalcSkin`)
   - **NPC/crowd LOD:** characters beyond a distance threshold skip the
     weighted passes and keep only the seam copy. There is no separate cheap
     kernel.
7. **Culling and clipping.**
   - Per mesh: a bounding sphere with 1 FTRV, near/far, and 4 side planes as
     multiplies by tangent constants. Back faces are culled by the PVR: the
     ISP cull mode comes from the strip flags and is flipped for mirrored
     matrices.
   - Meshes whose sphere straddles the near plane go to clip twins that **clip
     inside the strip**, as Le Mans does:
     - a 3-bit in/out history and a `braf` state machine
     - one FDIV per intersection
     - 1/w of the new vertex is the constant 1/w_near
   - **Visibility is an integer `cmp/hi` on the raw float bits of w**, against
     the near-plane w held as bits in a register.
8. **1/w is always FDIV.** FSRRA (44 in the binary) appears only in
   normalisation and light falloff. FDIV latency is hidden by pipelining in the
   main renderer, but not in the sea renderer or the particle kernels.
9. **No OCRAM, no `movca.l` in vertex code.** CCR is only ever 0x808, 0x105
   or 0, and the Shinobi OCRAM allocator is linked but unreferenced.

## 1. Frame-level entry points

| Entry | Callers | Role |
|---|---|---|
| 0x8c1d6880 | 25 sites | draw MT7 model, intensity path (-> 0x8c1d7120 -> table 0x8c1ddeb0 -> walker 0x8c1d7480) |
| 0x8c1d6980 | 15 | same with alpha in fr4 (walker 0x8c1d7482). If alpha < 1, the TSP blend is rewritten and the translucent list is used |
| 0x8c1d71e0 / 0x8c1d72a0 | 8 / 3 | RGB multi-light path (walker 0x8c1dad40 or twin 0x8c1dbf20) |
| 0x8c1d6600 | 4 NL wrappers (0x8c1d6500-0x8c1d65c0) | shadow modifier volume of a model (0x8c1dd220) |
| 0x8c1d6cc0(n) | 17 | selects the hook for mesh type -3: 0 none, 1 = 0x8c1d442a, 2 = 0x8c1d500a |
| 0x8c03bf40 | 6 | sphere-map UV pre-pass, run before a model draw when model flag &4 is set |
| 0x8c039b40 | 0x8c090fe0 only | sea |
| 0x8c03a260 | 0x8c1c7800 | particle/effect slots |

- **Path choice.** The map module (0x8c11bb5c-0x8c11bb7c) and the character
  draw (0x8c0d9088) store the draw function pointer (0x8c2e9fcc, 0x8c293c78).
  They pick the intensity path when light[0] (0xb0-byte records at 0x8c30c75c)
  is a plain directional and no local lights are active, and the RGB path
  otherwise. This reading is uncertain.
- **Matrices.** XMTRX = projection x view x model with the viewport folded in
  and the rows permuted, built by the matrix library (section 7) and
  0x8c1e74a0.

## 2. The MT7 model renderer (renderer B), listing sections A and B

### Data format

- **Mesh header** (0x50 B before the stream): PCW, ISP, TSP and TEX template
  words; a bounding sphere at +16/+28; the mesh type byte at stream-44;
  material colours at stream-40..-8; byte size at stream-4.
- **Mesh type byte:** 0 = diffuse lit, >0 = lit plus specular table
  (r8 = 0x8c303d34 + n<<9), -1 = unlit (ambient forced to 1.0), -2 = bump,
  -3 = packed vertex colour.
- **Strip command word:**
  - bits 0-1: ISP cull mode (to bits 27-28, XOR 1 when the matrix is mirrored)
  - bit 3: triangle list
  - bit 4: strip
  - bit 6: Gouraud
  - bit 7: another strip follows under the same header
  - a word <= 0 ends the stream

  The word is followed by `u32 count` and the entries.
- **Disc census** (mesh type byte of every mesh: map entries of every PKS in
  `SCENE/01`, and every model in the loose MT7 files; duplicates across packs
  counted, distinct by content in parentheses):

| Type | Packs (maps) | Loose MT7 |
|---|---|---|
| 0 | 55,405 (39,048), unit normals | 3,790 (3,235) |
| >0 | 697 (432) | 994 (959) |
| -1 | 4,364 (3,065) | 326 (300) |
| -2 | 0 | 3 (1) |
| -3 | 147 (94) | 37 (28) |

### Walker 0x8c1d7480

For each mesh:

1. FTRV the sphere centre, then test near/far and 4 sides against tangent
   constants (0x8c2658c8/cc). Reject the mesh, or set r12 bit 0 if it
   straddles the near plane.
2. Write a 64 B mesh header. The face colour is material x light colour
   (0x8c2656c8).
3. Write a 16 B header per strip group. QACR0/1 is reloaded only when the list
   changes. Lists come from Kamui's table `*(0x8c317e44)`: r5 is the RAM
   pointer, r6 = `0xE0000000 | (p & 0x03ffffff)`.
4. Branch on the mesh type to the kernel.

### Kernels

| Kernel | Use | Per vertex |
|---|---|---|
| **0x8c1d79b2** (section A) | type 0, strips, no clip: `I = ambient + max(0, N.L)` | about 40 instructions (79 per 2-vertex trip on the back-reference path, +3 inline), 1 FTRV + 1 FIPR + 1 FDIV, about 2 branches; **about 30-35 cycles** |
| 0x8c1d7890 | type -1 (I = 1.0), strips | 28 back-reference / 31 inline; about 25-30 cycles |
| 0x8c1d7b06 | type >0: second FIPR N.H, `ftrc` index into a per-material table, offset intensity = table[idx] above 309 | about 48-52 |
| 0x8c1d8280 | triangle-list twins of the above | similar |
| 0x8c1d7be0 / 0x8c1d8080 | near-clip strips/triangles; per-vertex classifier 0x8c1d7e60, 4-slot ring at 0x8c2bdaa0, intersection 0x8c1d7fe0 | about 50-60 |
| 0x8c1d85c0 | twin walker with a second directional light: one `jsr` per vertex to 0x8c1d8904 | +22 |
| 0x8c1d9760 | type -2: 56 B sequential vertices {P, N, T, B, u, v}; 3 FIPR, FSQRT, FDIV, atan byte table; packs the PVR bump-map angles into the offset colour | about 113 |
| 0x8c1da1e0 | type -3 default: s8 normals plus ARGB, 64 B floating-colour output | 66 unlit, about 104 lit |
| **0x8c1d4620** (section B) | type -3 through hook mode 1/2: packed base (and offset) ARGB from the vertex, type 3 output | 30 back-reference / 33 inline; about 20-24 cycles; type -3 meshes are rare (184 on disc) |
| 0x8c1d4840 | clip twin of 4620; culled runs take a depth-only FIPR fast path | 35.5-38.5 visible, 23-27 culled |
| 0x8c1db160 / 0x8c1db4a0 | RGB walker 0x8c1dad40, strips/triangles | about 80 instructions with 1 directional, about +25 per extra directional, about +45-60 per point/spot; about 70-80+ cycles |

Section A shows the bulk loop. The steady-state body interleaves the two
vertices like this:

- `fdiv` for A, then the `fipr` for A in a branch delay slot
- pair loads of B
- `fmul` X and Y of A by 1/w (ready by then)
- `ftrv` of B issued between A's stores
- the PCW `mov.l` overwrites the junk w word
- `pref @r6` flushes the SQ
- `pref @r4` prefetches the source 32 B ahead

### Lighting details

- **Directional (intensity path).** The light is rotated into model space per
  mesh. The normal loads permuted as `(ny, nz, nx, 0)`, because the pair loads
  are `(x,y)(z,nx)(ny,nz)`, so the light vector is stored permuted too.
  Ambient travels through FPUL to save a register.
- **RGB path.**
  - Per-mesh light culling (0x8c03c080 and its copy 0x8c03c3c0) walks up to
    32 lights (types 2 directional, 3 point, 4 spot). Point lights use a
    sphere-sphere test, spot lights a cone test with FSRRA/FSQRT. The result is
    a bitmask (0x8c03c3b0).
  - Per vertex and per active light:
    - Directional: 1 FIPR.
    - Point: `L = Lp - P`; FIPR N.L and FIPR L.L; a range test; FSRRA for 1/d;
      falloff `min(1, k*(1/d)^8)` by squaring three times.
  - Colour is accumulated with 3 `fmac` into fr13-15, initialised to ambient.
  - Output is a 64 B type-5 vertex, twice the TA bandwidth of the intensity
    path.
- **Specular / power table.** 0x8c1d66e0 builds a 32x128 float table at
  0x8c304208. The positive-type table at 0x8c303d34 is indexed by `ftrc(N.H*k)`.

### Why 685 FSCHG

Most vertex loops contain none: SZ stays 1 for a whole kernel (pair loads and
stores). Exceptions toggle SZ inside the loop: the specular kernel 0x8c1d7b06
(twice per vertex above the table threshold, for its 32-bit table load), the
shadow kernel 0x8c1dd420 (twice per strip vertex), the hook kernel 0x8c1d442a
and the sea clip loop. The bulk of the count comes from three sources:

- **Wrappers.** Every kernel, walker header write and clip helper toggles SZ
  twice. The kernel families also exist in several copies: hook mode 1 and
  mode 2 twins, intensity, RGB and RGB-twin walkers, each in strip, triangle
  and clip forms.
- **XMTRX save/restore.** The idiom `fschg; 8 x fmov xdN,@-rM; fschg` is
  10 instructions. Particle kernels use it once per particle, because each
  particle runs a C callback that may clobber XMTRX.
- **Matrix library.** It loads matrices straight into XD0-XD14 with 8 pair
  moves, with no FRCHG and no 16 single loads (section 7).

FRCHG (106) is mostly the library's multiply.

## 3. Characters: skinning (section C)

**Call chain.**
- Task MTWK (0x8c0f6840, frame function 0x8c0f6d80) -> 0x8c0d9fc0, which picks
  the draw function (intensity or RGB, alpha or opaque).
- -> tree walkers: 0x8c0d9140 (plain, recursive; mesh at node+40, child at +44,
  sibling at +48, motion matrix at +56), 0x8c0da580 and 0x8c0da100 (motion
  driven).
- -> mesh walker 0x8c1d7480.

**The rigid draw cannot tell a mesh was skinned.** Each pass writes
`{x,y,z,nx,ny,nz}` into the child mesh's own stream records and ORs 1 into x,
because a computed float has a random LSB and the bit is the tag.

| Pass | When | Method | Cost |
|---|---|---|---|
| Seam copy 0x8c0501a0, loop 0x8c0502fa | always (unless the global 0x8c24906c is set) | parent-to-child matrix = rigid inverse of the node (0x8c1de7d0) x parent with translations subtracted first (keeps floats small). `{srcOff, dstOff}` pairs; 2 FTRV per vertex (w=1, w=0); two vertices in flight; 12 explicit `nop` pairing fillers | 54 instructions + 12 nops per 2 vertices, **about 17-20 cycles per seam vertex** |
| Weighted seam 0x8c0503dc | only if 0x8c252e3c = 1 (near character) | records `{dst, w, P, N}` sorted by weight. Blended matrix `(1-w)M_rel + w M_node` (16 `fmac`), rebuilt only when w changes (`fcmp/eq`) and loaded into XMTRX by 8 pair moves. This is linear blend skinning for 2 bones. Normal renormalised by FIPR + FSRRA | 33 instructions, about 35-40 cycles; about 120 instructions per weight change |
| WBTR envelopes, C driver 0x8c0daf00 + kernel 0x8c0504fc | MDP7/WBTR chunks present | zeroes 48 B work vertices, then per bone adds `w*M*p` and `w*M*n` (6 `fmac`) over `{index, weight}` lists | about 39 instructions per influence, about 35-40 cycles |
| HMT_HandCalcSkin 0x8c052860 | hands | Hermite-interpolated finger poses (0x8c0b0200); FSCA Euler matrices; bone palette at `*0x8c2e479c` = current x node+32 (probably inverse bind). Each bone matrix goes into XMTRX with 8 `fschg` pair loads. Influence loop 0x8c052916, 2 FTRV, 2-stage pipelined. Then a 4x unrolled FIPR + FSRRA renormalise (17 instructions per vertex) and a scatter into the hand mesh stream | about 26-30 cycles per influence |

**Crowd LOD.** At 0x8c0f6dd4-0x8c0f6e0a, the character position is transformed
and compared with the distance at 0x8c253bb0 and with view-space z. Only near
characters that are in front set 0x8c252e3c, enabling the weighted passes. Far
characters and crowds are rigid limbs plus seam copies. There is no separate
NPC kernel; whether the NPC manager swaps meshes was not established.

**Comparison.**
- Soulcalibur skins with pre-multiplied partial vertices per bone into a
  shared pool.
- Shenmue II keeps the rigid MT7 meshes and patches only the joint vertices.
  This is cheap for a game with dozens of characters on screen, because the
  vertices that never change cost no skinning at all.

## 4. Shadows (section D)

**Model shadow modifier volumes.**
- **Header.** Wrapper 0x8c1d6600: PCW `0x818c0000 | (flags & 0x30000)`, list 1
  (opaque modifier volume).
- **Driver 0x8c1dd298.** Sphere test as in the walker, then the open and close
  volume headers (ISP | 0x40 on the last one).
- **Input.** The same MT7 strip stream, reading only xyz with pair loads; w = 1
  comes from `float fpul` with fpul = 1.
- **Output.** Each strip vertex emits one 64 B TA modifier-volume triangle
  `{PCW, A, B, C}`:
  - The PCW is `shar` of the SQ address.
  - Parity alternates the new vertex between slots A and C, to keep the
    winding.
  - The newest vertex is pre-copied into the next record.
- **Variants and cost.**
  - No-clip 0x8c1dd420 / 0x8c1dd540 (by flag parity); clip twins
    0x8c1dd640 / 0x8c1dd9a0 (helpers 0x8c1ddc80+, FDIV `t`, `fmac` lerp,
    1/w = 1/near).
  - About 43-46 instructions per triangle (two `fschg` among them), 1 FTRV,
    1 FDIV with about 6 cycles of stall, so about 35-45 cycles.
  - No CPU back-face culling (unlike Soulcalibur's front-face-only volumes).
- **Uncertain:** whether the source mesh is the character itself or a separate
  shadow mesh. The shadow matrix setup was not traced.

**C-code volumes (0x8c0ff0a4-0x8c1000a0).**
- A box/prism modifier-volume builder over a u16-indexed projected-point pool.
- Near-plane cases are handled by an 8-way switch.
- Emitters 0x8c0ffe60, 0x8c0fff40 and 0x8c0fff80 write 1, 2 or 3 64 B
  triangles by SQ.
- Purpose uncertain: object drop shadows or light volumes.

## 5. Sea (renderer A, section E)

- **Caller.** Only 0x8c090fe0, which draws the TRSEA4.MT6 tile N+1 times with
  a translation step. Before each tile, 0x8c091da0/0x8c091c80 patch the
  stream's op and header in place (animated textures `SIRANAMI.PVR`,
  `SHIBU.PVR`).
- **GBR = 0x8c2bdb80** (render context). Bank-1 registers are used as globals:
  r3_bank holds the result slot, r7_bank the UV-scale bits.
- **Stream.** MT6 "HRCM", read as stored:
  - Op word: low byte is the op, negative ends.
  - Ops 0-5: 4 header words, then strips of 36 B inline vertices
    `{xyz, nxyz, s16 v, s16 u, base ARGB, offset ARGB}` (x LSB = tag) or 4 B
    back-references.
  - Ops 6 and 7 set colours and the UV scale (default 1/256).
  - Colour is prebaked; normals are skipped.
- **Mesh cull.** FTRV of the centre. Each of the 4 side planes is one FSCHG
  pair load plus one FIPR. Straddling near selects the clip table 0x8c039d10;
  otherwise table 0x8c039d30.
- **No-clip kernel 0x8c0390b8.**
  - 39 instructions inline, 41 per back-reference.
  - 1 FTRV, 1 FDIV (used 10 instructions later, about 4-6 cycles of stall),
    2 `float` for the UVs.
  - No pipelining and no source prefetch. Type 3 output, PCW = SQ address,
    end of strip = r5 = -1.
  - About 30-35 cycles per vertex.
- **Clip kernel (loop 0x8c039246-0x8c0393f8).**
  - A 3-vertex window in fv4/fv8/fv12, shifted by 4 pair moves.
  - Outcode = one unsigned `cmp/hi` on the bits of 1/w, which catches both
    w < near and w < 0.
  - 6 case handlers through table 0x8c0395f4. Intersection at
    0x8c039800/0x8c039880: 5 FDIV per new vertex; colours lerped two channels
    per register (`0x00ff00ff` mask, `mul.l`).
  - About 83 instructions, about 60-70 cycles per vertex.

## 6. Effects (section F)

**Particle and billboard system.**
- **Driver 0x8c03a260.** It walks 16 slots of 104 B at 0x8c3015b8 (tag
  "EFCT").
- **List pointers live in r1_bank/r2_bank** for the whole pass. QACR is
  hard-coded per list: 0x10, i.e. the SQ writes go to the TA FIFO directly,
  for list +0; 0x0C (a RAM buffer) for list +8. List 0 is Kamui's
  direct-transfer list (set by NL at 0x8C1E2020, see `notes-system.md`).
- **Kernels** come from table 0x8c03a4c0 (flag bits 29..27) and the
  no-callback twins in 0x8c03a4e0:

| Kernel | Output | Cost |
|---|---|---|
| 0x8c03ad00 / 0x8c03ada0 | TA sprite (64 B, PCW -1); size x 1/w; cull only w <= 0 | 63 instructions, 1 FTRV, 1 FDIV (about 8 cycles of stall), about 45-50 cycles plus the callback |
| 0x8c03aa30 family (aa00, ae40, a700, b0a0) | world-space rotated quad, 1-2 FSCA angles, 4-vertex strip (packed colour or float UV); dropped whole if any corner has w <= 0 | XMTRX rebuilt per particle (view-space centre written straight into the translation column with SZ=1 back-bank moves, full multiply through the matrix library): about 11 FTRV, 4 FDIV, about 285 instructions, **about 250-300 cycles per particle** |

- **Fused update and draw.** Each element's C callback is called inside the
  draw loop. The common callback 0x8c03a040 is an LCG giving gaussian-ish
  jitter. XMTRX is restored after each one with the 10-instruction pair-move
  idiom.

**Sphere-map UV pre-pass, 0x8c03bf40.**
- It rewrites u, v in the MT7 stream in place: `u = 0.5 + 0.5 n'x`,
  `v = 0.5 + 0.5 n'y`, with XMTRX = the view rotation.
- It skips back-references and keeps the old LSB of v (purpose unknown).
- 31 instructions per vertex, or 38 with s8 normals. Then the normal draw runs.
- It is the only reflection/env effect found: chrome and shiny props use it.

**Other.**
- 0x8c1de5d0: a batch projector **software-pipelined three deep** (FTRV n+1,
  FDIV n, scale/store n-1, unrolled x3), about 13 instructions per vertex.
  Caller uncertain.
- 0x8c1de1fc / 0x8c1de320: vertex-light pool callbacks installed in gbr+16/+20
  (24 B in, 16 B out with float intensity; the second does up to 16 lights).
- 0x8c1c6620: a C billboard writing into the translucent list buffer with
  plain stores.
- Kamui `kmSetVertex` (0x8c20baa0) is used only by debug line/polygon helpers.
- 2D/UI and debug text (0x8c1e3fe0) are SQ writers and excluded here.
- The many FDIV-only "loops" in 0x8c060000-0x8c1d0000 are compiled game logic.
  The fsca loops at 0x8c1c6ba0 and 0x8c1cba54 build twiddle tables (audio or
  movie decoder).
- **Not found:** a dedicated water-surface wave, mirror or reflection pass. The
  CLTH (cloth, 0x8c0746bc) and LENS (0x8c0c31e8) chunk users were located but
  not analysed.

## 7. Matrix library (0x8c1de000-0x8c1df200)

| Routine | Literal loads | What it does |
|---|---|---|
| 0x8c1de790 / 0x8c1de7b0 | 245 / 70 | transform a point (w=1) / a direction (w=0) |
| 0x8c1de8f0 | 111 | get the translation |
| 0x8c1de9d0 (also 0x8c1dea10, 0x8c1dea40) | 88 + 7 + 6 | multiply: 4 FTRV over the new matrix's columns, then FRCHG, so the product becomes XMTRX with no store |
| 0x8c1deb40 / 0x8c1deaf0 | 389 / 575 | push (frchg + fschg + 8 pair stores) / pop (8 pair loads straight into XD). Stack at 0x8c30d470 |
| 0x8c1decd0 and siblings | 134+ | rotations: FSCA, 2 FTRV for the two non-trivial columns, then 4 SZ=1 `fmov DRn,XDm` moves straight into XMTRX. No FRCHG, no memory |
| 0x8c1de7d0 | | rigid inverse (FIPR rows, FSRRA renormalise); used to bring lights and seams into object space |
| 0x8c1e74a0 -> 0x8c1e75e0 | | projection x current |

## 8. Output path and cache

- Every kernel writes Kamui's per-list buffers directly through the store
  queues. The table is `*(0x8c317e44)` +0/+4/+8/+16. QACR is set to
  `ptr >> 24` when the list changes, and pointers are written back on exit. No
  `kmSetVertex` call is made in any vertex path.
- Kamui's end-of-pass DMA is at 0x8c214a40-0x8c215090 (channel 2,
  SB_C2DSTAT 0xa05f6800). The game's own DMA init is at 0x8c1e14a0.
- The particle driver's QACR = 0x10 for list 0 matches the opaque list being
  in direct TA mode, which the Kamui config confirms (`notes-system.md`).
- CCR: 0x808 at boot, then 0x105 (0 only while caches are off around overlay
  loads and mode changes). ORA (OCRAM) is never set. Shinobi's
  0x7c000000 allocator and `movca.l` helper are unreferenced. The 20 `movca.l`
  in the binary are library code or data.

## 9. Where the time goes

**Most vertices: the walker 0x8c1d7480 with kernel 0x8c1d79b2** (type 0,
diffuse intensity, no clip). Estimate about 30-35 cycles per strip vertex.
- Map/area meshes and characters both take this path when only directional
  light is active.
- Unlit meshes (type -1) take 0x8c1d7890 at about 25-30 cycles.
- Meshes crossing the near plane cost about 50-60 cycles per vertex.

**Areas with point or spot lights** switch to the RGB walker. That costs about
70-80 cycles or more per vertex, and twice the TA vertex size: likely the most
expensive common case (night scenes, interiors; uncertain).

**Characters add:**
- about 17-20 cycles per seam vertex
- 35-40 per weighted vertex or influence, near characters only
- the hand passes

Particles cost about 250-300 cycles each for rotated quads, but there are few.

Compared with the references:

| | Shenmue II | Le Mans | Soulcalibur |
|---|---|---|---|
| Vertex sharing | none (back-references in data, re-transform) | none | pool (16 B entries) |
| Bulk kernel | 40 instructions, lit, 2-vertex pipelined, about 30-35 cycles | 30 instructions, prelit, about 30-34 cycles | about 88 instructions per unique vertex plus 30 per strip vertex (stage) |
| Lighting | runtime, intensity, 1 FIPR (RGB multi-light path) | baked intensity / 1 FIPR | 2 FTRV, 4 lights, packed ARGB |
| 1/w | FDIV, hidden by pipelining | FDIV, about 8-cycle stall | FDIV, about 9-cycle stall |
| Near plane | in-strip clip twins | in-strip clip twins | +Inf multiply / C triangle clip on some stages |
| PCW | the previous vertex's SQ address, `shar` for end of strip | register constants | kept in the SQ by most emitters |
| Skinning | rigid limbs plus CPU joint patching in place | n/a | partial-vertex accumulation |

## Uncertainties

- The intensity-versus-RGB path selection rule (light record types at
  0x8c30c75c) is a reading of 0x8c0d9088 and 0x8c11bb5c, not confirmed.
- The header intensity modes (mode 1 then mode 2 in the 16 B strip-group
  header) are not confirmed.
- The specular table base and index scale are not confirmed.
- The k/d^8 point-light falloff constant is not confirmed.
- The bump-map reading of type -2 is not confirmed.
- What the 0x8c11e060 per-area field means (hook mode 2 keeps the offset
  colour).
- That node+32 is the inverse bind pose; the WBTR record layout beyond
  `{index, weight}`.
- The exact crowd-LOD test at 0x8c0f6df0.
- The shadow-volume source mesh and matrix.
- The sea grid size (literal 121 suggests 11x11) and op 6.
- Callers of the 3-deep batch projector 0x8c1de5d0.
- All cycle numbers assume cache hits; the strip-to-unique-vertex ratio of the
  MT7 data was not measured.
