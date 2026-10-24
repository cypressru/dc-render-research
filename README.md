# Dreamcast renderer research

Static analysis of how commercial Dreamcast games get their geometry speed
out of the SH4 and PowerVR2: vertex transform and lighting loops, store-queue
and TA submission, culling, LOD and data layout. Written to inform homebrew
renderers (KallistiOS, sh4zam).

| Game | Folder | Status |
|---|---|---|
| World Series Baseball 2K2 (2001, Blue Shift, Kamui2): original renderer source | [`wsb2k2/`](wsb2k2/README.md) | source + notes |
| Test Drive Le Mans (2000, Melbourne House, Kamui2) | [`test-drive-le-mans/`](test-drive-le-mans/README.md) | done |
| Soulcalibur (1999, Namco, Kamui 1.06) | [`soulcalibur/`](soulcalibur/README.md) | done |
| Shenmue II (2001, Sega AM2, Kamui 1.11), Japan disc 1 | [`shenmue2/`](shenmue2/README.md) | done |
| Dead or Alive 2 (2000, Team Ninja/Tecmo, Kamui2; renderer is the AM2 NAOMI library) | [`doa2/`](doa2/README.md) | done |

Shenmue II and Dead or Alive 2 share one renderer, Sega AM2's "NAOMI library"
(NL 0.8 / 0.9): their main kernels are instruction-for-instruction identical.

## Interesting discoveries

- **Two games, one renderer.** Shenmue II and Dead or Alive 2 both draw
  through Sega AM2's "NAOMI library". Their bulk vertex kernels are the same
  151 instructions, and the clip kernel matches 431 of 431
  ([DOA2](doa2/README.md)).
- **The command word is a memory address.** In that library each vertex's
  PCW is the store-queue address of the previous vertex: any address in
  `0xE0000000-0xE3FFFFFF` reads as a valid "vertex" command. End of strip is
  one `shar` of it (`0xE0...` becomes `0xF0...`). It saves registers, not
  cycles ([Shenmue II](shenmue2/README.md)).
- **Hiding the divide.** The AM2 kernel handles two vertices per loop trip, so
  each FDIV's result isn't read until about 20 instructions later. Le Mans and
  Soulcalibur use it right away and stall an estimated 8-9 cycles per vertex
  ([Shenmue II](shenmue2/README.md)).
- **A vertex index hidden in a bone weight.** Soulcalibur stores each skinned
  vertex as `{w*x, w*y, w*z, w}` per bone and keeps the destination index in
  the low 12 mantissa bits of the weight `w`, an error of at most about
  1/2048. The same loop has a `movca.l` cache trick that never fires: its
  alignment test checks the address 12 bytes into the entry
  ([Soulcalibur](soulcalibur/README.md)).
- **Four coloured lights in two instructions.** Soulcalibur loads four light
  directions into the matrix (one FTRV gives all four N.L), then four light
  colours (a second FTRV sums the RGB) ([Soulcalibur](soulcalibur/README.md)).
- **60 fps by patching its own code.** When a frame won't fit, Dead or Alive 2
  overwrites 11 draw entry points with `rts; nop`, runs one logic tick
  without drawing, then restores them. Logic stays at 60 Hz
  ([DOA2](doa2/README.md)).
- **A crowd sized by the clock.** Shenmue II recomputes how many NPCs to draw
  every frame from their measured draw cost against a 32 ms budget, fading the
  rest out ([Shenmue II](shenmue2/README.md)).
- **Shenmue II doesn't stream its town.** A district is one resident pack; the
  big `STREAM/*.AFS` files are ADX voice audio (24,803 "free talk" clips in
  `FREE01.AFS` alone) ([Shenmue II](shenmue2/README.md)).
- **Le Mans' "5 million polygons per second".** The binary gives no support
  for it. The whole track is about 54k triangles across four layers (plus
  about 18k in instanced props). Speed comes from a 30-instruction prelit
  kernel, distance layers (far-plane x 1.0 / 0.55 / 0.23) and a fixed
  37,000-strip-vertex budget ([Le Mans](test-drive-le-mans/README.md)).
- **pow(x, 16) on the integer pipe.** Le Mans computes specular by shifting
  the float's bit pattern left by 4 and adding the bits of 65536.0f
  ([Le Mans](test-drive-le-mans/README.md)).
- **Two colour channels per multiply.** Le Mans' clip path lerps packed ARGB
  as R|B and G in two registers with 8.8 fixed point: four `mul.l` for all
  channels. It masks alpha out, so clipped vertices get A = 0
  ([Le Mans](test-drive-le-mans/README.md)).
- **On-chip RAM only in WSB.** None of the four disassembled games enables
  the operand-cache RAM (OCRAM) or index mode; the only cache-level trick
  among them is Soulcalibur's `movca.l` line allocation for its vertex pools. WSB 2K2's source
  does: `__VCCPU_SplitCache` sets ORA and OIX and keeps the vertex pool and
  material table in on-chip RAM ([WSB 2K2](wsb2k2/README.md)).
- **Switched-off code in the WSB source.** In this revision of the WSB 2K2
  renderer (CVS 1.88 / 1.34), the batched bounding-box cull, the NOP-padded store-queue emitter and bump
  mapping are all compiled out (`#if 0`) ([WSB 2K2](wsb2k2/README.md)).

Each game folder has a `README.md` with findings and a `listings/` folder
with annotated disassembly of the important routines.

## Tools

- `tools/gdrom_extract.py game.cue outdir`: extracts the ISO9660 filesystem
  from a Redump-style GD-ROM dump (raw 2352-byte tracks, high-density area
  from LBA 45000).
- `tools/listing.py BIN BASE START [END]`: disassembles a range of a raw
  little-endian SH4 executable with `sh-elf-objdump` (stops after the first
  `rts` when END is omitted). Needs the SH toolchain (KallistiOS
  `sh-elf-objdump`; set `OBJDUMP` to override the path).
- `tools/check_listings.py BIN BASE LISTING.s ...`: compares every
  instruction line of annotated listings with a fresh disassembly of the binary
  (all listings in this repository pass).

Per-game parsers (Python 3, no dependencies; run without arguments for usage):

| Tool | Reads |
|---|---|
| `soulcalibur/tools/lz.py` | Soulcalibur LZ streams, `olnk` and inner packs |
| `shenmue2/tools/mt7.py` | Shenmue II MT7 models; its `parse_model()` also reads every model inside DOA2 `.CHR` files (all 86 checked), but the command line needs an MT7 header, so use `doa2/tools/chr.py` for whole `.CHR` files |
| `shenmue2/tools/ipac.py` | Shenmue II PKS/PKF packs (IPAC directories, gzip-wrapped or raw) |
| `shenmue2/tools/area.py` | Shenmue II per-area summary of a district pack |
| `shenmue2/tools/sm2walk.py` | Shenmue II generic 4CC chunk walker |
| `doa2/tools/chr.py` | Dead or Alive 2 `.CHR` models |
| `doa2/tools/aux_formats.py` | Dead or Alive 2 `.APV` morphs and `.SUP` joint welds |

## Method

All game folders follow the same steps:

1. Extract the disc with `tools/gdrom_extract.py`.
2. Find the executable's load base by matching 32-bit words against string
   offsets (0x8C010000 for every game so far).
3. Disassemble as little-endian (`sh-elf-objdump -D -EL -b binary -m sh4`);
   the default big-endian decode is garbage.
4. Find hot code by clustering `ftrv`/`fipr`/`pref`/`frchg`/`fschg`/`fsrra`
   and literal references to the store queues (0xE0000000), QACR
   (0xFF000038/3C), the TA FIFO (0x10000000), CCR (0xFF00001C), OCRAM
   (0x7C000000) and the DMA controller. Raw counts of these constants
   overstate: most hits are data, so confirm each in code.
5. Name routines from strings, RTTI and library version banners.
6. Check every listing line against a fresh disassembly before publishing
   (`tools/check_listings.py`).

Findings are static: instruction counts and cycle estimates, not
measurements on hardware.

## Releases analysed

Addresses are only valid for these dumps (Redump naming):

| Game | Dump | Executable |
|---|---|---|
| Test Drive Le Mans | Test Drive Le Mans (USA) (En,Fr,Es) | `LEMANS24.BIN` (loaded by `1ST_READ.BIN`) |
| Soulcalibur | Soulcalibur (USA) | `1ST_READ.BIN` |
| Shenmue II | Shenmue II (Japan) (Disc 1) | `1ST_READ.BIN` |
| Dead or Alive 2 | Dead or Alive 2 (USA) | `1ST_READ.BIN` |

All executables load at 0x8C010000.

## Notes

No game data is included. The listings are short excerpts of disassembly with
commentary, for research and interoperability. Addresses refer to the analysed
releases. `wsb2k2/source/` holds the publicly released WSB 2K2 renderer source
(Copyright (c) 2000 Blue Shift, Inc.), unmodified.
