# Shenmue II (DC, JP, Disc 1): world, streaming, visibility, NPC crowds

Executable `1ST_READ.BIN`, base `0x8C010000`. Data under `SCENE/01/`. All
addresses are runtime addresses. File offsets are relative to the start of the
file or chunk named. The parsers in `tools/` (`mt7.py`, `ipac.py`, `area.py`,
`sm2walk.py`) produce the counts below.
Confidence: **[C]** confirmed in code or data, **[P]** probable, **[?]** guess.

## 1. Data formats

### Containers
- **PKF** = `PAKF` (u32 size, u32 hash, u32 texCount) holding `DUMY` and
  `TEXN`×n (`GBIX`+`PVRT`), then an `IPAC` directory. Texture pack. [C]
- **PKS** = `PAKS` then `IPAC`. IPAC header: `"IPAC", u32 dirOfs, u32 count,
  u32 size`. Directory entries are 20 bytes: `name[8] ext[4] u32 ofs u32 size`,
  with ofs relative to the IPAC. Entry kinds: `MAPM` (map geometry), `CHRM`
  (character/prop model), `PROP`, `SRCH`, `FLDD` (collision), `LGHT`, `SNDP`,
  `MOTN`, `AUTH` (also `BIN `, `ECAM`, `DYNM`). [C]
- `MPK00.PKF/PKS` (the main area pack) is **gzip-wrapped** (`1f8b`, embedded
  name `MPK00.PKSirs…tmp`). Other packs are mixed:
  153 of the 266 non-MPK PKS are gzip-wrapped (in WT00, `WTP*`/`WTR0` raw,
  `WTK*`/`WTX*` gzip). [C]
- **AFS** = `"AFS\0", u32 n, n×(u32 ofs, u32 size)`. Data starts at 0x80000 and
  entries are aligned to 0x800. [C]
- **STREAM/*.AFS are ADX voice audio, not geometry.** 32,245 of the 32,769
  entries are mono ADX (`80 00 …`, 11,025 or 14,000 Hz); the rest are small
  `CHID`/`SPSD` records. `FREE01.AFS` has 25,039 entries: 24,803 ADX clips
  (mostly 11,025 Hz, avg 9 KB, "free talk") plus 236 `CHID`.
  `STREAM/*.IDX` = `IDXC`/`TABL` cue-name→index tables (`A001`, `A002` …).
  The code side is the CRI ADXF partition loader (strings at 0x8C22DD18…, `SCENE/%02d/STREAM/%s` at 0x8C235710, `FREE0%d`
  at 0x8C2356F8). [C]

### MDx7 model (`MDO7` map, `MDC7`/`MDL7`/`MDP7` characters and props)
- Header: `4cc, u32 size, u32 firstNode, u32 texCount`, then texCount × 16 B
  descriptors (`u16 w, u16 h, u32 fmt, 8-byte id`). [C]
- Node (0x40 B): `u32 id|flags` (high halfword: low nibble = cull class, see
  §3), `f32 pos[3]`, `s32 rot[3]` (0x10000 = 360°), `f32 scale[3]`,
  `u32 model, child, sibling, parent, 0, 0`. Map MDO7 trees are flat (root plus
  one level). Characters are hierarchical rigid segments (7–110 nodes, median
  33), with **no skin weights in the node tree** (joints are patched on the
  CPU, see `notes-tnl.md`). [C]
- Model: `u32 a, u32 b, f32 sphere[4]` (centre, radius), then meshes, then
  `u32 0, u32 nOut` (nOut = total strip entries, i.e. the T&L output-slot
  count). [C]
- Mesh: `u32 pcw, isp, tsp, texctl` (these are **real PVR words**; the PCW
  list type sits in bits 24-26, with 0x82 = translucent and 0x84 =
  punch-through), `f32 sphere[4]`, `s32 texIndex`, `u32 0`, `f32 colour[9]`,
  `u32 dataBytes`, then strips. The mesh header is 0x50 bytes. [C]
- Strip: `u32 flags, u32 n`. Flags 0x10 = strip, 0x08 = triangle list
  (n = number of triangles), 0x80 = "continue" (same state). Each entry is one
  of two kinds:
  - a **32-byte vertex**: `f32 pos[3], f32 normal[3], f32 uv[2]` (low mantissa
    bits of x and u carry flag bits); or
  - an **8-byte back-reference** `{u32 outOfs, s32 srcOfs}`. Its second word
    is always negative, so it reads as a NaN y and is easy to detect. srcOfs
    points back to the source vertex (relative to the end of the entry).
    outOfs is probably an offset into the already-transformed output buffer
    (MDO7 marks it `0x5Fxxxxxx`; MDC7 often uses 0); the kernels only test
    its low bit, so this reading is [?].

  So vertices are **float, unindexed, inline in strips**, with a small
  transformed-vertex reuse mechanism. [C]
- Lighting format: map PCWs `0x800000ac/bc` use col_type 2/3 (intensity
  modes 1/2), i.e. one intensity per vertex with the colour taken from the
  mesh. TSP fog bits are 00 (table fog) on map and NPC meshes. [C]
- Instancing: nodes share models (WTP0: 212 nodes / 141 models; WT00 MAP01:
  336 nodes / 179 models, 10.8 k unique triangles → 35.1 k instanced). [C]
- Textures: map textures are VQ without mipmaps (type 0x03: 155× 565,
  23× 1555, 15× 4444 in WT00, plus 5 twiddled), sizes 128² (119), 64² (53),
  256² (21). NPC textures are twiddled, twiddled-rectangular or VQ (types
  0x01/0x0d/0x03: 1,757/1,497/1,390), mostly 64–128 px, without mips. [C]

### Measured geometry
| pack | nodes | tris unique / instanced | strip entries | full verts | geom bytes | B/tri |
|---|---|---|---|---|---|---|
| WT00 MAP | 155 | 5,764 / 8,032 | 10,390 | 10,110 | 383 K | 66 |
| WT00 MAP01 | 336 | 10,798 / 35,114 | 19,314 | 17,718 | 671 K | 62 |
| WT00 MAP02 | 143 | 5,820 / 16,192 | 10,400 | 9,363 | 354 K | 61 |
| WT00 MAP03 | 234 | 9,134 / 20,916 | 16,362 | 15,340 | 575 K | 63 |
| WN00 MAP+MAP01 | 614 | 24,807 / 48,943 | 46,459 | 44,588 | — | — |
| interior WTP0 | 212 | 5,746 / 8,280 | 9,314 | 8,121 | 304 K | 53 |
| interior WTK0 / WTX2 | 127 / 158 | 9,904 / 10,454 | — | — | 474 K / 536 K | 48 / 51 |
| NPC 00A_ (OK1_L, MDC7) | 23 | 574 | 874 | 579 | 25 K | 43 |
| NPC MMC_ / ZOH_ | 35 / 34 | 900 / 886 | 1,284 | 842 / 895 | 36 K / 37 K | ~40 |

- Strip shape in WT00 MPK00: **79 % of 13,155 strips have exactly 4 entries
  (quads)**. Next most common are 6 (8 %) and 3 (3 %). Only 55 triangle
  lists. Back-references make up 6.4 % of entries. Average strip length is
  about 4.5, so the data is not stripified for long runs. [C]
- HUMANS NPC set (all 776): triangles min/median/max **130 / 863 / 2,798**;
  nodes median 33; textures median 6 (PKF median 107 KB, max 525 KB); PKS
  around 50 KB. [C]

### Area-level files
- **MAPINFO.BIN** is a chunk list: `ATTR SNDP LGHT ECAM FLDD DOOR SCEX REGD
  WTHR EVFD LSCN MAPT CHRD END` (some areas add `SCN4 MAPR MPMV SHRG`).
  `FLDD` = float collision polygons (WT00: 110 KB). `WTHR` = polygon regions
  (x/z quads plus a y range; probably rain-free or covered areas). `DOOR` =
  door↔room ID pairs (`R201→R001` …). **There is no PVS, occlusion or LOD
  table.** [C, WTHR meaning P]
- **MISC/AREATBL.BIN**: 132 records of 32 B (`name[4]`, ints, then `f32
  farA, farB, farC` at +20/+24/+28). Examples: WT00 80/35/30, WN00 75/35/30,
  WK00 115/25/30, WS00 70/50/30, AR02 155/30/30, WE00 280/40/30. The loader
  passes these to setters 0x8C06E240/260/280 (call site at 0x8C11C6E4…). [C]
- **MISC/NPCAREA.BIN**: a 4-byte header, then 78 records of 0x1C B: area
  pattern (1–12 codes, `*` wildcards), NPC script `.BIN`, then
  `u8 maxNPC, u8 minNPC` at +12
  (WT00/WN00 32/26, AR02 32/20, ARSF 46, QTB4 50), plus pointers to `.MPT`
  and `.MOT` lists. Read at 0x8C1024A6–0x8C1025AC into 0x8C2E9EA8 (max) and
  0x8C2E9E68 (min). [C]
- **MISC/DOORTBL*.BIN / DOORDAT*.BIN** are SH-4 code overlays
  (`e6 2f` = `mov.l r14,@-r15`), not tables. [C]
- **NPC/HUMANS.IDX**: `u32 n=776`, n × 4-char names (`00A_`…`ZOH_`), then
  n × u32 sizes, the texture sizes used for the memory check (equal to the
  PKF entry size for 746 of 776).
  **HUMANS.AFS** has 1,552 entries = 776 pairs (`2i` = PKF textures,
  `2i+1` = PKS holding the `CHRM` model, plus a `BIN` script/table in 335 of
  them, 123 MB total). Each NPC type has one model (two have a second
  `CHRM`); there are no LOD variants. [C]

## 2. World structure and streaming

- **Area = one resident pack.** On area entry the loader builds
  `scene/%02d/%c%c%c%c` (0x8C230F60 at 0x8C11C76E), loads `MPK00` (the code
  loops over `MPK%02d` at 0x8C11C61C), and registers `MAP.MT7` /
  `MAP%02d.MT7` into **32 map-block slots of 108 B** (0x8C2ACFDC, loop
  0x8C11C4A0, `MAP ` tag). Raw sizes: WT00 PKS 2.52 MB geometry plus 1.32 MB
  PKF textures (198); WN00 2.38 + 1.33 MB; AR02 2.97 + 1.42 MB (20 map
  blocks). On disc the PKS compresses about 4:1 under gzip, the PKF about
  1.2:1. [C]
- Map blocks (`MAP`, `MAP01`…) are spatial chunks of the district, about
  60–220 m on a side. WT00 spans roughly x 112–336, z 206–391 (metres). Blocks
  are switched on and off as units through 32-bit masks at 0x8C2AE15C
  (setters 0x8C11D080/0x8C11D060, also called from event code at 0x8C147C2C
  and 0x8C15FE7A), not by distance. [C mechanism, P usage]
- **Interiors** (`WTP0..4`, `WTK0..2`, `WTR0` … in the district folder) are
  separate PKS packs, each with its own `FLDD`/`LGHT`/`MAPM`/`SNDP`
  (6–11 k tris, 0.2–0.55 MB). They are tied to the MAPINFO `DOOR` table, so
  they load on door transitions rather than by continuous streaming. [P]
- The **only continuous streams** are ADX voice (ADXF partitions; STREAM
  AFS/IDX) and **NPC models** (below). There is no position-predictive
  geometry streaming. [C for what exists; absence P]
- **NPC model cache** (0x8C102A40…0x8C102E4C): per-type state array
  (`NPCH` tag, 776 × 8 B at *0x8C2E9E30), states 0 idle, 1 requested,
  2 reading, 3 resident. A request (0x8C102C40) runs these steps:
  1. Query free texture memory (0x8C0C9600 → library 0x8C20F7A0). If
     `PKF size + 0xC18` exceeds the largest free block, return -4.
  2. Query the main heap (0x8C054080: total, largest and fragmented free; the
     result is cached once per frame at 0x8C2ACBF0, minus a 14 KB (0x3800)
     reserve). If it doesn't fit, return -3.
  3. Issue an async read of AFS entries `[2i, 2i+1]` (0x8C126540/560 →
     0x8C126580, a load queue of 52 × 108 B at 0x8C2AE48C).
  4. Poll the read (0x8C1269A0).
  5. Bind the textures and model (`BIN ` tag via 0x8C126D00).

  If memory is short the NPC is simply not spawned. [C]

## 3. Visibility, LOD, fog

- No precomputed visibility. The map draw (0x8C11B000 →
  0x8C119B80 → recursive node walker **0x8C1199E0**) walks the node tree with
  a matrix stack. For each node it reads a 32-byte node-info record (array
  *0x8C2ACE94, built at load in 0x8C11A0C0…) and dispatches through
  `0x8C230EE0[type]` (fr4 = radius). The tests are hand-written sphere/frustum
  assembly (**0x8C04E0D8, 0x8C04E124, 0x8C04E1B4**): `ftrv` the centre,
  near test `r - z < 0`, far test `-z - r > far`, then |x| and |y| against
  `(r - z)·k + r`. Constants sit in a literal block at 0x8C04E200, written
  each frame by 0x8C04DF60 from 0x8C11BDA0 (camera projection plus the
  AREATBL distances). [C]
- **Cull class (the LOD mechanism)**: node flag low nibble → table
  0x8C254ED8: `0,1,5,7,11 → class 0` and `4 → class 4` (both 0x8C04E0D8,
  far = farA), `6 → class 8 (far = farB)`, `9 → class 16` (0x8C04E170: near
  and side planes only, no far test; 1,770 nodes in the district packs, e.g.
  WT00 radius about 15 m), `2 → 0xFF (never drawn)`, `3 → 0xF0` and
  `8 → 0xF4` (special nodes, e.g. WT00 MAP05's 90 untextured quads at
  constant y). Data match: flag-6 nodes are the small clutter (WT00 MAP01:
  80 nodes, mean radius 1.1 m), and they disappear at farB (35 m in WT00).
  Most other nodes are culled at farA (80 m). A class-12 variant (0x8C04E1B4)
  also rejects spheres nearer than farB, so a "far-only" stand-in is
  possible, but no flag value maps to it. **There are no per-model mesh
  LODs**: no duplicate models at the
  same node, and NPCs have a single model. [C code, P data interpretation]
- farC (30 m in most areas) drives the **fade of objects with a `CPAM`
  component** (0x8C0D74F8: view distance > farC ± 0.5 starts fade-out, with
  hysteresis). [P]
- Each mesh also carries a bounding sphere, tested in the mesh walker
  0x8C1D7480 (see `notes-tnl.md`). [C]
- Fog: per-mesh TSP selects table fog. Fog register writes go through the
  library (base + offset), so this pass found none. A debug printer uses a
  `FOG ` tag (0x8C097AC0). [C/P]

## 4. NPC crowds

- **Spawn and keep rules** (0x8C10DCA0, 0x8C10E2C0; distance = `fipr`/`fsqrt`
  helper 0x8C04CDE8 from camera):
  - **Spawn**: within 25 m and inside the frustum (r = 1). Spawn points of
    mode 1 also need more than 6.5 m.
  - **Keep**: always within 30 m; within 75 m only while inside the frustum
    (r = 5).
  - **Despawn** otherwise.
  - Spawn and despawn fade alpha by **±0.05 per frame** (constants at
    0x8C10DF34/38/40, 0x8C10E3DC/E4/E8/F0). [C]
- **Population cap** 0x8C1066C0: `cap = max(minNPC, maxNPC −
  int(maxNPC·f·0.5))`, with max/min from NPCAREA (default 32). f is a global
  scalar from 0x8C1B9940 (0x8C3011AC+12); a separate flag is set when
  f < 0.15. It is probably a weather or rain factor [?]. Each NPC adds a
  per-type weight byte (+0x2FD) to the running total at 0x8C2E9E84, and a new
  spawn is refused at the cap (0x8C1081BE). NPC objects are 0x3B8 B each,
  count at 0x8C2E9E34. [C formula, ? meaning of f]
- **Adaptive per-frame draw count** (task `DRWH`, 0x8C06FF20, registered at
  0x8C070100 with `DRWP`/`DRWO`):
  - Candidate humans are **insertion-sorted by |view depth|** (obj+76) into a
    50-entry list (0x8C06FCE0). Other objects go to a 100-entry list.
  - `N = (32000 µs − (frameTime − humanTime)) × humansDrawnLast / humanTime
    − 1`, minimum 6, where frameTime is the TMU-measured frame in µs
    (0x8C0C9EA0: TCNT0 delta / 12.5, kept in a 32-frame ring at 0x8C2E4710)
    and humanTime is this task's own TMU-measured cost (× 0.08, clamped to at
    least 10 µs, 0x8C07000C).
  - **The nearest N get "fade in" and the rest "fade out"**: CPAM counter via
    0x8C0D7740, steps of 40.
  - Anything with alpha > 0.001 is still drawn (0x8C06FAE0).
  - The population cap is also reset to `(N+1)·2` unless an area overrides it
    (`WSKB` → 49, `AR01` special). [C]
- NPC LOD: none in geometry (one 130–2,800-triangle model per type).
  Distance handling is fade and count-limit only. Animation-rate LOD was not
  investigated. [C / ?]
- Character models: typically 20–35 rigid parts, 1–2 meshes each, strips of
  4–7. [P]

## 5. Frame-level budgeting

- **TMU budget loops**: bulk NPC processing loops (e.g. 0x8C1056A0 over all
  NPC objects) read TCNT0 (0xFFD8000C) every 300 iterations. Past 15,000 µs
  (0x8C105808) they call 0x8C174A00 and 0x8C1E1520 (also called at end of
  frame, 0x8C0C9F82) and continue, so the long work is cooperative and
  time-sliced. The same pattern appears at 0x8C105C30, 0x8C105EFA,
  0x8C1065EC and 0x8C10EF0C. [C pattern, P purpose]
- End of frame (0x8C0C9EA0) samples the PVR TA registers
  (`TA_OL_BASE`…`TA_ISP_CURRENT`, 0xA05F8124–0xA05F8138) every other frame into
  0x8C293518–0x8C29352C (no peak). The peaks kept at 0x8C2E870C are the
  per-list byte counts, i.e. vertex-buffer high-water tracking. [C]
- Overall target: the 32,000 µs constant implies a 30 fps frame budget, with
  NPC count as the pressure valve. [P]

## Uncertainties / not done
- Meaning of model fields a/b (MAP04 has b = 3), strip flag bits 0x40/0x04/
  0x02/0x01, and the low mantissa flag bits in vertex x/u.
- The data source of f in the NPC cap (weather?).
- Who toggles the 32 map-block masks at runtime (event scripts or the camera).
- The fog table setup (left to the TA pass).
- Interior load trigger, inferred from the file layout and DOOR chunks; the
  call chain was not traced.
