#!/usr/bin/env python3
"""Disassemble address ranges of a raw little-endian SH4 binary (Dreamcast
1ST_READ-style executable) with sh-elf-objdump.

usage: listing.py BIN BASE START [END]      (hex addresses)
  Without END, stops after the first rts (and its delay slot) past START.
  Prints "addr:  insn" lines; literal-pool loads show their value as "! value".
Set OBJDUMP to override the objdump path.
"""
import os, re, subprocess, sys

OBJDUMP = os.environ.get('OBJDUMP', '/opt/toolchains/dc/sh-elf/bin/sh-elf-objdump')

def disasm(path, base, start, end):
    out = subprocess.run([OBJDUMP, '-D', '-EL', '-b', 'binary', '-m', 'sh4',
                          '--adjust-vma=0x%x' % base,
                          '--start-address=0x%x' % start, '--stop-address=0x%x' % end, path],
                         capture_output=True, text=True, check=True).stdout
    for l in out.splitlines():
        m = re.match(r'\s*([0-9a-f]{8}):\t[0-9a-f ]+\t(.*)', l)
        if m: yield int(m.group(1), 16), re.sub(r'\s+', ' ', m.group(2)).strip()

def routine(path, base, start, end=None):
    lines = list(disasm(path, base, start, end or start + 0x2000))
    if end: return lines
    for i, (a, s) in enumerate(lines):
        if s.startswith('rts'): return lines[:i + 2]
    return lines

if __name__ == '__main__':
    p, base, start = sys.argv[1], int(sys.argv[2], 16), int(sys.argv[3], 16)
    end = int(sys.argv[4], 16) if len(sys.argv) > 4 else None
    for a, s in routine(p, base, start, end): print('%08x:  %s' % (a, s))
