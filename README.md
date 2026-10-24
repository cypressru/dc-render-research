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
