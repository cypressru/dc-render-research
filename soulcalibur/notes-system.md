# Soulcalibur (DC, USA): system-level renderer notes

Static analysis only. Executable `1ST_READ.BIN` (3,679,460 B, base `0x8C010000`). Addresses are virtual.
Confidence: **[C]** confirmed in code/data, **[L]** likely, **[?]** guess.

## 0. Binary layout and libraries

| Range | Contents |
|---|---|
| `8C010000-8C103000` | game code (Namco) |
| `8C103000-8C1F0000` | strings/data (move names, bios, stage-object names) |
| `8C1F0000-8C21A000` | non-SDK library code (math etc.; no SQ/TA access; code at about `8C1F2000-8C20D000`) [L] |
| `8C21A000-8C246000` | Shinobi 1.43 + Kamui 1.06 + syCache etc. |

Version strings: `KAMUI Ver 1.06 Build:Feb 25 1999` (file `0x236765`), `Shinobi Ver 1.43 Build:Jul 23 1999`,
`syCache Ver 1.52 Build:Jul 22 1999`, `Ninja Ver 01000086 Build:Apr 09 1999`, `sd Ver 1.00.18`, `gdFs Ver 1.07`.
Kamui config keys near `0x2366b0`: `RENDER VSYNCCount RegionSize ObjListSize ISPParamSize TSPParamSize VertexBuffer BufferBase BufferSize PoolingTAStatus RenderTimeOut VertexTimeOut VSYNCTimeOut`, `HARDWARE EnableTexture16MB`.

## 1. Geometry path to the PowerVR

**The 617 count for 0x10000000 is noise.** Aligned words: 171, mostly data tables. `mov.l` literal loads: 3 in game code, 21 in Kamui.
None of the 3 game sites writes to the TA. `8C07E230` builds a TCW (`(vram>>3)&0x1FFFFF | 0x10000000`, format 2 = ARGB4444). The other two are flag tests.

**Game code writes TA parameters by store queue itself, not through kmSetVertex [C].**
About 60-80 game routines (depending on how function boundaries are drawn) load `0xE0000000` (113 literals) and write QACR0/QACR1 (96 literals). Pattern, e.g. `8C03AF28`, `8C06F8A4`, `8C0870D8`:
```
ptr  = listptr[list]               ; table = *(0x8C266C10+0x6F4) = KMVERTEXBUFFDESC @8C267304
QACR0=QACR1 = ptr>>24              ; area bits come from the destination itself
sq   = 0xE0000000 | (ptr & 0x3FFFFFF)
... 32-byte header/vertex, pref @sq ...
listptr[list] = (ptr & 0xFC000000) + (sq & 0x3FFFFFF)   ; write back (8C03B0EE)
```
One kernel serves two kinds of destination. If the list pointer is `0x10000000` (TA FIFO), QACR area is 4 and the data goes **directly to the TA**. If it is a RAM vertex buffer (`0x8Cxxxxxx`, or the uncached `0xACxxxxxx` alias), QACR area is 3 and the SQ burst-writes RAM.
Kamui stores `0x10000000` into the direct list's current pointer at `8C222A9C` (`*(*0x8C34E404) = 0x10000000`).

**Kamui setup (game `8C041754`, struct at `0x8C266C10+0x694`, passed to kmSetSystemConfiguration `8C228F00`) [C values / L field names]:**
dwSize=0x60, flags=0x11, 2 framebuffers, `+0x6B4` pBufferDesc=`8C267304`, `+0x6B8` vertex buffer = uncached `A0xxxxxx` (32-aligned), `+0x6BC` 0x34000 (x 4 = 0xD0000, so apparently the buffer size in 32-bit words), `+0x6B0` 0x135400.
The caller reserves `base+0xD0000` (832 KB) for the buffer.
Per-list buffer shares (floats `+0x6C0..+0x6D0`): **opaque 0 %, opaque modvol 35 %, translucent 60 %, translucent modvol 0 %, punch-through 5 %**.
Opaque gets 0 %, which matches the Kamui sample idiom `nDirectTransferList = KM_OPAQUE_POLYGON`. Opaque is streamed straight into the TA while the frame is built. Everything else is pooled in RAM.

**Flush (kmRender-like, `8C2246A0`) [C]:** if the direct mode bit 0x20 of `*8C379EE4` is set, QACR is set to 0x10 and an end-of-list for the direct list (4 words from `8C245F40`) is sent by SQ (`8C224712`).
Then `8C2245A0` loops over lists 0..4 in hardware order (opaque, OMV, translucent, TMV, punch-through). It skips the direct list and empty lists. Each buffered list goes by DMA ch2 to `0x10000000` through the queued DMA helper `8C237C68`.
For the modvol lists, when the flag at `8C379EF8` is 1, it first sends a header block (pointer `8C379EFC`, size from `8C379F00`, list type patched into bits 24-26, `8C2245EE`).
Raw DMAC programming is at `8C2380B6`: SAR2=src, TCR2=len/32, CHCR2=`0x12C1`, `SB_C2DST=0x10000000`, C2LEN, C2ST=1.
Banked buffers: the bank index is at `8C379E20` and per-list ptr/len arrays are at `8C379E44`/`8C379E94`. That gives CPU/TA overlap: the opaque list for frame N+1 goes to the TA while the previous frame's lists are rendered from the other bank [L].
Textures use the same DMA queue to `0x11000000+off` (`8C23C480`), with a CPU fallback to `0xA4000000` for unaligned data. YUV goes to `0x10800000` (`8C22625A`, movies/pictures).

**Main loop `8C031420` [C]:** `8C03E9C0` (pad) → `8C031800` (game update, <0 exits) → `8C03ED00` → Kamui `8C222D20` → game draw `8C02014C` → Kamui `8C224BE0` → flush `8C2246A0` → `8C063040` → loop.
There is no game-side vsync wait or frame-skip logic. Pacing is left to Kamui (flags=0x11; bit 0x10 makes `8C2246A0` flush immediately instead of deferring to the vsync handler, see `8C228FD2` / `8C2246C2`) [L].
The 57 calls to `8C220060` (reads TMU TCNT2 `FFD80024`) use it as a cheap random source (results masked; AI at `8C09EAA8`, and effect code), not profiling: no start/stop pairs were seen [L].

**Single pass [?]:** no evidence of multi-pass or render-to-texture use in game code. Not searched exhaustively.

## 2. Cache

- CCR writes: startup `8C01000C` does `CCR = (CCR & 0x89AF) | ICI`. Kamui/Shinobi init `8C220504` → syCache `8C2330BC` with **CCR = 0x105** (OCE|CB|ICE; data at `8C2459E8`), then ICI and OCI. `8C220572` (reached only from the shutdown path `8C0C3AA8` -> `8C220526`) disables caches, clears the OC address array, sets ICI and leaves CCR = 0. `8C22E514`, `8C233112` and `8C23311E` only OR in ICI/OCI. The other CCR refs (`8C2331BC`, `8C233410`, `8C233664`, `8C233898`) only *read* ORA for flush-range routines. **ORA and OIX are off [C].**
- OCRAM: the only `0x7C000000` literal is in syCacheAllocCacheRAM-style `8C23391C` (8 x 1 KB pages, map at `8C34DD24`). It has **no callers**. The other `7Cxxxxxx` literals are data. **OCRAM unused [C].**
- movca.l (real ones): game `8C03A9B8/9F2/A58`, `8C03C94A`, `8C03CA18`, `8C03CBCC` are ftrv transform loops. They `movca.l` at each 32-byte boundary of the output so a line is allocated without a read, then store 16-byte records (x',y',z', raw tag word). Two vertices per line. Exception: in `8C03C920` the test is made on entry+12 (after `add #12`), which is never 32-byte aligned, so `8C03C94A` never runs. The only other real ones are 2 in syCache (`8C233862`, `8C2339F4`); the remaining 121 of the 129 hits (`8C11AD66-8C20B010`) are data mis-disassembled.
- ocbi/ocbp/ocbwb: **none in real game code** (the game-range hits are literal-pool noise). They are all in syCache range-flush helpers (`8C233180..8C2337F8`), plus Kamui `8C22E5AC..63C` (ocbp before DMA) and `8C23C04E` (ocbwb before texture DMA).
- Prefetch: `pref` is used both as the SQ flush and on source data in the game kernels. No I-cache tricks found (only ICI on init and code load).

## 3. Disc data

Container `olnk` (`u32 n, 'olnk', hdrsize, total`, then (off,size) pairs relative to hdr end). Inner packs: `u32 n, hdrsize, u32 end_off[n]`.
**LZ compression, decoder at `8C0EE76C` [C]:** flag byte, LSB first, 1 = literal, with a sentinel bit (stop when flag==1). Flag 0xFF means 7 raw bytes; 0 means end.
A reference is a big-endian u16: `len = ((v>>11)-1 &31)+1`, `dist = ((v-1)&0x7FF)+1`. Decoder: `tools/lz.py` (a port of 8C0EE76C), verified on STAGE.DAT stage 0 (71232 -> 124064 bytes).

- `STAGE.DAT` (23 stages): [A] inner pack of TIM textures, [B] pack: entry0 LZ geometry/scene (stage 0: 71 KB → 124 KB), entries 1..n raw **0x20000-byte 16bpp texture pages** (256x256; 9-15 per stage, stage 13 only 2; stages are about 1.4-2.3 MB, stage 13 0.34 MB).
- `HUMAN.DAT` (210 entries, 78 MB): per model, LZ skeleton+mesh plus four raw 0x20000 pages, SOSB voice bank, motion packs (`mot%03x`).
  Skeleton nodes are 32 B with s16 2.14 fixed rotation (`0x3FFF`=1). Mesh vertices are **float xyz (pre-multiplied by the bone weight) + w = the weight, whose low 12 mantissa bits carry the vertex index** (`0x3F800000|i` for a full-weight vertex; model 0 also has e.g. `0x3F008xxx`). That is ftrv-ready and matches the index extraction in `8C03C920` (`mov.w @(12,r5)`, `shld 4`, `and 0xFFF0`) [C].
- Stage mesh records: `u16 idx, u16 idx|0x8000 (strip end), u16 V, u16 U` (one little-endian u32 with U in the high half, copied unchanged into the TA UV16 word), where U/V are **upper halves of floats, i.e. the PVR UV16 format** [C]. They come after 4-byte strip headers (`0x1A,0x0400` as u16s in stage 0). Not pre-built PCWs: game kernels assemble headers from per-mesh templates (`8C03AF36..AF54` copies 4 words, ORs TSP).
- Textures: real **PlayStation TIMs** (magic 0x10, flags 8/9 = 4/8bpp CLUT; stage TIMs use 8 and 0x48 and are mostly LZ-compressed) in `VCSEL`, `HOPEN`, stage [A] and CINIT (one). Debug strings: `"TIM8! x=%d y=%d coltype=%x"`, `"TIM4! ..."`, `"ARGB1555! ..."`.
  They are uploaded as PVR palettized: TCW `0x28000000|(pal<<21)` (4bpp) at `8C05DB42` and 9 other sites, plus 4 sites with `0x30000000` (8bpp). GBIX/PVRT appear only for UI (1555 twiddled), YUV422 pictures (CINIT/HOPEN), and JPEG for the gallery. **No VQ anywhere** (no PVRT data type 3/4).
  Page manager: `"I_CreateTextureSurfacePageSet"`, `"Free Texture Page = %d/%d"`, `"(8192byte*31)"`, `"I_ScrollTexture : ISCR_MAX_TEXCELL"` (texture scrolling for water etc.).
- `GBGMxxL/R.P16/P08/P04`: stereo BGM as split L/R streams. `HOPEN.DAT`: 92 opening-scene model packs (the opening is real-time and editable, see "OPENING DIRECTION").

## 4. Frame level

- **Shadows are modifier volumes [C]:** the fighter shadow `8C03DA98` takes list pointer #1 (OMV), writes PCW `0x81800031` and ISP `0x20000000` by SQ, then emits the volume via `8C03CD18`. `8C071EB0` and `8C0729AA` do the same with PCW `0x81800040` for an effect mesh projected with fighter 1's shadow matrix (`0x8C25E058+0x1DC`). This matches the 35 % OMV buffer. Strings: `"P0 SHADOW WORK ADDRESS=%p"`.
- 2D/HUD: TA sprites (PCW `0xA2840009`, `8C05DB2A`). Blend constants: `0x84000000` (SRC_ALPHA, ONE: additive, 52 sites) and `0x94000000` (SRC_ALPHA, INV_SRC_ALPHA, 53 sites).
- Stage effects are per-stage "objects" (strings at `0x116358`): `TakiObj Splash Hamon Ripple SuiMen Snow Leaf Candle LgtBlur LightBlr Blur SdwObj Shadow PalBlink` (palette blink = CLUT animation).
- No profiler, polygon counter, or LOD strings found. A debug overlay exists (`"#X#Y motion_cnt=%d"`, `"P0 MODEL WORK ADDRESS=%p"`, `"MOTION MONITOR ... Motion monitor for dev. not include in product!"`). Stage culling and LOD were not analysed [?].
