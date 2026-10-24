#!/usr/bin/env python3
"""Extract the ISO9660 filesystem from a Redump-style GD-ROM dump (.cue + raw
2352-byte .bin tracks). The high-density area starts at LBA 45000 (track 3);
later data tracks are placed by counting sectors of the tracks before them
(the last track ends at LBA 549150).

usage: gdrom_extract.py game.cue outdir
"""
import os, re, struct, sys

def tracks(cue):
    base = os.path.dirname(cue); out = []; cur = None
    for line in open(cue, encoding='latin1'):
        m = re.match(r'\s*FILE "(.+)"', line)
        if m: cur = os.path.join(base, m.group(1)); continue
        m = re.match(r'\s*TRACK (\d+) (\S+)', line)
        if m: out.append([int(m.group(1)), m.group(2), cur])
    return out

def layout(cue):
    """[(first_lba, sector_count, path)] for the high-density MODE1 tracks.
    Track 3 starts at LBA 45000 and the area ends at 549150; tracks are placed
    forward from the start while every earlier size is known and backward from
    the end otherwise, so a missing audio track in the middle does not matter."""
    t = [x for x in tracks(cue) if x[0] >= 3]
    sz = [os.path.getsize(p) // 2352 if p and os.path.exists(p) else None for _, _, p in t]
    fwd, lba = [], 45000
    for s in sz:
        fwd.append(lba)
        lba = None if (lba is None or s is None) else lba + s
    bwd, lba = [None] * len(t), 549150
    for i in range(len(t) - 1, -1, -1):
        if lba is None or sz[i] is None: lba = None; continue
        lba -= sz[i]; bwd[i] = lba
    res = []
    for i, (n, mode, p) in enumerate(t):
        a = fwd[i] if fwd[i] is not None else bwd[i]
        if mode.startswith('MODE1') and sz[i] and a is not None: res.append((a, sz[i], p))
    return res

class Disc:
    def __init__(self, cue):
        self.t = [(a, s, open(p, 'rb')) for a, s, p in layout(cue)]; self.missing = 0
    def sector(self, lba):
        for a, s, f in self.t:
            if a <= lba < a + s:
                f.seek((lba - a) * 2352 + 16); return f.read(2048)
        self.missing += 1   # gap/dummy file outside every data track: zeros
        return bytes(2048)
    def read(self, lba, size):
        return b''.join(self.sector(lba + i) for i in range((size + 2047) // 2048))[:size]

def walk(disc, rec, path, listing):
    lba, size = struct.unpack('<I', rec[2:6])[0], struct.unpack('<I', rec[10:14])[0]
    d = disc.read(lba, size); i = 0
    while i < len(d):
        l = d[i]
        if l == 0: i = (i // 2048 + 1) * 2048; continue
        r = d[i:i + l]; name = r[33:33 + r[32]]
        if name not in (b'\0', b'\1'):
            n = name.decode('latin1').split(';')[0]; p = os.path.join(path, n)
            if r[25] & 2: os.makedirs(p, exist_ok=True); walk(disc, r, p, listing)
            else:
                fl, fs = struct.unpack('<I', r[2:6])[0], struct.unpack('<I', r[10:14])[0]
                with open(p, 'wb') as o: o.write(disc.read(fl, fs))
                listing.append((fs, fl, p))
        i += l

if __name__ == '__main__':
    cue, out = sys.argv[1], sys.argv[2]
    disc = Disc(cue); os.makedirs(out, exist_ok=True)
    pvd = disc.sector(45000 + 16)
    assert pvd[1:6] == b'CD001', 'no ISO9660 PVD at LBA 45016'
    listing = []; walk(disc, pvd[156:190], out, listing)
    for fs, fl, p in sorted(listing): print('%10d  lba %6d  %s' % (fs, fl, p))
    if disc.missing: print('warning: %d sectors outside the data tracks read as zeros' % disc.missing, file=sys.stderr)
