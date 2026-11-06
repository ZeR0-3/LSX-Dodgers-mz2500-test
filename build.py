#!/usr/bin/env python3
"""LSX-Dodgers MZ-2500 ビルド (z88dk-z80asm 使用)
  [LSX_IMPORT=<原本のシステムD88>] python3 build.py <LSX-Dodgers原本dir(LD*.ASMのあるフォルダ)> <z88dk-z80asm> <出力dir> [USE_TINIT] [COLS80] [KEEP_ENV]
"""
import os, re, shutil, subprocess, sys
orig, Z, out = sys.argv[1:4]
flags = sys.argv[4:]          # 例: COLS80 DEBUG_MARK
PRE = ''.join('%s\tEQU\t1\n' % f for f in flags)
here = os.path.dirname(os.path.abspath(__file__))
os.makedirs(out, exist_ok=True)
work = os.path.join(out, 'src'); conv = os.path.join(out, 'conv')
for d in (work, conv): shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
for f in os.listdir(orig):   # 原本はCP932 -> UTF-8
    if f.upper().endswith('.ASM'):
        raw = open(os.path.join(orig, f), 'rb').read()
        try: txt = raw.decode('cp932')
        except UnicodeDecodeError: txt = raw.decode('cp932', errors='replace')
        open(os.path.join(work, f), 'w', encoding='utf-8').write(txt)
for f in os.listdir(os.path.join(here, 'src')): shutil.copy(os.path.join(here, 'src', f), work)
subprocess.check_call([sys.executable, os.path.join(here, 'tools', 'ld2z80asm.py'), work, conv])
env = dict(os.environ)
env.setdefault('Z80_OZFILES', os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(Z)))), 'lib'))
def asm(name, src):
    p = os.path.join(conv, name + '.asm'); open(p, 'w', encoding='utf-8').write(PRE + src)
    r = subprocess.run([Z, '-b', '-m=z80', '-m', name + '.asm'], cwd=conv, env=env, capture_output=True, text=True)
    if r.returncode: print(r.stdout, r.stderr); sys.exit('assemble failed: ' + name)
    for l in r.stdout.splitlines():
        if 'warning' in l: print('  ', l)
    return open(os.path.join(conv, name + '.bin'), 'rb').read()

# ---- 本体 (ORG BDOS) ----
inc = ['M25BANK','M25CCP','LDCCP','M25CCP2','LDOS','M25IO','LDFILE','LDFILE2','LDDIO','M25DISK','M25MEM',
       'LDCCPWK','M25TABLE','LDWORK','LDCALL','M25DPB']
body_src = '\tINCLUDE "M25DEF.ASM"\n\tINCLUDE "LDDEF.ASM"\nORG_BASE EQU BDOS\n\tORG BDOS\n\tJP IO_BDOS\n' + \
           ''.join('\tINCLUDE "%s.ASM"\n' % n for n in inc)
body = asm('body25', body_src)
print('body', len(body), 'bytes  BDOS..%04X' % (0xCF06 + len(body)))
syms = {}
for l in open(os.path.join(conv, 'body25.map'), encoding='utf-8', errors='replace'):
    m = re.match(r'^(\w+)\s*=\s*\$([0-9A-Fa-f]+)', l)
    if m: syms[m.group(1)] = int(m.group(2), 16)
need = ['FILL_MEMORY','ZERO_MEMORY_DE','MSX','MSG_A','_COMANL','CPM_WBOOT','IO_INT8253','_DISKE',
        '_BREAK','CPM_BOOT','CHKEY','S27BUF','_DEVICE']
miss = [n for n in need if n not in syms]
if miss: sys.exit('missing symbols: %s' % miss)
open(os.path.join(conv, 'body_syms.inc'), 'w').write(
    ''.join('%s\tEQU\t0%04XH\n' % (n, syms[n]) for n in need) + 'BODYLEN\tEQU\t%d\n' % len(body))

# ---- TRAP38 (ORG TRAP38) ----
trap = open(os.path.join(here, 'src', 'TRAP38.ASM'), encoding='utf-8').read()
trap_bin = asm('trap38', 'TRAP38\tEQU\t0FFD9H\n\tINCLUDE "body_syms.inc"\n' + trap)

# ---- ステージ1 + IPLヘッダ ----
st = open(os.path.join(conv, 'M25INIT.ASM'), encoding='utf-8').read()
open(os.path.join(conv, 'body25.bin.inc'), 'w').write('')
img = asm('ipl', '\tINCLUDE "M25DEF.ASM"\n\tINCLUDE "LDDEF.ASM"\n\tINCLUDE "body_syms.inc"\n' + st)
sysbin = img[:]                                   # LD2500.BIN (ORG 8000H で組んだシステム。START から始まる)
open(os.path.join(out, 'LD2500.BIN'), 'wb').write(sysbin)
nsec = -(-len(sysbin) // 512); assert nsec <= 32, 'LD2500.BINは16KB以下'
# ---- ブートローダ(IPLが読む8KBページ) ----
RSV, FATSZ, NFAT, ROOTSEC = 36, 3, 2, 7
sys_lsn0 = RSV + FATSZ * NFAT + ROOTSEC          # = 49 : 先頭クラスタの論理セクタ
boot_src = open(os.path.join(conv, 'M25BOOT.ASM'), encoding='utf-8').read()
boot = asm('boot', 'SYS_LSN0\tEQU\t%d\nSYS_NSEC\tEQU\t%d\n' % (sys_lsn0, nsec) + boot_src)
open(os.path.join(out, 'boot_payload.bin'), 'wb').write(boot)
print('LD2500.BIN', len(sysbin), 'bytes (%d sectors @LSN %d) / boot loader' % (nsec, sys_lsn0), len(boot), 'bytes')
# ---- 起動ディスク(標準LSX形式のD88)。LSX_IMPORT=<原本のシステムD88> で FORMAT.COM 等のツールも取り込む ----
cmd = [sys.executable, os.path.join(here, 'tools', 'make_boot_disk.py'), os.path.join(out, 'LSX2500.d88'),
       os.path.join(out, 'LD2500.BIN'), os.path.join(out, 'boot_payload.bin')]
if os.environ.get('LSX_IMPORT'): cmd += ['--import', os.environ['LSX_IMPORT']]
subprocess.check_call(cmd)
