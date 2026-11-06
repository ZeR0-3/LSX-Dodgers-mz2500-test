#!/usr/bin/env python3
"""AILZ80ASM風ソース -> z88dk-z80asm 向け変換 (検証用ハーネス)
使い方: ld2z80asm.py <srcdir> <outdir> [DEFINE ...]
"""
import re, sys, os
src, out = sys.argv[1], sys.argv[2]
defs = set(sys.argv[3:])
os.makedirs(out, exist_ok=True)
for fn in os.listdir(src):
    if not fn.upper().endswith('.ASM'): continue
    lines = open(os.path.join(src, fn), encoding='utf-8', errors='replace').read().split('\n')
    o = []
    lastlabel = None
    for l in lines:
        code, sep, cmt = l.partition(';')
        s = code
        # #IF EXISTS X / #ELSE / #ENDIF
        m = re.match(r'^\s*#IF\s+EXISTS\s+(\w+)', s, re.I)
        if m:
            o.append('\tIFDEF\t%s' % m.group(1)); continue
        if re.match(r'^\s*#ELSE', s, re.I): o.append('\tELSE'); continue
        if re.match(r'^\s*#ENDIF', s, re.I): o.append('\tENDIF'); continue
        # ORG a,b  (phase)   /  ORG $$+OFFSET,$$  (dephase)
        if re.match(r'^\s*END\s*$', s, re.I): continue
        m0 = re.match(r'^LAST_ADR\s+EQU\s+\$\$\+OFFSET', s)
        if m0:
            o.append('LAST_ADR\tEQU\tINITE+$-BDOS'); continue
        m = re.match(r'^(\s*)ORG\s+(.+),(.+)$', s, re.I)
        if m:
            if m.group(3).strip() == '$$':
                o.append('\tDEPHASE')
            else:
                o.append('\tPHASE\t%s' % m.group(2).strip())
            continue
        s = s.replace('$$', '$')
        s = re.sub(r"(?<![\w'\"$])([A-F][0-9A-F]{2,}H)\b", r'0\1', s)
        s = re.sub(r'\bHIGH\s+(\w+)', r'\1/256', s)
        s = re.sub(r'\bLINE\b', 'LINES_', s)
        if re.match(r'^\s*INCLUDE', s, re.I): s = s  # same
        ml = re.match(r'^([A-Za-z_][\w]*):?\s*($|DS\b)', s)
        if re.match(r'^([A-Za-z_]\w*):', s) or re.match(r'^[A-Za-z_]\w*\s*$', s):
            lastlabel = re.match(r'^([A-Za-z_]\w*)', s).group(1)
        if lastlabel:
            s = re.sub(r'(\bDS\s+[^;]*?-)\s*%s\b' % re.escape(lastlabel), r'\1ORG_BASE-$', s)
        o.append(s + sep + cmt)
    open(os.path.join(out, fn), 'w', encoding='utf-8').write('\n'.join(o))
