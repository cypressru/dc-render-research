#!/usr/bin/env python3
"""Per-area summary: every PKS's IPAC entries; MAPM/CHRM entries parsed with mt7.summarize.

usage: area.py PACK.PKS [PACK.PKS ...]
  e.g. area.py fs/SCENE/01/0004/MPK00.PKS
  Set AREAFLAGS=-c to also summarise CHRM (character) entries.
"""
import sys,os,io,contextlib,struct
sys.path.insert(0,os.path.dirname(__file__))
import mt7, ipac
if len(sys.argv)<2: sys.exit(__doc__)
for p in sys.argv[1:]:
    d=ipac.load(p)
    for i,ents in ipac.ipacs(d):
        kinds={}
        for nm,ex,o,s in ents: kinds[ex]=kinds.get(ex,0)+s
        print(f'== {os.path.basename(p)} ({os.path.getsize(p)} B on disc, {len(d)} B raw) entries={len(ents)} ' + ' '.join(f'{k}:{v}' for k,v in sorted(kinds.items())))
        for nm,ex,o,s in ents:
            if ex in ('MAPM',) or (ex=='CHRM' and '-c' in os.environ.get('AREAFLAGS','')):
                buf=io.StringIO()
                try:
                    with contextlib.redirect_stdout(buf): mt7.summarize(d[o:o+s],f'{nm}.{ex}')
                    print('   '+buf.getvalue().strip())
                except Exception as e: print('   ',nm,ex,'ERR',e)
