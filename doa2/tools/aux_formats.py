#!/usr/bin/env python3
"""Summaries of Dead or Alive 2 (Dreamcast) per-costume side files.

usage: aux_formats.py DIR NAME        e.g.  aux_formats.py fs/DOA2 KAS00

APV  morph targets. u32 n_sections (9), u32 sec_off[n] (0xFFFFFFFF = absent).
     section: u32 cnt, u32 sub_off[cnt+1] (relative to section start);
     block 0 = u32 vertex byte offsets, relative to the start of one CHR object;
     block 1 = base positions (3 floats per vertex); blocks 2.. = per-target data
     (same size, small values: deltas).
SUP  joint welds. u32 sec_off[...], 0-terminated (7-14 sections). section: u32 header
     size (0x34), u8 node_a, u8 node_b, u16 n, about 128 B of matrix/float data, then
     groups of 28 B records {u32 CHR vertex offset, float pos[3], float nrm[3]}.
"""
import struct, sys, os

def chr_objects(d):
    h = struct.unpack_from('<6I', d, 0)
    ptrs = struct.unpack_from('<%dI' % h[3], d, h[1])
    return [p - ptrs[0] + h[0] for p in ptrs]

def apv(dirn, name):
    c = open(os.path.join(dirn, name + '.CHR'), 'rb').read()
    a = open(os.path.join(dirn, name + '.APV'), 'rb').read()
    obase = chr_objects(c)
    n = struct.unpack_from('<I', a, 0)[0]
    for si, s in enumerate(struct.unpack_from('<%dI' % n, a, 4)):
        if s == 0xFFFFFFFF:
            print('APV sec %d: absent' % si); continue
        cnt = struct.unpack_from('<I', a, s)[0]
        sub = struct.unpack_from('<%dI' % (cnt + 1), a, s + 4)
        nv = (sub[1] - sub[0]) // 4 - 1
        off0 = struct.unpack_from('<I', a, s + sub[0])[0]
        y = struct.unpack_from('<I', a, s + sub[1] + 4)[0]
        objs = [i for i, ob in enumerate(obase)
                if ob + off0 + 8 <= len(c) and struct.unpack_from('<I', c, ob + off0 + 4)[0] == y]
        print('APV sec %d: %2d position blocks (incl. base), %4d vertices, object %s, %d bytes' %
              (si, cnt - 1, nv, objs or '?', sum(sub[i + 1] - sub[i] for i in range(cnt))))

def sup(dirn, name):
    s = open(os.path.join(dirn, name + '.SUP'), 'rb').read()
    offs = []
    while struct.unpack_from('<I', s, 4 * len(offs))[0]:
        offs.append(struct.unpack_from('<I', s, 4 * len(offs))[0])
    for i, o in enumerate(offs):
        _, a, b, n = struct.unpack_from('<IBBH', s, o)
        print('SUP sec %d: nodes %2d-%2d, %3d vertices' % (i, a, b, n))

if __name__ == '__main__':
    if len(sys.argv) < 3: sys.exit(__doc__)
    apv(sys.argv[1], sys.argv[2]); sup(sys.argv[1], sys.argv[2])
