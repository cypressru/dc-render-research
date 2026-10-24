# Dead or Alive 2 (DC, USA): system-level renderer notes

Static analysis only. Executable `1ST_READ.BIN` (1,815,864 B, base `0x8C010000`, ends `0x8C1CB538`). Addresses are
virtual. Confidence: **[C]** confirmed in code or data, **[L]** likely, **[?]** guess. Kamui field names come from the
Kamui 2 SDK and are [L]. Offsets and values are [C]. The per-vertex kernels are covered in a separate note.

## 0. Layout and libraries

| Range | Contents |
|---|---|
| `8C010000-8C0F8000` | game code (Tecmo). **It has no `ftrv`, no SQ address and no TA register access**: all geometry goes through NL |
| `8C0F8000-8C10E5C0` | **NL = "NAOMI LIBRARY Ver 0.9 AM R&D" (Oct 28 1999)**, "NLSPRITE Ver 0.2", "NLOBJPUT Ver 0.99" (Sega). Init, Kamui wrapper, matrix library (`8C0FCD00-8C0FEA80`), sprites, model renderer (`8C101542`) and the T&L/strip kernels (`8C101920-8C104000`, `8C107D10-8C10E5C0`; SHC runtime and sound glue in between). GBR = `0x8C2F4E00` (NL state) |
| `8C110EA0-8C1132C0` | second NL math/draw layer (SHC runtime before it, from `8C10E5C0`). The current matrix is kept in XMTRX: load `8C110F80` (about 450 game calls from 313 literal loads), store `8C110FA0`, `fsca` rotations `8C111780/7C0/800`. Also the lit-model entry points `8C111560/580/680/6A0` |
| `8C1132D0-8C11A000` | Shinobi 1.62 (start-up code at `8C1132D0`): syCache 1.52 (`8C117xxx`), gdFs, pd, bu, CRI ADX; more Shinobi (syMmu `8C123250`) and CRI ADX/mwRna sit in `8C11E000-8C12A000` |
| `8C11A000-8C11E000`, `8C12A000-8C133000` | **Kamui2 `kamui2 Ver 16,3,2,0 Build:Jul 23 1999`**. API at `8C11Axxx-8C11Dxxx`, state at `0x8C2F5E80` |
| `8C139000-8C13D000` | "KAMUI-Darkness" `kmdk Ver 1,3,0,0` and DMA helpers |
| `8C140000-` | data. File-name table (575 `c:/doa2/...` entries) at `8C151370`, with 67 more just before it from `8C151264`. Files are opened by index |

The 296 `0x10000000` and 174 `0xE0000000` hits are mostly data. Only 15 and 13 are `mov.l` literals in code. The
NL kernels build SQ addresses with `mov #-32; shll8; shll16`, so literal counts undercount the real SQ users.

## 1. Geometry to the PowerVR

### Kamui configuration [C]

NL builds `KMSYSTEMCONFIGSTRUCT` at **`0x8C2B6CE8`**. Defaults are set by `8C0F92F0`. The boot code `8C012474...8C0124A0`
then edits it, and NL calls **`kmSetSystemConfiguration` = `8C11B7A0`** (from `8C0F98DA`, followed by `trapa #65`
on failure). The setup has the same shape as Shenmue II's NL 0.8, but this is Kamui2, so the struct is bigger.

| off | value | meaning |
|---|---|---|
| +00 | 0x1F8 | dwSize |
| +04 | 0x100, then \|0x10 | flags. 0x10 = direct-transfer list enabled (`8C0F9380`) |
| +08/+0C | `8C2B6EE0` -> {`8C2B6EF4`, `8C2B6F14`}, 2 | 2 framebuffer surface descriptors |
| +14 | 0x800000 default; the game sets **0x3E0000** (or 0x300000) via `8C0F9370` (`8C012474`, `8C015C1C`) | texture memory size [L] |
| +18/+1C | 0x800 / 0x400 | texture structs / small-VQ structs [L] |
| +20/+24 | `8C2B6F7C` / `8C2E26C0` | texture work / pBufferDesc. `*pBufferDesc` = the per-list SQ pointer table, cached at `*8C2B6F34` |
| +28 | 2 | **nNumOfVertexBank = 2** |
| +2C | **`0xACE80000`** (`8C0F9500`: `0x8CE80000` \| P2) | vertex buffer |
| +30 | **0x180000** | size. The buffer ends exactly at `0x8D000000`: the top 1.5 MB of RAM |
| +34 | 1 | nPassDepth |
| +38 | \|= 0xA0 (`8C0F9F30` at boot) | pass flags [? meaning] |
| +44 | **0 = opaque** (`8C0F9440(0)`) | direct-transfer list |
| +48..+58 | **0, 16.7, 66.7, 16.7, 0 %** | OP, OMV, TR, TMV, PT shares |

The shares come from `8C0F9930(0, 0x10000, 0x40000, 0x10000)`, with PT = `*8C2B6EEC` = 0 (no caller sets it). The
size is computed in `8C0F9520` as sum x 4. Each bank therefore holds **OMV 128 KB, translucent 512 KB, TMV 128 KB**,
and nothing for punch-through.

Display (`8C012380` boot, `8C015B80` on cable change): `syCblCheck` (`8C1189E8`) picks NL mode 0 (VGA) or **mode 9
(NTSC) / 19 (PAL)**, called as `8C0F8DF0(mode, 0x80, vsync=1)`. The mode table `8C148914` (12 B: broadcast, KM mode,
w, h) gives KM mode `0x38` / `0x3A` = **640x480 non-interlaced framebuffer with flicker filter** (the `...NI640x480FF`
entries, [L] on the names). Every field shows a full 640x480 frame: **no field rendering**. The flags 0x80 ->
bpp-table index 0 = RGB565 [L]. Background plane: `8C0F9FA0` (3 vertices, PCW `0xE0000000` / `0xF0000000`) -> Kamui
`8C11CC60`.

### SQ submission [C]

- Opaque goes **straight into the TA FIFO** [L: it is the configured direct-transfer list]. OMV, TR and TMV go by SQ into the RAM banks, and Kamui DMAs them at end of
  pass. `kmEndPass` `8C11B5A0` -> `8C130760` loops over the 5 lists, appends the end-of-list by SQ (`8C13083A`,
  `8C1308AA`) and queues the buffered lists [L on the DMA ordering]. The ch2 code is `8C12D320` (queue, SB_C2DST
  `A05F6800`) and `8C139480` (CHCR2 `0x12C1`, DMAOR `0x8201`).
- The NL model renderer `8C101542` takes the list from **PCW bits 24-26 of each mesh header**. It indexes the list
  pointer table and reloads QACR0/1 = ptr>>24 **only when the list changes** (`8C101644-8C101662`). It writes
  `0xE0000000 | ptr & 0x3FFFFFF` and stores the advanced pointer back. The same idiom is used by the NL debug-text
  printer `8C0FB930` (opaque or translucent).
- **Each vertex's PCW word is its own SQ address**: `0xE0xxxxxx` reads as a vertex parameter. The last vertex of a strip
  gets `shar` of it = `0xF0xxxxxx` (end-of-strip). See `8C101A36-8C101A48`. This is the same trick as AM2's MT7 kernel
  in Shenmue II.
- **Polygon headers are pre-built in the model data** (PCW, ISP, TSP, TEX per mesh). NL ORs in global bits
  (`*8C2EF7E0` / `+4`) and patches the cull mode per strip from the strip flags, flipped for mirrored matrices
  (`8C101836-8C101852`). Intensity meshes get a 64 B header: face colour = material x light, offset colour = material x
  `8C1CA930` (`8C101760-8C101796`).
- **Fade**: if object alpha < 1 (`8C101604-8C101628`), PCW becomes translucent (bit 25 set, bit 26 cleared) and the TSP
  blend becomes SRC_ALPHA / INV_SRC_ALPHA.
- 2D: NLSPRITE `8C100430` (about 200 game call sites). It uses 40 B per-texture records with pre-built PCW/ISP/TSP words that
  are masked and patched per call.

### Lists actually used [C]

Census of every `.CHR` (all 86): mesh PCWs use **only list 0 (opaque) and list 2 (translucent)**. There is no
punch-through anywhere, which matches PT = 0 %.

**Modifier volumes = shadows** (OMV, list 1). NL `8C101430/450/470/490` -> `8C1014A0` builds header
`0x818C0000 | (flags & 0x30000)` and runs the model's geometry through `8C10D980` into list 1 (`@(4,listtab)`). The game
calls `8C101430` 11 times from 4 places (`8C0AE05E`, `8C0B88B4`, `8C0D445C`, `8C0D44D2`) after loading a projection matrix
(`8C0D4446-8C0D4452`). The variant with `r5 = -1` (`8C101450`) is reached only through the frame-skip patch list. **No
producer was found for TMV** (list 3), although it gets 16.7 % [?].

### Render to texture [C]

NL has a texture render target. `8C0FC3xx` creates a surface with Kamui `8C11C440` (type `0x901`: RGB565 rectangle
[L]). `8C0FC4F0` starts rendering into it. `8C0FC600` ends the pass (`kmEndPass`, Kamui `8C11B0C0(surface)`,
`kmEndScene`, `kmBeginScene`, `kmBeginPass`) and sets FB_X_CLIP/FB_Y_CLIP (`A05F8068/806C`) to the surface size. One
game module uses it (`8C0C28C4/8C0C2AE2`, `8C0C2E80/8C0C2FD6`, `8C0C3352/8C0C33EA`). Its purpose was not identified [?];
two of the four calls to the shadow driver `8C0D3DF0` (`8C0C29B8`, `8C0C33B8`) sit inside its passes.
NL framebuffer readback through `0xA5000000` (`8C0F9BE0`, `8C0F9C90`) has no callers.

### Frame structure and pacing [C]

The main loop is `8C0125EC-8C01279C`. NL end-of-frame `8C0F8A60` runs `kmEndPass` `8C11B5A0`, `kmRender` `8C11B140(0)`,
`kmEndScene` `8C11B740`, then **immediately `kmBeginScene` `8C11B380` + `kmBeginPass` `8C11B1E0`**. The game step
`8C012D7C` therefore builds frame N+1 while the PVR renders frame N from the other bank. Opaque streams straight into
the TA during the build.

1. `8C0F9B60` -> Kamui metrics `8C11C780` into `8C2E1F7C`. `*8C2E1F80` = **last PVR render time in µs**. Kamui keeps
   an 8-entry ring at `state+0x914`: TCNT0 at render start (`8C1310F6`, `8C13121E`), delta at the render-end interrupt
   (`8C1301E4`), x128/100.
2. `8C0F9D90` marks the NL µs timer (TMU0, Pφ/64, x1.28 at `8C2B6F60`; set up in `8C0F9AB0`).
3. Optional limiter: if `*8C1CB65C` is set (by script opcodes `8C01F6D4`, `8C02039E`), spin until 16000 µs have passed.
4. If the previous frame was not skipped: `late = elapsed / (vsync x 16000)`, then NL flush (render), then
   **if `(vsync + late) x 16000 < last PVR render time`: frame skip**.
5. Game update and draw build `8C012D7C`. Logic loops `vsync count` times per frame (`8C08E866` runs the update
   functions `*8C2B6F44` times).

**Frame skip by code patching [C].** `8C012A74` swaps the first 4 bytes of 11 draw entry points with `rts; nop`
(stored at `8C150398-8C1503C0`), with `ocbwb` (`8C111F00`) per patch and then ICI (`8C1177EE` via P2). The patched
entries are lit models `8C111560/580/680/6A0`, sprites `8C100430`, shadows `8C101430/450`, `8C103920/980`, `8C1040B0`
and debug print `8C0FBB30`. One full logic tick then runs with no drawing. The next iteration restores the code, skips
the render, and waits for the vblank counter `8C1CB8FC`. The counter is set by the callback `8C012A42`, registered with
`8C1046B0(1, ...)`. **Logic stays at 60 Hz and only the display drops a frame.** The trigger is PVR render time, not
CPU time.

- `kmSetWaitVsyncCount` = `8C11C740`, via NL `8C0F8FB0`. Boot uses 1 (60 fps). The script opcodes `8C01FACA` and
  `8C0218C2` can change it (cutscenes [L]). The other 7 callers pass 1.
- Fog: NL `8C0F8960` uploads a dirty 128-entry fog table (`8C2F4E80`, Kamui `8C11A388`). `8C0FBFE0` converts a float to
  the FOG_DENSITY format. These are applied from the main loop when the render-done callback `8C012BC0` has fired.

## 2. Cache

- **CCR = 0x105** (OCE \| CB \| ICE): `8C11868C` jumps through P2 to syCacheInit `8C117798` with `*0x8C14E084` = 0x105.
  That routine writes the value, then ICI and OCI. Other writes: startup `8C01000C` (`(CCR & 0x89AF) | ICI`), syMmu
  `8C123250` (ICI), shutdown `8C1186FA` (CCR = 0, OC address array cleared, CCR = ICI), and the syCache ICI/OCI helpers
  `8C1177EE`/`8C1177FA`. `8C117F74`, `8C11FE6C` and the range helpers only *read* CCR.ORA to size their flush loops.
- **ORA (OCRAM) and OIX are never enabled [C].** The only `0x7C000000` literal is syCache's 8 x 1 KB OCRAM page
  allocator `8C117FF8`, which has no callers. Nothing lives at `7C00xxxx`.
- **movca.l: none in real code** except the unreferenced syCache one-liner `8C117F3E`. The 16 game-range hits are
  data words (`0x0nC3`) in literal pools and tables.
- ocbi/ocbp/ocbwb, real uses:
  - NL `8C111E80` (ocbi range), `8C111EC0` (ocbp range), `8C111F00` (single `ocbwb`). syCache `8C117804...8C117ED4`.
    `8C11FF74...8C120112` (in the CRI ADX/mwRna range). syMmu `8C1232F0...8C1233C8`. Kamui `8C129ED8` (ocbwb before texture DMA, called
    from `8C12B192`).
  - The game calls `8C111E80` before buffers are filled by DMA (`8C08E068`, 0x26000 B; `8C08B612`). It calls
    `8C111EC0` after CPU-written texture data, before DMA. Example: `8C0D869C` repacks 0x20000 565 pixels in place
    to 4444 (`(b>>1)<<12 | (r>>1)<<8 | (g>>2)<<4 | 0xF`, with r = bits 15-11, g = 10-5, b = 4-0 of the source), sets
    format `0xD02`, then ocbp of 256 KB
    (`8C0D8728`).
  - **Self-modifying code**: the frame-skip patcher above (ocbwb + ICI).
  - The other ocb\* hits are data.
- Prefetch: `pref` is the SQ flush. The model walker also prefetches the next source block (`pref @r4` 48 bytes ahead,
  `8C101602`, `8C101848`). There is no I-cache trick beyond the code patching and running CCR code from P2.

## 3. Data formats

Parsers: `tools/chr.py` (models, `-o` per object), `tools/aux_formats.py` (APV/SUP). No game file is compressed:
models, morphs and VRAM blobs are raw and pre-swizzled (zlib would save about 55 % on CHR, 45 % on texture BIN and 37 % on APV, but only about 19 % on MOT).

**CHR = NLOBJPUT object file [C]** (characters, stages, effects `EFC0/1`, `FIX`):

- header `{0x18, objtab_off, textab_off, n_obj, n_tex, 0}`. objtab holds pointers **pre-linked** to `0x0C300000`
  (characters) or `0x0C400000` (stages, effects), so the loader relocates by the delta [L].
- texture table: 12 B `{u16 w, h, u16 fmt = PVRT pixel format | data type << 8, u32 addr}`. addr is an offset into the
  matching `.BIN` blob (base `0x0D200000` / `0x0D600000`). **Each `.BIN` is exactly the sum of its textures**: raw,
  pre-twiddled VRAM images uploaded as is.
- object: `u32 1, u32 flags (1/3/5), float sphere[4]`, then meshes.
- mesh: `PCW (bit 31), ISP, TSP, TEX` + `sphere[4]` + `mat[11]` + `u32 size` + strips. `mat[0]` = texture index. In the
  file, TEX holds format bits only, and the VQ entries' TSP size is half the table size, so both are patched at load
  [L]. `mat+4` (signed byte) = light type: 0, 1, 2, 5, -1 = unlit, -2/-3 = hooks `8C109000`/`8C109A80`. A type >0
  indexes a 512 B table at `8C2F046C + type<<9`. `mat[3..6]` = face ARGB, `mat[7..10]` = offset ARGB.
- strip: `u32 flags, u32 n`. Bit 4 = strip, else triangle list (n triangles, 3n records). Bit 7 = chained to the
  previous strip. Bits 0-1 = cull. Bits 3, 5, 6 select kernels. Vertex record: **32 B float `{x,y,z, nx,ny,nz, u,v}`,
  tagged by bit 0 of x = 1**, or an **8 B back-reference** `{tag, s32 rel}` to an earlier record (de-indexing). The
  walker tests `tst #1` (`8C101942`).
- Counts (all objects in the file; the run of 15-21 unlit `flags=3` hull objects, usually about 490 tris, excluded):

| file | objects | meshes | strips | inline verts | backrefs | tris |
|---|---|---|---|---|---|---|
| KAS00 (Kasumi) | 56 | 145 | 1,405 | 7,241 | 4,603 | 8,184 (+488) |
| HIK00 (Hayabusa) | 50 | 114 | 1,414 | 8,253 | 5,662 | 10,239 (+472) |
| 42 costumes | 42-59 (WBA00 29, YTI00 1) | 19-152 | | 4.6k-8.4k | | **6,011-10,739, avg 8,357** |
| STAGE03 | 239 | 429 | 3,790 | 21,058 | 12,014 | 23,942 |
| STAGE05 | 218 | 1,034 | 5,238 | 24,091 | 3,359 | 15,922 |
| STAGE20 | 251 | 1,582 | | 22,728 | | 12,293 |
| STAGE30-40 | 1 | 2 | 100 | 238 | | 200 (movie placeholders) |

  Stages hold 3k-28k tris (whole stage, all tiers). Effects: `EFC0` has 122 objects, 6,760 tris, 108 of 123 meshes
  translucent.
- **Textures (3,836 entries): VQ 2,497 (65 %)**, of which 1,009 have mipmaps. Twiddled 565/4444 make up most of the
  rest. **No palettised textures and no small VQ.** Stage textures are 88 % VQ (about half VQ with mipmaps); characters use VQ for large maps and
  twiddled for 32x32. Sizes: 128x128 1,407, 64x64 994, 32x32 651, 256x256 343. VRAM blobs: character `.BIN` 106-390 KB
  (avg 303), stage 32-760 KB (avg 569), `EFC0.BIN` 820 KB, `EFC1.BIN` 436 KB. With the 3.9 MB texture setting, 2
  fighters + stage + effects + HUD fit in about 2.5 MB [L].
- Load-time conversion: only the 565->4444 in-place pass above (pictures) [C]. Models stay float. The CPU writes
  morphs and welds into the RAM copy of the CHR.

**Per-costume side files [C structure / L meaning]:**

- **APV = morph targets.** 9 sections. Each has u32 vertex offsets **relative to a CHR object** (verified: KAS00
  section 0 hits head object 4 at 0x56E8, 0x5728, ...), base positions, and N blocks of small deltas. KAS00: face
  303 verts x 4 and 345 x 18 position blocks, base included (lip and expression sets, debug `Eye Chng`, `MorfStop`),
  torso 256 (base positions only, no targets), and four 518-530-vertex sets x 12-13 that probably match the
  545-vertex hands (hand poses [L]). Most files are 285-500 KB; MAM00, WBA00 and YTI00 have empty 32 B APVs.
- **SUP = joint welds.** 7-14 sections per file (KAS00: 10), each `{u32 header size 0x34, u8 node_a, u8 node_b, u16 n}`,
  about 128 B of matrix/float data, then 28 B records `{u32 CHR vertex offset, pos[3], nrm[3]}`. KAS00 node pairs:
  1-0, 0-2, 3-7, 4-8, 7-6, 6-2, 9-13, 10-14, 13-12, 12-2, with 10-40 vertices each (3-44 across all files). These are
  probably seam vertices re-posed by the neighbour bone, i.e. rigid two-bone skinning by overwrite; the code that
  applies them was not found. **No per-vertex
  weights exist anywhere.**
- **ACS** (`XXX_Ann.ACS`, 41 files for 42 costumes, none for YTI00, 46-7,738 B): (type, offset) list (types 0-2, 4-9 and
  0xFC-0xFE, 0xFF = end) + float
  boxes and limits. Probably hair/cloth chain or collision setup [?]. **`redu / rest / eff` debug strings** (`8C145718`)
  hint at spring reduction and restitution [?].
- `NAME.MOT`, plus `N_`/`C_`/`M_`/`W_` variants and `COMON.MOT`: an offset table to motions. Each motion = 44 channel
  tracks of packed variable-length keys, data placed before its channel table. gzip saves only about 19 %.
- `Snn_DAT.BIN`: 2-4 u16 grids (bit 15 flag + 15-bit value) = stage floor, wall or danger map [L]. `KASUMI.BIN` etc. =
  move/command tables [?]. `*_C?.BIN`, `DANGSET`, `WATER` = DTPK sound banks. `AICADRV.BIN` = ARM7 driver.
- Memory, per fighter: CHR 0.2-0.33 MB + MOT about 1.0-1.2 MB + APV about 0.4 MB + move-table BIN (`KASUMI.BIN` etc.) about 0.08 MB + texture BIN 0.1-0.4 MB. The
  stage CHR is up to 1 MB. Fixed-address pools [?]. The vertex banks take `0x8CE80000-0x8D000000`.

## 4. Frame level

- **No polygon counter or profiler strings.** The only metric used is Kamui's PVR render time (frame-skip trigger) and
  the NL µs timer. The pause/debug menu code is compiled in (`8C0193DA-8C01B47C`, table `8C150EBE`): `Camera Move`,
  `Light Move`, `Fog Chng`, `Stg Undulate`, `Char Pos`, `Neck Chng`, `Eye Chng`, `Plural Light`, `Stg Bank Chng`,
  `MorfStop`, `CHRDISP`, `Hit Area`, light editors (`amb_r = %f`, `CONTE MLT LIGHT COMMAND ERROR!`). Reachability not
  checked [?].
- **No LOD [C for data, L overall]**: no file holds alternate-resolution copies of an object, and nothing in NL selects
  by distance.
- **Culling** is per mesh in NL: the bounding sphere is transformed (`ftrv`) and tested against near and 4 side planes
  (`8C101708-8C10174E`, constants `8C1CA8D4..E0`). A culled mesh is skipped by its `size`. Meshes whose sphere crosses
  the near plane set a bit that routes their strips to the clipping kernels `8C101C80`/`8C102120` instead of
  `8C101920`/`8C102320` (`8C101870`, `8C1018B8`). The object sphere in the CHR header is not used by NL [?].
- **Multi-tier stages**: each stage is one CHR with all tiers. The game keeps name tables `{u16 object index, u16 flag,
  char *name}`: e.g. `8C19DC40` (116 entries: `ag_buila1_top/_mid/_und`, `ag_kisi*`, `ag_soko*`), `8C1A7E24`
  (`bl_flr_a_1`...), plus `gl2_*` (ice), `sn2_*`, `ag2_2f..6f` (floors). The stage module walks them (`8C08E478` ->
  NL `8C104240`, which bakes the object under a fixed matrix via `8C10D120` and sets object flag 0x20 [L]). The fall
  transition just keeps drawing the same CHR with a scripted camera [?]. `Stg Bank Chng` suggests bank-switched stage
  sets.
- **Effects budget**: effects are ordinary NL objects (`EFC0/EFC1/FIX.CHR`, mostly translucent). The translucent bank
  is 512 KB, so with 32-64 B vertices plus headers about 8-16k translucent vertices per frame [L]. Opaque is
  unbudgeted (direct). Shadows draw the model into the 128 KB OMV bank.

## Open items

- The purpose of the render-to-texture module (`8C0C2848...`) and of the 15-21 `flags=3` hull objects per costume (probably
  the shadow volumes).
- How each SUP/APV section maps to skeleton nodes, ACS semantics, and the MOT key encoding.
- The real per-frame triangle count. It needs runtime state for which objects and tiers are drawn.
