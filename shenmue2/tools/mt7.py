#!/usr/bin/env python3
"""Shenmue II DC MDx7 (MT7) parser: node tree + model -> mesh -> strip stats.
Layout (reverse-engineered, see notes-world.md):
 hdr: 4cc(MDO7/MDL7/MDP7/MDC7) size firstNode texCount; texCount*16 tex descs (w,h,fmt,id8)
 node(0x40): u32 id|flags, f32 pos[3], s32 rot[3] (0x10000=360deg), f32 scl[3], u32 model, child, next, parent, ?, ?
 model: u32 a,b; f32 sphere[4]; meshes...; u32 0; u32 nUniqueVerts
 mesh: u32 pcw,isp,tsp,tex; f32 sphere[4]; s32 texIdx; u32 ?; f32 col[9]; u32 dataBytes; strips
 strip: u32 flags (0x10=strip, 0x08=tri list n=tris, 0x80=continuation), u32 n; n entries: 32B vertex (pos3 nrm3 uv2 float) or 8B ref (u32 a, s32 srcOfs<0 rel. to entry end -> y-slot is a NaN, which marks it)
"""
import struct, sys, gzip, collections
def load(p):
    d=open(p,'rb').read()
    return gzip.decompress(d) if d[:2]==b'\x1f\x8b' else d
def find_models(d):
    out=[]; i=0
    for tag in (b'MDO7',b'MDL7',b'MDP7',b'MDC7'):
        i=d.find(tag)
        while i>=0:
            sz=struct.unpack_from('<I',d,i+4)[0]
            if 0<sz<=len(d)-i: out.append((i,tag.decode(),sz))
            i=d.find(tag,i+4)
    return sorted(out)
class Stats: pass
def parse_model(m,mo,vstride=32):
    s=collections.Counter()
    a,b=struct.unpack_from('<II',m,mo); sph=struct.unpack_from('<4f',m,mo+8)
    o=mo+0x18; meshes=[]
    while True:
        pcw=struct.unpack_from('<I',m,o)[0] if o+4<=len(m) else 0
        if pcw==0: break
        if (pcw>>24)&0xe0 not in (0x80,0xa0,0xc0,0xe0) and pcw>>29!=4:
            raise ValueError(f'bad pcw {pcw:#x} @{o:#x}')
        isp,tsp,tex=struct.unpack_from('<3I',m,o+4); msph=struct.unpack_from('<4f',m,o+16)
        texi=struct.unpack_from('<i',m,o+32)[0]
        nbytes=struct.unpack_from('<I',m,o+0x4c)[0]
        p=o+0x50; end=p+nbytes; strips=[]
        while p<end:
            fl,n=struct.unpack_from('<II',m,p); p+=8; full=ref=0
            islist=(fl&0x18)==0x08
            for k in range(n*3 if islist else n):
                w1=struct.unpack_from('<I',m,p+4)[0]
                if w1>=0xff800001: ref+=1; p+=8
                else: full+=1; p+=vstride
            strips.append((fl,(n*3 if islist else n),full,ref,(n if islist else max(0,n-2))))
        if p!=end: raise ValueError(f'strip overrun {p:#x}!={end:#x}')
        meshes.append(dict(pcw=pcw,isp=isp,tsp=tsp,tex=tex,texi=texi,sph=msph,strips=strips,bytes=nbytes))
        o=end
    nuniq=struct.unpack_from('<I',m,o+4)[0] if o+8<=len(m) else -1
    return dict(a=a,b=b,sph=sph,meshes=meshes,nuniq=nuniq,end=min(o+8,len(m)))
def walk_nodes(m,first):
    nodes=[]; st=[(first,0)]
    while st:
        o,dep=st.pop()
        while o:
            f=struct.unpack_from('<I3f3i3f6I',m,o); nodes.append((o,dep,f))
            if f[11]: st.append((f[11],dep+1))
            o=f[12]
    return nodes
def summarize(m,name='',verbose=False):
    tag=m[:4].decode(); size,first,ntex=struct.unpack_from('<3I',m,4)
    nodes=walk_nodes(m,first); models=sorted({n[2][10] for n in nodes if n[2][10]})
    tot=collections.Counter(); per=[]
    for mo in models:
        r=parse_model(m,mo)
        tri=sum(st[4] for me in r['meshes'] for st in me['strips'])
        nst=sum(len(me['strips']) for me in r['meshes'])
        ent=sum(st[1] for me in r['meshes'] for st in me['strips'])
        full=sum(st[2] for me in r['meshes'] for st in me['strips'])
        per.append((mo,len(r['meshes']),nst,ent,full,r['nuniq'],tri,r['end']-mo,r['sph'][3]))
        tot['meshes']+=len(r['meshes']); tot['strips']+=nst; tot['entries']+=ent; tot['fullv']+=full
        tot['tris']+=tri; tot['uniq']+=r['nuniq']; tot['bytes']+=r['end']-mo
    inst_tris=0
    tri_of={p[0]:p[6] for p in per}
    for n in nodes:
        if n[2][10]: inst_tris+=tri_of[n[2][10]]
    print(f'{name} {tag} size={size} tex={ntex} nodes={len(nodes)} models={len(models)} '
          f"meshes={tot['meshes']} strips={tot['strips']} stripEntries={tot['entries']} fullVerts={tot['fullv']} "
          f"uniqVerts={tot['uniq']} tris(unique models)={tot['tris']} tris(instanced)={inst_tris} "
          f"avgStripLen={tot['entries']/max(1,tot['strips']):.2f} geomBytes={tot['bytes']} B/tri={tot['bytes']/max(1,tot['tris']):.1f}")
    if verbose:
        for p in per: print('  model@%x meshes=%d strips=%d ent=%d full=%d uniq=%d tris=%d bytes=%d r=%.2f'%p)
    return tot,nodes,per
if __name__=='__main__':
    if len(sys.argv)<2: sys.exit('usage: mt7.py FILE.MT7 [FILE ...]   (also raw MAPM/CHRM pack entries)')
    for p in sys.argv[1:]:
        v=p.startswith('-v:'); p=p[3:] if v else p
        d=load(p)
        for off,tag,sz in find_models(d):
            try: summarize(d[off:off+sz],f'{p}@{off:#x}',v)
            except Exception as e: print(p,hex(off),tag,'ERR',e)
