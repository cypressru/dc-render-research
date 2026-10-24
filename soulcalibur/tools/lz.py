#!/usr/bin/env python3
"""Soulcalibur (Dreamcast) LZ decompressor and olnk pack lister.

A direct port of the game's decoder at 0x8C0EE76C (1ST_READ.BIN, base 0x8C010000):

  repeat:
    flag = next byte
    0xFF -> copy 7 raw bytes, continue
    0x00 -> end
    else, until flag == 1 (sentinel bit):
      bit = flag & 1; flag >>= 1
      bit 1 -> copy one literal byte
      bit 0 -> back-reference: v = big-endian u16
               length   = ((v >> 11) - 1 & 31) + 1
               distance = ((v - 1) & 0x7FF) + 1   (bytes back from the output end)

The game rounds the returned size up to a multiple of 4.

olnk container: u32 n, 'olnk', u32 header size, u32 total, then n (offset, size)
pairs, offsets relative to the end of the header.
Inner pack: u32 n, u32 header size, u32 end_offset[n]; entry i runs from the
previous end (the header size for i = 0) to end_offset[i].

Verified: STAGE.DAT stage 0, inner pack 1, entry 0 decompresses 71232 ->
124064 bytes (the stream ends 12 bytes early: padding); entries 1.. are raw
0x20000-byte 16 bpp texture pages.

usage: lz.py list FILE                  list olnk entries (and whether each decodes)
       lz.py inner FILE OLNK_INDEX      list an olnk entry's inner pack, recursing one level
       lz.py unpack FILE INDEX OUT      decompress one olnk entry to OUT
       lz.py raw FILE OFFSET OUT        decompress a stream starting at OFFSET

  e.g. lz.py inner STAGE.DAT 0          (stage 0: its geometry stream and texture pages)

'list' and 'inner' try the decoder on every entry; a small raw entry can
occasionally decode by accident, so treat their 'lz' labels as a hint.
"""
import struct, sys

def decompress(d, pos=0):
    out = bytearray()
    while True:
        flag = d[pos]; pos += 1
        if flag == 0xFF:
            out += d[pos:pos + 7]; pos += 7; continue
        if flag == 0:
            return bytes(out), pos
        while flag != 1:
            bit = flag & 1; flag >>= 1
            if bit:
                out.append(d[pos]); pos += 1
            else:
                v = (d[pos] << 8) | d[pos + 1]; pos += 2
                length = (((v >> 11) - 1) & 31) + 1
                dist = ((v - 1) & 0x7FF) + 1
                if dist > len(out): raise ValueError('reference before start of output')
                for _ in range(length): out.append(out[-dist])

def olnk(d):
    n, magic, hdr, total = struct.unpack_from('<I4sII', d, 0)
    if magic != b'olnk': raise ValueError('not an olnk pack')
    pairs = struct.unpack_from('<%dI' % (2 * n), d, 16)
    return [(hdr + pairs[2 * i], pairs[2 * i + 1]) for i in range(n)]

def inner(d):
    n, hdr = struct.unpack_from('<II', d, 0)
    ends = struct.unpack_from('<%dI' % n, d, 8)
    if any(e > len(d) for e in ends): raise ValueError('not an inner pack')
    return list(zip([hdr] + list(ends[:-1]), ends))

def describe(leaf):
    try:
        out, used = decompress(leaf)
        return 'lz %d -> %d B (stream %d B)' % (len(leaf), len(out), used)
    except Exception:
        return 'raw %d B, starts %s' % (len(leaf), leaf[:8].hex())

def main(a):
    if len(a) < 2: sys.exit(__doc__)
    d = open(a[1], 'rb').read()
    if a[0] == 'list':
        for i, (o, s) in enumerate(olnk(d)):
            try:
                out, end = decompress(d[o:o + s]); info = 'lz -> %d B, starts %r' % (len(out), out[:4])
            except Exception as e:
                info = 'not LZ (%s), starts %r' % (e.__class__.__name__, d[o:o + 4])
            print('%4d  @%08x  %8d B  %s' % (i, o, s, info))
    elif a[0] == 'inner':
        o, s = olnk(d)[int(a[2])]; e = d[o:o + s]
        for i, (x, y) in enumerate(inner(e)):
            leaf = e[x:y]
            try: sub = inner(leaf)
            except Exception: sub = None
            if sub and len(sub) > 1:
                print('%3d  inner pack, %d entries' % (i, len(sub)))
                for j, (u, v) in enumerate(sub): print('     %3d  %s' % (j, describe(leaf[u:v])))
            else: print('%3d  %s' % (i, describe(leaf)))
    elif a[0] == 'unpack':
        o, s = olnk(d)[int(a[2])]; open(a[3], 'wb').write(decompress(d[o:o + s])[0])
    elif a[0] == 'raw':
        open(a[3], 'wb').write(decompress(d, int(a[2], 0))[0])
    else: sys.exit(__doc__)

if __name__ == '__main__': main(sys.argv[1:])
