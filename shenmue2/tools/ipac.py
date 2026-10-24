#!/usr/bin/env python3
"""List IPAC directory entries in a PKS (PAKS->IPAC) or gz-wrapped pack. Entry: name[8] ext[4] u32 off u32 size (off rel. IPAC start)."""
import struct,sys,gzip
def load(p):
    d=open(p,'rb').read()
    return gzip.decompress(d) if d[:2]==b'\x1f\x8b' else d
def ipacs(d):
    i=d.find(b'IPAC')
    while i>=0:
        dirofs,cnt,sz=struct.unpack_from('<III',d,i+4)
        if 0<cnt<5000 and i+dirofs+cnt*20<=len(d):
            ents=[]
            for k in range(cnt):
                e=i+dirofs+k*20
                nm=d[e:e+8].split(b'\0')[0].decode('latin1'); ex=d[e+8:e+12].split(b'\0')[0].decode('latin1')
                o,s=struct.unpack_from('<II',d,e+12); ents.append((nm,ex,i+o,s))
            yield i,ents
            i=d.find(b'IPAC',i+dirofs+cnt*20)
        else: i=d.find(b'IPAC',i+4)
if __name__=='__main__':
    if len(sys.argv)<2: sys.exit('usage: ipac.py PACK [PACK ...]   (PKS/PKF, optionally gzip-wrapped)')
    for p in sys.argv[1:]:
        d=load(p)
        for i,ents in ipacs(d):
            print(f'{p} IPAC@{i:#x} n={len(ents)}')
            for e in ents: print(f'   {e[0]:8s}.{e[1]:4s} @{e[2]:#08x} {e[3]:8d}')
