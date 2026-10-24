#!/usr/bin/env python3
"""Check annotated listings against a fresh disassembly of the binary.

usage: check_listings.py BIN BASE LISTING.s [LISTING.s ...]

Every line that starts with an address (`8c0xxxxx:  insn ...`) is compared
with sh-elf-objdump's decode of that address. Comments (after ';' or '//')
and literal-pool annotations ('! value') are ignored; operand text is
compared with branch-target hex stripped. Exits non-zero on any mismatch.
"""
import re, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from listing import disasm

def norm(s):
    s = s.split(';')[0].split('//')[0]
    s = re.sub(r'!.*', '', s)
    s = re.sub(r'\s+', ' ', s).strip().lower().replace(', ', ',')
    return re.sub(r'0x[0-9a-f]+', 'X', s)

def main(a):
    if len(a) < 3: sys.exit(__doc__)
    path, base = a[0], int(a[1], 16)
    size = os.path.getsize(path)
    ref = {x: norm(s) for x, s in disasm(path, base, base, base + size)}
    bad = total = 0
    for lst in a[2:]:
        n = 0
        for i, line in enumerate(open(lst), 1):
            m = re.match(r'\s*(?:0x)?(8c[0-9a-f]{6}):?\s+(\S.*)', line, re.I)
            if not m: continue
            got = norm(m.group(2))
            if not got: continue
            n += 1; addr = int(m.group(1), 16)
            if ref.get(addr) != got:
                bad += 1; print('%s:%d: %08x listing %r, binary %r' % (lst, i, addr, got, ref.get(addr)))
        total += n; print('%s: %d instruction lines' % (lst, n))
    print('checked %d, mismatches %d' % (total, bad))
    sys.exit(1 if bad else 0)

if __name__ == '__main__': main(sys.argv[1:])
