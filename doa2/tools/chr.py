#!/usr/bin/env python3
"""Parse Dead or Alive 2 (Dreamcast) .CHR model files (NLOBJPUT object format).

usage: chr.py FILE.CHR [-v]

Layout (little-endian, offsets in bytes):
  header   u32 data_off (=0x18), u32 objtab_off, u32 textab_off, u32 n_obj, u32 n_tex, u32 0
  objtab   n_obj x u32 pointers, pre-linked to a fixed base (0x0C300000 characters,
           0x0C400000 stages/effects); file offset = ptr - ptr[0] + data_off
  textab   n_tex x {u16 w, u16 h, u16 fmt (PVRT pixel format | data type << 8), u16 0,
           u32 tex addr (0x0D200000 chars / 0x0D600000 stages; offset into the .BIN blob)}
  object   u32 a, u32 b, float sphere[4], then meshes
  mesh     u32 PCW (bit 31 set), u32 ISP/TSP word, u32 TSP, u32 TEX ctrl,
           float sphere[4], u32 mat[11] (byte at mat+4 = light type, signed),
           u32 size, strips...; the mesh list ends at a 0 word, a new mesh at a word with bit 31
  strip    u32 flags (bit 4 strip, else triangle list; bits 0-1 cull; bit 7 = chained to previous),
           u32 n (strip vertices, or triangles for a list: 3n records), vertex records: 32 B {x,y,z,nx,ny,nz,u,v} if bit 0 of x is set,
           else 8 B back-reference {u32 tag, s32 rel} to an earlier record
"""
import struct, sys, collections

def u32(d, o): return struct.unpack_from('<I', d, o)[0]

def parse(path, verbose=False):
    d = open(path, 'rb').read()
    data_off, objtab, textab, nobj, ntex, _ = struct.unpack_from('<6I', d, 0)
    ptrs = struct.unpack_from('<%dI' % nobj, d, objtab)
    base = ptrs[0]
    tex = [struct.unpack_from('<HHHHI', d, textab + 12 * i) for i in range(ntex)]
    st = collections.Counter()
    lists = collections.Counter(); ltypes = collections.Counter(); sflags = collections.Counter()
    blends = collections.Counter(); bad = 0; per = []
    for oi, p in enumerate(ptrs):
        o = p - base + data_off
        end = (ptrs[oi + 1] - base + data_off) if oi + 1 < nobj else objtab
        st['objects'] += 1
        t0 = st['tris']; v0 = st['inline']; ms0 = st['meshes']
        m = o + 24
        while m < end:
            pcw = u32(d, m)
            if pcw == 0 or not pcw & 0x80000000: break
            isp, tsp, texw = struct.unpack_from('<3I', d, m + 4)
            lt = struct.unpack_from('<b', d, m + 36)[0]
            size = u32(d, m + 76)
            st['meshes'] += 1
            lists[(pcw >> 24) & 7] += 1
            ltypes[lt] += 1
            blends['%d/%d' % (tsp >> 29, (tsp >> 26) & 7)] += 1
            s = m + 80; stop = s + size
            while s < len(d) - 8:
                f, n = struct.unpack_from('<2I', d, s)
                if f == 0 or f & 0x80000000 or n > 4096: break
                sflags[f] += 1
                if f & 0x10:
                    st['strips'] += 1; st['strip_verts'] += n; st['tris'] += max(0, n - 2); k = n
                else:
                    st['trilists'] += 1; st['tris'] += n; k = 3 * n
                s += 8
                for _ in range(k):
                    if u32(d, s) & 1:
                        s += 32; st['inline'] += 1
                    else:
                        s += 8; st['backref'] += 1
            if s != stop: bad += 1
            if verbose:
                print('obj %3d mesh pcw %08x isp %08x tsp %08x tex %08x type %d size %d%s' %
                      (oi, pcw, isp, tsp, texw, lt, size, '' if s == stop else ' (parse %d)' % (s - m - 80)))
            m = stop
        per.append((oi, st['meshes'] - ms0, st['inline'] - v0, st['tris'] - t0,
                    struct.unpack_from('<2I4f', d, o)))
    fmts = collections.Counter('%04x' % t[2] for t in tex)
    return dict(file=path, size=len(d), base=hex(base), nobj=nobj, ntex=ntex, stats=dict(st),
                lists=dict(lists), light_types=dict(ltypes), strip_flags={hex(k): v for k, v in sflags.items()},
                blend_src_dst=dict(blends), tex_formats=dict(fmts), mesh_parse_mismatch=bad,
                per_object=per, tex_sizes=dict(collections.Counter('%dx%d' % (t[0], t[1]) for t in tex)))

if __name__ == '__main__':
    if len(sys.argv) < 2: sys.exit(__doc__)
    r = parse(sys.argv[1], '-v' in sys.argv)
    for k, v in r.items():
        if k == 'per_object':
            if '-o' in sys.argv:
                for oi, nm, nv, nt, h in v:
                    print('  obj %3d meshes %2d verts %5d tris %5d  hdr %d %d sphere (%.3f %.3f %.3f) r %.3f' % ((oi, nm, nv, nt) + h))
        else: print('%-20s %s' % (k, v))
