# Dead or Alive 2 (Dreamcast, 2000): transform and lighting loops

Team Ninja / Tecmo, USA disc. Main executable `1ST_READ.BIN` (1.8 MB, load base
`0x8C010000`, ends at `0x8C1CB538`). Libraries, from their version strings:

- `NAOMI LIBRARY Ver 0.9 AM R&D`, `NLOBJPUT Ver 0.99`, `NLSPRITE Ver 0.2` /
  `libspr 0.2` (Dec 1999): Sega AM2's render layer over Kamui.
- Kamui2 16,3,2,0 (Jul 1999), Shinobi 1.62, syCache 1.52, ADXT 5.66 / ADXF 5.53.

Everything here comes from static analysis. Nothing was measured, so cycle figures
are estimates from instruction counts and SH4 latencies (FTRV 1/cycle issue, 4-5
cycles latency; FDIV about 12 cycles latency). Labels: [C] confirmed in code or
data, [P] probable, [?] guess. Annotated loops are in `listings/tnl-loops.s`.

## Summary

1. **The renderer is AM2's NL library, the same code that Shenmue II ships.**
   DOA2 started as a NAOMI arcade game, and the Dreamcast port keeps NL as its
   whole 3D layer. The walkers and vertex kernels match Shenmue II instruction
   for instruction (table in section 1). Shenmue II's analysis therefore applies
   to the kernels themselves, and this note covers what DOA2 does around them.
2. **The game code has no vector FP at all.** There is no FTRV, FSRRA or FSCA in
   `0x8C010000-0x8C0F8000`, and only one FIPR (a vector length at 0x8C0C696A). All
   242 FTRV are in the library region `0x8C0FCD90-0x8C113300`.
3. **Bulk path [C].** The intensity walker 0x8C101540 drives four kernels:
   - type 0 (diffuse), 0x8C101A52: about 40 instructions, 30-35 cycles per strip
     vertex, two vertices per loop trip, the FDIV hidden;
   - type > 0 (specular table): about 40-45 cycles;
   - type -1 (unlit): about 25-30 cycles;
   - type -3 (packed vertex colour), fast path 0x8C10A7E0: about 20-24 cycles.

   The game reaches all of them through four draw functions, 0x8C111560/80 and
   0x8C111680/A0, which have about 710 call sites.
4. **Characters are rigid limbs.** Most `*.CHR` costumes hold 42-59 MT7 models
   (40 of 42; WBA00 has 29, YTI00 1), 8.9k triangles on average. There are no weights, no matrix palette and no CPU
   skinning loop. Soft parts move by writing vertex positions into the mesh in
   place:
   - a particle-chain system (hair, ribbons and cloth, data in `*_A0n.ACS`)
     writes simulated points into vertex records (0x8C0C5996);
   - blend helpers for per-vertex keyframes (`*.APV`) do the same (0x8C0CF8FA).
5. **Stage point lights are baked into the mesh every frame.** A DOA2-only NL pass
   (0x8C10D360) lights each unique vertex with directional, point and spot lights.
   It writes packed base and offset ARGB into the vertex record, and the light
   above 1.0 spills into the offset colour. It then retypes the mesh to -3, so
   the transform uses the cheapest kernel. A second pass (0x8C104290) undoes the
   conversion.
6. **A DOA2-only twin of the bulk kernel** (0x8C108372) adds an offset intensity
   `k*(I - b)` driven by the diffuse term. It costs about 6 instructions more per
   vertex.
7. **Character shadows are modifier volumes per limb.** A unit volume model is
   sheared between two joints along the light direction (0x8C0D43E8) and drawn
   by the NL volume kernels. Stage meshes carry the PCW "shadow" bit and
   characters do not.
8. **The only reflection effect is a sphere-map UV pre-pass** (0x8C112560), as in
   Shenmue II. The game draws no mirrors. One module renders to a texture
   (purpose unknown, see notes-system).
9. **OCRAM is refuted.** CCR is 0x105, with no ORA bit. There is exactly one
   `0x7C000000` literal (Shinobi's allocator, never called) and no `movca.l`,
   `ocbi` or `ocbp` in any vertex loop. Raw byte-substring counts of these
   constants (66/174/296) are mostly data. The real literal counts are 1
   (`0x7C000000`), 13 (`0xE0000000`) and 15 (`0x10000000`, four of which are
   SR.BL masks).
10. **Frame skip by self-modifying code.** When a frame is late, the game
    overwrites the first word of eleven draw entry points with `rts; nop`, so the
    next logic pass draws nothing. It writes the cache line back with `ocbwb` and
    sets CCR.ICI from P2.

## 1. Where the code is

| Range | Contents |
|---|---|
| 0x8C010000-0x8C0F8000 | game code (SHC-compiled C), scalar FP only |
| 0x8C0F8000-0x8C0FCD00 | NL system, sprite and debug-text helpers, random (0x8C0FB090) |
| 0x8C0FCD00-0x8C0FEA80 | NL matrix library (= Shenmue II 0x8C1DE000-0x8C1DF200) |
| 0x8C0FEA80-0x8C101540 | NLSPRITE 2D sprites (0x8C100430, 0x8C100890) and the modifier-volume entries 0x8C101430-0x8C1014A0 |
| 0x8C101540-0x8C10E5C0 | NL walkers and vertex kernels; 0x8C104400-0x8C107C80 in between holds NL system/sound glue and SHC integer runtime (0x8C107370 is the divide) |
| 0x8C10E5C0-0x8C110E00 | SHC runtime (struct copy, strings, more) |
| 0x8C110EA0-0x8C1132C0 | second NL math/object layer: FSCA wrappers, rotations, the draw API, light culling, sphere map. Partly shared with Shenmue II (the draw tail 0x8C1116C2 = SM2 0x8C1DDE70; the vertex-pool callbacks), partly absent there |
| 0x8C113300-0x8C13F000 | Kamui2, Shinobi, CRI ADX/SJ |
| 0x8C13F000- | data (strings, tables); every `movca.l`/`ocbi` beyond this point is data decoded as code |

**Identity with Shenmue II.** Both binaries were disassembled, then addresses and
literals were normalised and the instruction sequences aligned:

| DOA2 | Shenmue II | Equal instructions | Role |
|---|---|---|---|
| 0x8C101540 walker | 0x8C1D7480 | 1081/1120 | the differences are literal pools plus Shenmue II's extra second-light hook to 0x8C1D85C0 |
| 0x8C101A52 bulk kernel | 0x8C1D79B2 | 151/151 | type 0 intensity strip kernel |
| 0x8C101CA2 near-clip strip machine | 0x8C1D7C02 | 431/431 | |
| 0x8C102660 RGB walker + 0x8C102A80 kernels | 0x8C1DAD40 / 0x8C1DB160 | 398/400, 1218/1280 | not reachable from DOA2 game code [P] |
| 0x8C10A5EA..0x8C10B1C0 type -3 hooks and fast kernel | 0x8C1D442A.. | 1364/1376 | |
| 0x8C10D980 shadow volumes | 0x8C1DD220 | 1559/1568 | |
| 0x8C107D10 3-deep batch projector | 0x8C1DE5D0 | 152/152 | no caller found in either game |

NL state lives in a GBR block at `0x8C2F4E00` (set at 0x8C0F8E66). Shenmue II's
block is at `0x8C2BDB80`. NL's Kamui list-pointer table is `*0x8C2B6F34`
(Shenmue II: `*0x8C317E44`).

The parts of the library that are DOA2-only, or missing from Shenmue II:

- the twin walker family 0x8C107E60 (section 4);
- the pre-light walker 0x8C10D120 and its kernels 0x8C10D360/0x8C10D680
  (section 5);
- the eye-vector prologue of the draw API (0x8C111560/0x8C111580) and the sphere-map pass 0x8C112560. Shenmue II has its sphere map in game code. The draw tail itself is shared.

## 2. Draw API and per-model flow

| Entry | Game call sites | Does |
|---|---|---|
| 0x8C111680 | about 224 | draw one model with the current matrix, alpha 1 |
| 0x8C1116A0 | 34 | same with alpha in fr4: TSP blend is rewritten, translucent list |
| 0x8C111580 / 0x8C111560 | about 310 / 146 | first rotates the eye position into model space (FIPR + FSRRA, stored at 0x8C2E64B0) for the specular kernels, then the same tail |
| 0x8C103920 / 0x8C103980 | 5 / 1 | NL table entries (the walker slots 0x8C103FE8 / 0x8C104058) |
| 0x8C104240 / 0x8C104290 | 16 / 3 | pre-light a model in place / undo it (section 5) |
| 0x8C101430 / 0x8C101450 | 11 | modifier-volume draw (section 7) |
| 0x8C103C70 / 0x8C103D40 | 27 / 0 | sphere-in-frustum test only (returns 0/1) |
| 0x8C103BE0 | about 70 | type -3 hook select: 0 none, 1 = 0x8C10A5EA, 2 = 0x8C10B1CA |
| 0x8C100430, 0x8C100890 | about 200, about 140 | 2D sprites (NLSPRITE), not 3D |

**Tail 0x8C1116C0.**
- The entries push the matrix first (0x8C0FDEC0, or inline in 0x8C111580/60);
  the tail pops it (0x8C0FDE70) after the walker.
- It loads the projection at `0x8C2F0670` into the back bank, rearranging every
  4-float group `(m0,m1,m2,m3)` to `(m3, m0, m1, -m3)`. The z row is dropped and w
  comes first, so FTRV in the kernels returns `(w, X, Y, -w)` and the PCW store
  overwrites w. This is the trick documented for Shenmue II.
- It forms `XMTRX = permuted projection x modelview(0x8C2F0630)` with 4 FTRV + FRCHG
  (0x8C1111E0) and calls the plain alpha walker 0x8C101542 directly.

These draws therefore never take the twin walker.

**Matrix library [C].**
- Loading XMTRX is 8 SZ=1 pair moves straight into XD0-XD14 (0x8C110F80, 26+
  callers in character code).
- Rotations are FSCA + 2 FTRV + pair moves into XD (0x8C1117C0, about 300 call sites).
- Push/pop are 0x8C0FDEC0 / 0x8C0FDE70 (about 134/137 sites).
- 0x8C111580 transposes the rotation in the back bank by shuttling elements
  through FPUL (`flds/fsts`), with no memory traffic.

**Culling.**
- Per mesh, the NL walker tests the bounding sphere (one FTRV, near plus 4
  side planes), as in Shenmue II.
- Per model, game code calls the sphere test 0x8C103C70 (27 sites; 0x8C103D40
  has no caller) before drawing. Nothing else: no portals, no LOD meshes [P].
- Back faces are culled by the PVR (the ISP cull mode comes from the strip
  flags).
- The near plane is handled by Shenmue II's in-strip clip twins (0x8C101CA2 and
  others), at about 50-60 cycles per vertex.

## 3. Data: `*.CHR`

`*.CHR` is a small header plus NL MT7 models. Shenmue II's `tools/mt7.py`
`parse_model()` reads every model in all 86 `.CHR` files with no error (the
command line expects an MT7 header; use `tools/chr.py` for whole files).

- **Header.** `u32 firstModel (0x18), modelTable, texTable, nModels, nTex`.
  - Model pointers are absolute: base `0x0C2FFFE8` for characters, `0x0C3FFFE8`
    for stages and effects. The loader must relocate them, because two
    characters are resident together [P].
  - Texture records are 12 B: `{w | h<<16, format, VRAM address}` (0x0D2xxxxx
    for characters, 0x0D6xxxxx for stages and effects).
- **Model and mesh.** These are exactly MT7:
  - mesh header: PCW/ISP/TSP/TEX, sphere, texture index, type byte at +0x24,
    9 colour floats, byte size;
  - strips: `{flags, n}`, with 32 B inline vertices `{xyz, nxyz, uv}` (x LSB = 1)
    or 8 B back-references.
- **Mesh types (all files).** 0: 6116, -1: 3467, 5: 2315, -3: 2306, 1: 1729, then
  2, 3, 10, 6, 4, 7, 8. Type n > 0 selects specular table n (r8 = table + n<<9).
- **The PCW tells characters from stages.**
  - Characters use `0x8000002C/3C`: intensity modes 1/2, textured, offset, no
    "shadow" bit.
  - Stages and effects use `0x800000AC/BC/9C`, with bit 7 set: affected by
    modifier volumes. `0x9C` is floating-colour, used by the type -3
    vertex-colour meshes.

| Set | Files | Average triangles | Average strip entries | Inline vertices | Average strip length |
|---|---|---|---|---|---|
| Characters | 42 | 8,924 | 11,704 | 58% | 9.5 |
| Stages | 41 (12 are 200-triangle stubs) | 8,513 (big ones 12-28k) | 13,757 (big ones 20-33k) | 82% (52-97% on the big ones) | 6.0 |
| EFC0/EFC1/FIX | 3 | 4,577 | 5,597 | 63% | 13.1 |

- **Character strips are long.** They average 9.5 entries, against Shenmue II's
  4.5. 42% of character entries are back-references, which are re-transformed
  but read from cache.
- **Stage geometry is mostly short quads,** with few back-references. The pre-lit
  stages STAGE10/11 are about 70% type -3 (STAGE00/24/25 are similar); STAGE05
  is mostly specular types (64%).
- **A typical costume (AYA00).** 48 models: 9,138 triangles, 98 meshes (68 of
  type 1). Models 33-47 are 15 untextured (texture index -1) type -1 meshes
  with ISP `0x83400000`, closed hulls with extruded vertices. A run of 15-21
  such hulls exists in 40 of the 42 costumes, at a costume-specific index
  (none in WBA00/YTI00). They are probably the limb shadow volumes (section 7).
- **Other per-character files.**
  - `*.APV`: groups of `{vertex byte-offset list, -1}` plus keyframes of packed
    xyz. AYA00 group 0 holds 8 position blocks (base + 7 targets) of 236
    vertices whose offsets fall in one model, probably the head: facial
    animation, probably.
  - `*_A0n.ACS`: accessory/soft-part simulation set-up [P].
  - `*.MOT`: cubic-polynomial motion channels, evaluated with 3 FMAC per channel
    (Horner) in game code (0x8C0723DA-0x8C072942). This is skeleton logic, not
    vertex work.

## 4. Kernels and the DOA2 twin

| Kernel | Use | Per strip vertex |
|---|---|---|
| 0x8C101A52 (= SM2 0x8C1D79B2) | type 0, `I = ambient + max(0, N.L)`, light pre-rotated to model space | 79 instructions per 2 vertices on the back-reference path (85 inline), 1 FTRV + 1 FIPR + 1 FDIV, **about 30-35 cycles** |
| 0x8C101BA6 (= SM2 0x8C1D7B06) | type > 0: second FIPR with the eye vector from 0x8C111580, `ftrc` index into the per-material table | about 48-52 instructions, about 40-45 cycles |
| 0x8C101930 (= SM2 0x8C1D7890) | type -1 unlit | about 25-30 cycles |
| 0x8C10A7E0 (= SM2 0x8C1D4620) | type -3 packed vertex colour (hooks 1/2) | about 30 instructions, about 20-24 cycles |
| 0x8C101CA2 and siblings | near-clip twins | about 50-60 cycles |
| **0x8C108372** (DOA2 twin, section A) | type 0 plus an offset ramp | 97 per 2 vertices (91 back-reference): **+6 per vertex**, about 35-40 cycles |

The specular table (32 x 128 floats, rows of 512 B at 0x8C2F0940) is built once
by 0x8C103860 (called from 0x8C0165B2) as repeated powers. It is Shenmue II's
0x8C1D66E0.

**The twin kernel (0x8C108372, walker 0x8C107E60).**
- r13 points at `{k, -b}` (0x8C1CA940, written by 0x8C103B60(b=fr4, k=fr5)). Per
  vertex the twin adds `I_offset = (r8 >= 0) ? k*(I - b) : 0`. The plain kernel
  always writes 0.
- The PVR adds the offset intensity to the textured result, so this is a
  brightness/flash ramp driven by the diffuse term, unclamped (the PVR saturates).
- 0x8C103B60 swaps both walker slots to the twin when `k > 0` and `b >= 0`. It
  has three game callers (0x8C0A8C26, 0x8C0A8E7C, 0x8C0BF7CC). The effect is
  probably a hit flash or a special-move glow [?].
- Only the slot-based entries (0x8C103920/0x8C103980) use the twin, because the
  draw API calls 0x8C101542 directly. The twin is rare in practice [P].

**Pipelining and pairing.** These are Shenmue II's 2-vertex software pipeline:
- FDIV of vertex n is used about 20 instructions later, while n+1 is loaded and
  transformed;
- 64-bit pair loads and stores;
- `pref @r4` 32 B ahead on the source and `pref @r6` per vertex on the SQ.

Integer and FP instructions are interleaved for dual issue, so the 40-instruction
body runs in roughly 30-35 cycles. 1/w is always FDIV, and FSRRA (30 in the
library) is used only for normalising and lighting. The DOA2-only C loops below
are not pipelined.

## 5. Stage dynamic lights: in-place pre-light (0x8C10D360)

Entry 0x8C104240 runs: 0x8C0FCB10 rotates the 16 light records into model space
(rigid inverse 0x8C0FCF90), 0x8C103F50 loads the permuted projection, then walker
0x8C10D120, then it sets flag 32 in the object. Six stage
draw functions call it every frame over all their parts: the 116-part loop at
0x8C08E47E, and 0x8C094E7C, 0x8C09B01C, 0x8C0A9B82, 0x8C0ABC04, 0x8C0B16E6.
0x8C104290 is called instead when the stage switches the lights off, and
restores the meshes.

**Per mesh.**
- Light culling (0x8C112D80) tests the bounding sphere against every active
  light: point range, spot cone with FSQRT/FDIV. Lights are 0xB0 B records at
  0x8C2EF7E8 with types 2/3/4 and active mask `*0x8C1CA788`. The result is a
  bitmask.
- The ambient times the material colour is precomputed.

**Per inline vertex only.** Back-references are skipped, so each unique vertex
is lit once:
- The first time a mesh is lit, the float normal is packed into the nx slot as
  `0x80|nx|ny|nz` (s8 x 3, scale 127). The original mesh type goes into the
  header (+48 >> 16) and the mesh becomes type -3. Later passes unpack the s8
  normal (3 x `exts.b` + `float` + `fmul`).
- Directional lights cost 1 FIPR and a clamp at 0.
- Point and spot lights:
  - `L = Lp - P`, FIPR N.L, FIPR L.L, a range test, FSRRA for 1/d;
  - the spot cone from L.D;
  - attenuation `N.L / (d (k0 + k1 d + k2 d^2))` with one FDIV, applied only when
    the divisor exceeds 1.
- RGB is accumulated with 3 FMAC.
- The output is two words written into the vertex itself:
  - base ARGB = material x light, clamped, at +16 (the old ny);
  - offset ARGB = `(light - 1) x k`, clamped, at +20 (the old nz).
  Over-bright light therefore becomes the PVR offset (additive) colour.
- Cost: about 135 instructions with one directional light, roughly 110-130 cycles
  per unique vertex, plus about 50 instructions per point light. About 20
  branches per vertex, mostly the 4-way clamps.

**Why.**
- The RGB walker (Shenmue II's multi-light path) would cost 70-80+ cycles per
  strip vertex and emit 64 B type-5 vertices.
- This pass emits 32 B packed vertices through the cheapest transform kernel, and
  lights only unique vertices.
- It is a Soulcalibur-style split (light once, transform per strip entry) done in
  place in the MT7 stream.
- Stage strips are short (82% inline on average), so the saving is mostly in TA
  bandwidth and the cheap kernel rather than in sharing.

## 6. Characters

**Skinning: there is none [C].**
- Every costume is a set of rigid MT7 limb models, drawn one per bone with the
  bone's matrix through the draw API. No NL kernel reads weights or indices, and
  no matrix blending exists in the library.
- The game code has no vector FP. Its only FP loops with vertex-like strides are
  the in-place writers below, the motion curves and the particle/stage updates.
- No seam-patch code was found. The `.SUP` files hold seam-vertex records that
  look like Shenmue-style welds (notes-system), but their consumer was not
  located.
- The per-frame loop that calls the draw API for the character's limb models was
  not pinned down. All draw-API call sites are in 0x8C08C000-0x8C0E1000, a mix of
  per-stage and scene draw functions [P].

**Soft parts: particles written into the mesh [C for the mechanism, P for the
content].**
- The accessory module 0x8C0C4000-0x8C0C7C00 keeps chains of particles (48 B
  records) per character.
- It inverts 15 bone matrices per character (0x8C0FD2B0, 64 B each, at
  `*0x8C29DAF8`) and solves distance constraints:
  - 0x8C0C6278 and five copies;
  - scalar, 81 instructions per link: FSQRT + FDIV, both ends moved;
  - position-based, Jakobsen/Verlet style.
- Then 0x8C0C5996 transforms each particle into its bone's model space
  (0x8C111B80, one FTRV whose result is stored the next instruction, so about 4
  cycles of stall). It stores x,y,z into every vertex record listed for it, at
  object+0x1F0, with seam duplicates flagged by the list LSB. It ORs 1 into x so
  the walker still sees an inline vertex.
- Cost: about 45 instructions per particle plus about 10 per duplicate record.
- The deformed model is then drawn normally. Some go through the sphere-map pass
  first: 0x8C0C5486/5642/596A call 0x8C112560.
- Hair and ribbons are the obvious users. Breasts and the like are more likely
  bone-level springs in the skeleton code, which was not traced.

**Vertex animation (APV).**
- Four helpers at 0x8C0CF8FA-0x8C0CFA16 take a `-1`-terminated list of vertex byte
  offsets plus packed xyz keys and write blended positions into the records,
  with the tag OR:
  - `A + tB`: 24 instructions;
  - `tA + (1-t)B + C`: 37 instructions;
  - copy: 18 instructions;
  - `v += tA`: 24 instructions.
- This matches the APV layout exactly.
- No static caller was found. They are probably reached through a computed
  pointer [?].

## 7. Shadows

**Characters [C for the mechanism, P for the model identity].**
- Driver 0x8C0D3DF0, once per player:
  - it skips when the floor test fails;
  - it scales the light direction (0x8C2A60E0);
  - for 15 joint pairs (straight-line code) it calls 0x8C0D43E8 (6 sites) or
    0x8C0D4462 (9 sites).
- Those build a matrix (0x8C2A60F0) mapping a unit volume model onto the segment
  joint A to joint B, sheared along the light (`B - L * B.y`, renormalised), then
  multiply by the view.
- They tail-call 0x8C101430. That is NL's modifier-volume draw: header PCW
  `0x818C0000 | flags`, opaque-modifier list (QACR from list +4), then the Shenmue
  II volume kernels 0x8C10DB80 and its siblings.
- Each strip vertex becomes one 64 B volume triangle, with no CPU back-face cull:
  about 35-45 cycles per triangle.
- The volume models come from the character's CHR slot table
  (`0x8C22120C + slot*0x400`). These are most likely the 15 untextured type -1
  hulls (15 calls, 15 hulls).
- The result is a real projected shadow per limb on any floor whose mesh has PCW
  bit 7. The characters themselves never receive volume shadows (their PCWs lack
  the bit).

**Stage objects.** Stage functions draw fixed volume models the same way, for
example five at 0x8C0AE060-0x8C0AE080 and four at 0x8C0B88B6.

## 8. Reflections, environment maps, effects

**Sphere-map UV pre-pass, 0x8C112560 [C].**
- It walks the mesh stream and skips type -2 and back-references.
- For strips whose flag has bit 8, it rotates the normal by XMTRX (view
  rotation): `u = 0.5 + s n'x`, `v = 0.5 + s n'y`. s is 0.5, or 1/256 for s8
  normals. It keeps the old v LSB.
- Cost: 31 instructions per vertex (about 40 with s8 normals).
- Nine game call sites (seven literal loads): stage functions and the accessory
  module.
- Nothing else reflects. There is no planar mirror, no second camera pass and no
  framebuffer read-back in the vertex code. Water and ice floors would get their
  look from env-mapped or translucent meshes [P].

**Effects and particles.**
- No particle kernel exists in NL. Effects are NL models from `EFC0.CHR` (122
  models, mostly translucent type -1) and `FIX.CHR`, drawn through the normal API
  (often the alpha 0x8C111560).
- Their state is updated by scalar game loops, for example 0x8C092E58 with 45
  slots x 5 trail points of 24 B.
- Stage modules also edit MT7 records in place before drawing:
  - 0x8C0C0CBA copies and scales UVs, 9 instructions per vertex;
  - 0x8C0C0DD0 offsets positions;
  - 0x8C0C0260/0x8C0C0794 run spring/follow updates.
  These are probably animated water and props [?].
- Vertex-pool callbacks 0x8C1126C0 (one light) and 0x8C112800 (up to 16 lights)
  are installed in GBR+16/+20 by 0x8C112160. They are the same as Shenmue II's
  0x8C1DE1FC/0x8C1DE320, but have only one game caller, and their consumer was
  not found.

## 9. Output path and cache

- **Store-queue output.** Kernels write through the store queues. The walker sets
  `QACR0/1 = list pointer >> 24` from Kamui's table `*0x8C2B6F34` when the list
  changes.
- **Free command words.** The PCW is the SQ address itself (`0xE0..`), with
  `shar` marking end of strip (`0xF0..`), exactly as Shenmue II.
- **Possible RAM path for alpha.** The alpha RGB path 0x8C1041C0 forces QACR = 0x0C
  (RAM area 3), so at least that list goes through a RAM buffer and DMA. The
  Kamui configuration names opaque as the direct-transfer list (notes-system),
  so opaque is probably direct TA [P].
- **No `kmSetVertex`.** No vertex path calls `kmSetVertex`, and the only TA FIFO
  (`0x10000000`) users are in Kamui and Shinobi.
- **No OCRAM, no `movca.l` in vertex code [C].**
  - syCache init 0x8C117798 is called with `*0x8C14E084 = 0x105` (OCE|CB|ICE, no
    ORA).
  - The single `0x7C000000` literal (0x8C118024) is Shinobi's OCRAM allocator,
    with no caller.
  - In code, `movca.l` occurs once (0x8C117F3E, Shinobi).
  - `ocbi` (9) and `ocbp` (9; a tenth hit at 0x8C10571C is a literal word) occur
    only in syCache and middleware range purges and NL's DMA-coherency helpers
    0x8C111E80 and 0x8C111EC0.
  - `ocbwb` is also used by the frame-skip patcher.
  - The 74 `movca.l` and 101 `ocbi` beyond 0x8C13F000 are data.
- **Instruction counts by region.** FSCHG 405, FRCHG 116, FTRV 242, FIPR 109,
  FSRRA 30, FSCA 18 and PREF 397 are in the library region. Game code adds one
  FIPR and 6 PREF (the APV blend helpers).

## 10. Frame skip

- **Detection.** The main loop (0x8C012600-0x8C012716) compares Kamui's last PVR
  render time (`*0x8C2E1F80` via 0x8C0F9B80) with the frame budget
  `(vsync + late) x 16000 us`. If it is over, it calls 0x8C012A74.
- **Patching.** That routine swaps the first 4 bytes of 11 entry points with a
  saved `rts; nop` (`0x0B000900`, kept at 0x8C150398-0x8C1503C0):
  - the draw API (0x8C111580, 0x8C111680, 0x8C111560, 0x8C1116A0);
  - the NL entries 0x8C103920, 0x8C103980, 0x8C1040B0;
  - sprites (0x8C100430), volumes (0x8C101430/50) and debug print (0x8C0FBB30).
- **Cache.** Each patched line is written back (`ocbwb`, 0x8C111F00). The routine
  then jumps to 0x8C1177EE through P2 to set CCR.ICI.
- **Restore.** Calling it again (0x8C012714) puts the original words back.
- **Effect.** One logic pass then runs at full speed with every draw call
  returning immediately. This is a cheap 60 fps catch-up that needs no draw flag
  in the game code.

## 11. Where the time goes (rough)

At 60 fps the CPU has about 3.3M cycles per frame.

| Item | Strip vertices | Cycles per vertex | Cycles per frame |
|---|---|---|---|
| Two characters (upper bound: all limb models drawn) | about 20-22k, mostly specular type 1 or type 0 | 35-40 | 0.8M |
| A big stage, before culling, on the type 0/specular kernels | 20-33k | 30-40 | 0.6-1.0M |
| Pre-lit stages: lighting per unique vertex | | +110-150 | |
| Pre-lit stages: transform on the fast kernel | | 20-24 | |
| Shadows: about 10 small volumes per character | | | small |
| Soft parts: a few hundred particles | | 45-60 per particle | 10-30k |

So vertex work is probably 40-60% of the frame, which leaves room for the game,
physics and audio at 60 fps. All figures assume cache hits.

## 12. Comparison

| | DOA2 | Shenmue II | Soulcalibur | Le Mans |
|---|---|---|---|---|
| Library | AM2 NL 0.9 | AM2 NL 0.8 + NLOBJPUT (same kernels) | Namco own | own |
| Bulk kernel | NL type 0 / specular, about 40 instructions, 2-vertex pipelined, about 30-35 cycles | same code | about 100 cycles per unique vertex + about 20 per strip vertex (characters) | 30 instructions, prelit, about 30-34 cycles |
| Vertex sharing | none (re-transform; 42% back-references on characters) | none | pool | none |
| 1/w | FDIV, latency hidden | same | FDIV, about 9-cycle stall | FDIV, about 8-cycle stall |
| Characters | rigid limbs; particle chains and APV write vertices in place | rigid limbs + joint seam patches in place | weighted partial vertices per bone | n/a |
| Coloured local lights | baked per frame into packed ARGB, then the fast kernel | RGB walker, 64 B vertices | 4 lights by 2 FTRV | baked |
| Shadows | modifier volumes per limb, sheared between joints | model-strip volumes | one-winding volumes | n/a |
| Env map | sphere-map UV pre-pass | same idea (game-side copy) | screen-space env map (Metal Model, 0x8c03fac0) | car-paint reflection pre-pass with a sphere map (0x8c164960) |
| OCRAM / `movca.l` | no / no | no / no | no / used in pool writes | no |

DOA2 and Shenmue II are both clients of the same renderer (DOA2 ships NL 0.9,
Shenmue II NL 0.8; the version numbers do not say which came first). Its own additions are about doing more with the cheap
kernels:
- light baking into the stream;
- the offset-intensity twin;
- CPU-written soft geometry;
- volumes per limb;
- frame skip by patching code.

## Uncertainties

- **The character draw loop.** It was not located. The claim that limb models go
  through 0x8C111580/0x8C111680 rests on the API being the only route to the
  walkers.
- **The 15 CHR hulls as shadow volumes.** This is inferred from their properties,
  their count and from the shadow driver indexing the CHR slot table.
- **The use of the twin offset ramp** (callers 0x8C0A8C26, 0x8C0A8E7C, 0x8C0BF7CC)
  and the meaning of r8 >= 0 in it.
- **APV as facial animation.** Also unresolved: what calls the blend helpers.
- **Which stages run the pre-light pass** (the six functions above), and whether
  it runs every frame or only while lights move. The call sits in per-frame stage
  code, but its condition flag (`obj+20`) was not traced.
- **The opaque list path.** The Kamui configuration (notes-system) makes opaque
  the direct-transfer list, but the runtime list pointer was not traced.
- **Stage water/snow/ice specifics.** No dedicated wave or snow kernel exists. The
  in-place stage edits found were not tied to particular stages.
- **Cycle counts** are static estimates. Strip entries per frame after culling
  were not measured.
