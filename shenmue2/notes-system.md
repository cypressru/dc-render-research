# Shenmue II (DC, Japan, disc 1): system-level renderer notes

Static analysis only of `1ST_READ.BIN` (3,179,576 B, base `0x8C010000`). Addresses are virtual.
Confidence: **[C]** confirmed in code/data, **[L]** likely, **[?]** guess. Field names for Kamui structs are
borrowed from the Kamui 2 SDK and are **[L]** at best; offsets and values are **[C]**.

## 0. Layout and libraries

| Range | Contents |
|---|---|
| `8C010000-8C1C8000` | game code (AM2). Also the hand-written T&L kernels (other notes) |
| `8C1D6000-8C1EA000` | **NL = "NAOMI LIBRARY Ver 0.8 AM R&D" (Apr 2000)** plus "NLOBJPUT Ver 0.99" (Feb 2001): AM2's own render/math layer between the game and Kamui. GBR is fixed at `0x8C2BDB80` (NL state, set in `8C1E193C`) |
| `8C1EA000-8C206000` | Shinobi pieces (`syCache Ver 2.01`, `syMmu`, `sySq`, `syHw ..._am2c`, Feb 2001), gd, pd, bu |
| `8C206000-8C21B000` | **Kamui `KAMUI Ver 1.11.0.1 Build:Sep 7 2000`**. Main state at `0x8C317ED0`, per-list pointer table at `*0x8C317E44` |
| `8C220000-8C2238xx` | libc/libgcc |
| `8C224000-` | data |

Other strings: `libsnd 1.05e`, `ADXF 5.78`, `ADXT 5.99L2`, `mwRna 2.01`/`mwNm 2.00` (Sofdec). The Kamui profile keys are the
same as in Soulcalibur (`RENDER VSYNCCount RegionSize ObjListSize ISPParamSize TSPParamSize VertexBuffer BufferBase BufferSize
PoolingTAStatus RenderTimeOut VertexTimeOut VSYNCTimeOut`, `HARDWARE EnableTexture16MB`). Kamui's built-in defaults are in
`8C2110E0` [C]: RegionSize 0x6000, ObjListSize 0x7A000, ISP/TSP 0x180000, VertexBuffer BufferBase `0xACC00000`, BufferSize
0x400000, timeouts 10. The second TA parameter set is placed at +0x400000, giving one set per 4 MB VRAM half (`8C21120A` loop).

**Export table `8C053810-8C053CFF` [C].** About 250 function pointers into the game, NL, Kamui and syCache. It is the ABI
for code loaded at run time (see the cache section). For example, it holds `8C209780`, `8C20DAC0`, `8C1E2020`, `8C053D00`
(syCacheInit-like) and `8C053E64` (ocbp range).

## 1. Getting geometry to the PowerVR

### Kamui configuration [C]

NL builds the `KMSYSTEMCONFIGSTRUCT` at **`0x8C30866C`** (`8C1E1F60`, called from NL init `8C1E18E0`):

| off | value | meaning |
|---|---|---|
| +00 | 0x60 | dwSize |
| +04 | 0, then \|0x10 (see below) | flags |
| +08 | `8C30864C` -> {`8C2BDC3C`, `8C2BDC64`} | 2 framebuffer surface descriptors |
| +0C | 2 | nNumOfFrameBuffer |
| +10 | 640 (0x280) | probably nNumOfTextureStruct [L] (`8C1E2180` can reset it to 640 and also set +14/+18) |
| +14, +18 | 0, 0 | |
| +1C | 0x200000, then per area | not identified [?]. Soulcalibur uses 0x135400 here |
| +20 | `0x8C309068` | pBufferDesc (KMVERTEXBUFFDESC, also passed to every kmSetVertex in NL) |
| +24 | `0xACC00000` default; the game sets **`0xACEC0000`** | vertex buffer (P2, uncached) |
| +28 | 0x100000, then computed | vertex buffer size |
| +2C..+3C | floats 70, 5, 25, 0, 0 (defaults) | % per list: OP, OMV, TR, TMV, PT |
| +5C | 0 -> **0x20** | direct-transfer list (0x20\|list: 0x20 = opaque, 0x22 = translucent, 0x24 = punch-through) |

`kmSetSystemConfiguration` = **`8C20C5A0`**, called from `8C1E2448` (followed by `trapa #65` on failure). The setup has two
branches, chosen by `8C308668`, which is set when `*0xA05F689C` (SB_SBREV?) > 7 [? on the meaning]. In one branch the struct
is edited and Kamui is configured once. In the other, Kamui's run-time setters are called (`8C20C440`(flag, directlist),
`8C20BD20`, `8C20A1E0`, `8C2089A0`).

Game boot `8C0CA180` -> NL init `8C1E1B40`(mode 0/1/9 from the cable check `8C1F8120`, flags 0x80, vsync count 1) ->
`8C1E2020` (**opaque becomes the direct list**: +5C = 0x20, flags \|= 0x10, NL mode = 2) -> `8C0C9640` per area.

**Per-area budgets come from a table on disc [C].** `MISC/AREATBL.BIN` is an SH4 stub. When run, it returns a pointer to
132 records of 32 bytes: `char id[4]` ('*' is a wildcard, as in `WRG*`), then `u32 omv, trans, pt, x` and 3 floats. The
lookup is `8C057640`. The loader is `8C057550` (`misc/areatbl.bin`): it flushes the cache, then calls the stub. `8C0C9640`
uses the record as follows:

- vertex buffer base `0x8CEC0000` (`8C1E2240` ORs in P2)
- +1C = x/4 (`8C1E2000`)
- list sizes (`8C1E24C0` -> `8C1E2280`): OP 0 (direct), OMV = omv/4, TR = trans/4, TMV 0, PT = pt/4 (PT via `8C1E2220`). The
  size is the sum; it is doubled only in NL mode 3 (no direct list), and the percentages are recomputed in floats.

Ranges across all areas: omv 0x10000-0x50000, trans 0x50000-0x120000, pt 0x10000-0xE0000, x 0x200000-0x5D0000. The
floats are 20-800 / 10-400 / 10-90: the farA/farB/farC cull distances (setters `8C06E240/260/280`, see `notes-world.md`).
The common record (`QA00`) is 0x30000/0xD0000/0x40000/0x380000, which with opaque direct (NL mode 2) gives a
**320 KB RAM vertex buffer at `0x8CEC0000-0x8CF10000`**.

### Store-queue path [C]

Same idiom as Soulcalibur. The game kernels (e.g. `8C039000`, `8C039120`) save the per-list SQ pointers in GBR slots
(`@(72/80/88,gbr)`, saved per list at `8C2BDBC8/D0/D8`). They take the destination from `*(*0x8C317E44)[list]`, write
QACR0 = QACR1 = ptr>>24, and stream 32-byte blocks via `pref`. Opaque therefore goes **straight into the TA FIFO**
(0x10000000). OMV, TR and PT go by SQ to the RAM buffer, and Kamui DMAs them (ch2) at end of pass. Init leaves
QACR = 0x0C (`8C1E1A46`).

NL `8C1E1C80`/`8C1E1CC0` snapshot the 5 list pointers at frame start and return the bytes written per list.

Slow path: NL immediate-mode helpers (`8C1DF220...8C1E0100`) build each vertex on the stack and call Kamui
`8C20B0A0`/`8C20BA00`/`8C20BAA0` (strip-head / start / set-vertex style [L]) with PCW `0xE0000000`/`0xF0000000`. These
are used for 2D and simple shapes. Most of the 40 `0xE0000000` and 108 `0x10000000` literal loads are PCW/TCW constants,
not addresses.

### Polygon headers [C/L]

Headers are pre-built in the model data and copied per mesh, with a few bits patched on the fly. Kernel
`8C0391CC`/`8C03918A` copies 4 words from the mesh, clears PCW bits 4-5 (colour type -> packed), and has a variant that
forces word1 \|= 0x02000000 and TSP = (TSP & 0x03FFFFFF) \| 0x941000C0 (SRC_ALPHA/INV_SRC_ALPHA + modulate-alpha). That
is the per-object fade/translucency switch [L]. NL keeps two strip contexts (`8C309248`, `8C308954`) built with Kamui
`8C20A7E0`.

### Modifier volumes / shadows [C]

Module `8C0FEE00-8C100040` builds volumes into list 1 (OMV, buffered in RAM, QACR = 12):

- header `0x81000000`
- triangles: 3 vertices x (x*w, y*w, w), PCW 0xFFFFFFFF; `8C0FFE60` is one triangle, `8C0FFF40` two, `8C0FFF80` three
- close `8C0FFFE0`: `0x81000040` + ISP `0x20000000` (last polygon, inside-volume mode)

The pointer is written back into the Kamui list table. Strings: `Shadow`, `ShadowOff`, `CutMvShadow`. The OMV share is
5 % by default and 16-80 KB per area (record omv/4).

### Effects

The cutscene/event data uses 26 chunk tags (table `8C25AD4C`, parser `8C15D5C0`, handlers `8C15B5C0...`):
`STGC LGHC CHDS RFBD EYES HAND CLTH OSGC BLUR WAVE FACX FADE MBTK SMKC HAPA PRTS AFOG FOBJ SHDW FCLP FILT LENS DOOR LGHS
WRST FPLU`. They cover blur, wave, fade, fog, shadows, filter and lens flare (`LENSFLAR.BIN`). Other strings: `ObjBlur`,
`fade_out`, `FOG BACK %`.

NL `8C1E2700`/`8C1E27A0` read the framebuffer back through `0xA5000000`, sized by bpp, probably as a capture source for
transitions or thumbnails [L]. `8C1E0AC0` reads a texture back from VRAM through `0xA4000000`. **No render-to-texture
use was found in game code** [?]. Kamui's FB_W_SOF1 code (`8C2170EA`) was not traced to a game caller.

### Frame structure and pacing [C]

- vblank callback `8C0C9E20` increments `0x8C02015C`; it is registered via `8C0FEC20`
- render-end callback `8C0C9E60` (registered via NL `8C1E1E80` -> Kamui `8C20D900`): **PVR render time** =
  TMU0 TCNT0 delta since the render start saved at `8C29353C` -> stored at `8C293538`
- **frame end `8C0C9EA0`** (a task registered by `8C0CA0A0`):
  1. frame time = (prev TCNT0 - TCNT0)/12.5 -> 32-entry float history `8C2E4710`, current value at `8C020174`
  2. `8C053F78`: **busy-wait** until vblank counter >= last + interval - 1
  3. on alternate frames, snapshot TA registers `A05F8124..8138` (OL/ISP base and limit, NEXT_OPB, ITP_CURRENT)
  4. per-list bytes used (`8C1E1CC0`) and high-water marks at `8C2E870C` (reset per area); `8C1E26C0` -> `8C293530`/max `8C293534`
  5. NL render `8C1E1520` = Kamui `8C2091A0` (end of pass + render, flag `8C30C710` set around it) + `8C208C20`
  6. record render start, `8C1E1C80` (list snapshot), vblank count -> `8C2934F8`
  7. soft-reset check `8C0C9D40` (combo held > 5 frames -> BIOS)
- `8C0C9DE0`(fps): interval = 60/fps -> `8C020154`. **Boot calls it with 30** (`8C0CA126`), so the main game targets
  **30 fps** on 2 vblanks. `8C07FC0A` forces interval 1 (60 Hz) for some mode [? which]. Kamui waits 1 more vsync
  (`8C20EEE0` kmSetWaitVsyncCount(1) from NL init) [L].
- There is no frame skip: a slow frame simply takes more vblanks, and the wait is relative to the last frame.
- CPU/PVR overlap is Kamui's: two vertex banks and two TA parameter sets in separate 4 MB VRAM halves [L]. Opaque is
  streamed into the TA while the CPU builds the frame.

## 2. Cache

CCR values written [C]:

| site | value | purpose |
|---|---|---|
| `8C010100` (startup) | 0x808 | ICI\|OCI, caches off |
| `8C053D00` (game copy of syCacheInit, P2) | flush per ORA/OIX, then 0x808, then arg | |
| called from `8C0CA250`/`8C0CA4BA` | **0x105** | ICE\|CB\|OCE |
| `8C05E106`, `8C05E1AC` | 0 | shutdown / exit to BIOS |
| `8C04FC00` | writes back every valid OC line (OC address array `F4000000`, ocbp per line), then **CCR = 0** | |
| `8C04FC68` | CCR \|= arg (always 0x105), run from P2 | |
| `8C048460` (unreferenced) | `8C0483AC` clears the OC address array (half of it if ORA) | |
| `8C1F98C0...8C1F9E54`, `8C1FBC20` (Shinobi syCache) | ICI/OCI/flush helpers | |
| `8C206280` (Kamui) | ICI | |

The `8C04FC00` + `8C04FC68(0x105)` pair is called (with interrupts masked) at:

- **code/data overlay loads**: `8C05757C`/`8C0575CE` load `misc/areatbl.bin` ('AREA') and a 'SYSP' pack, flush, then
  `jsr` into the loaded code
- `8C122CC4` before dispatching through table `8C0200B0` (the arcade sub-games HANGON/OUTRUN/BURNER/HARRIER [L])
- `8C05C5CA`, `8C080C14`, `8C0B3F92`, `8C0B4410`, `8C12240A`, `8C155D4E` around display-mode changes (`8C20E0A0`
  kmSetDisplayMode + `8C20EC20`)

This is the "cache trick": caches are disabled and re-enabled around code loads and video mode switches. **The re-enable
does not set ICI**, so I-cache coherency relies on the earlier off/on cycle [? possible latent bug].

- **ORA (OCRAM) and OIX are never enabled [C].** The only `0x7C000000` literal is Shinobi's OCRAM page allocator
  (`8C1F9F8C`, 8 x 1 KB pages), which has no callers.
- **movca.l: no real use in game or NL code [C].** All 20 hits except `8C1FA450` (an unreferenced Shinobi helper) are
  data mis-disassembled.
- **ocbi/ocbp/ocbwb** are used only for DMA coherency:
  - game range helpers `8C053E3E` (ocbi), `8C053E64` (ocbp), `8C053EB0` (ocbwb), by line count
  - `8C04848A`: ocbi range, or the address-array method for >= 192 KB; used by `8C03D420`/`8C03D6A8`
  - **texture upload**: `8C177820`/`8C177880` purge (ocbp) w*h*2 bytes of a GBIX/PVRT image before the DMA
  - Kamui `8C2178C0` -> `8C21A2AE` (ocbwb per 32 B before texture DMA)
  - the remaining 0x8C11-0x8C19 hits are data
- **Prefetch:** `pref` serves as the SQ flush and also touches the destination ahead (`pref @r12` after each 32-byte
  block). Source data is read sequentially.
- **No I-cache tricks or code relocation to special addresses** were found beyond running CCR code from P2 (`|0xA0000000`).

## 3. Textures

Disc scan of every PVRT header in every file (GZ unpacked): **23,745 textures, 9,860 distinct by content** [C].

- pixel format: RGB565 18,388, ARGB4444 4,155, ARGB1555 1,195, **BUMP 7**
- data type: **VQ 17,380 (73 %)**, twiddled 4,344, twiddled-rectangle 1,995, rectangle 9, twiddled+mips 4, VQ+mips 13
- **mipmaps: 17 of 23,745** (14 distinct)
- palettised: 0; small VQ: 0
- sizes: 128x128 9,241, 64x64 8,071, 256x256 1,984, 32x32 1,424, 64x128 1,309, 512x512 407

(These are counts of headers; the same texture can appear in several packs. Distinct textures are 62 % VQ.)

Upload goes through Kamui `8C2179A0` (about 20 call sites inside Kamui's texture API). If the data is aligned it is DMA'd
on ch2 to the TA texture path `0x11000000` (queue `8C214B80`, SAR2/DMATCR2/CHCR2, SB_C2DST). Otherwise the CPU copies
it to `0xA4000000` with 64-bit `fmov` (`8C21A280`). YUV (movies) uses `0x10800000` (Kamui `8C206424`, `8C20F654`).

VRAM budget: Kamui texture manager stats sit in NL block `0x8C308554` (`8C1E2620` -> Kamui `8C214520`). The debug page
prints `FreeTexture : %d` and `MaxBlockSize : %d`. The 2 x 4 MB TA parameter split leaves the rest for textures [L].
Per-area streaming policy: see `notes-world.md`.

## 4. Debug / profiler

- **Debug pages `8C0ADB80`** (pages selected with pad bit 0x400 at `8C2EA030`, printed by NL `8C1E4220`/`8C1E4120`). No
  direct reference was found; it may be called from a debug-only table [?]. The pages show:
  - `Max/Rel/Min : 0x%x`
  - `ITPBase/ITPLimit/ITPCurrent`, `OBJBase/OBJLimit` (from the TA register snapshot `8C293518..2C`)
  - `IVBS Opaque/OpaqueM/Trans/TransM/Punch : 0x%x` (this frame's per-list bytes)
  - `MVBS ...` (high-water marks)
  - `FreeTexture`, `MaxBlockSize`, `Heap Rest/Max/Waste`
- The frame-time ring (`8C2E4710`), render-time (`8C293538`) and list high-water marks are kept in the shipping build.
- `--- ADDRESS CHECKER TRAP ---` plus register dump: syExtChk (Shinobi).
- No polygon counter strings were found. Per-list byte counts take that role.
