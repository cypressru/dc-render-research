#!/usr/bin/env python3
"""Walk Shenmue II containers: gzip, PAKF (texture pack), PAKS/IPAC, generic 4CC+size chunks.

usage: sm2walk.py FILE [START_OFFSET]
  Prints each 4CC chunk with its size; stops at the first non-chunk or at a
  size that runs past the end of the data.
"""
import sys, struct, gzip
def load(p):
    d=open(p,'rb').read()
    if d[:2]==b'\x1f\x8b': d=gzip.decompress(d)
    return d
def is4cc(b): return all(32<=c<127 for c in b)
def chunks(d,off,end,depth=0,maxn=400):
    n=0
    while off+8<=end and n<maxn:
        tag=d[off:off+4]
        if not is4cc(tag): print('  '*depth+f'@{off:x} non-chunk {d[off:off+16].hex()}'); return
        sz=struct.unpack_from('<I',d,off+4)[0]
        if off+sz>end: print('  '*depth+f'@{off:06x} {tag.decode()} size={sz:#x} (past end: not a chunk)'); return
        print('  '*depth+f'@{off:06x} {tag.decode()} size={sz:#x}')
        if sz<8: sz=8
        off+=sz; n+=1
if __name__=='__main__':
    if len(sys.argv)<2: sys.exit(__doc__)
    d=load(sys.argv[1]); print('len',hex(len(d)))
    off=int(sys.argv[2],0) if len(sys.argv)>2 else 0
    chunks(d,off,len(d))
