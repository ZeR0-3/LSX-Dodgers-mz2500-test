#!/usr/bin/env python3
"""標準LSX形式(FAT12, 2FAT)のD88のルートへファイルを書き込む(テスト用)。
  d88_put.py image.d88 ローカルファイル NAME.EXT
空きクラスタを先頭から使う。BPB(論理セクタ0)から配置を求める。"""
import struct, sys
img, src, dst = sys.argv[1], sys.argv[2], sys.argv[3].upper()
buf = bytearray(open(img, 'rb').read()); data = open(src, 'rb').read()
offs = struct.unpack('<164I', buf[0x20:0x20 + 164 * 4]); sec = {}
for o in offs:
    if not o: continue
    ns = struct.unpack('<H', buf[o + 4:o + 6])[0]
    for _ in range(ns):
        c, h, r = buf[o], buf[o + 1], buf[o + 2]; sz = struct.unpack('<H', buf[o + 14:o + 16])[0]
        sec[(c, h, r)] = o + 16; o += 16 + sz
def loc(L):
    t, r = divmod(L, 9); return sec[(t >> 1, t & 1, r + 1)]
def rd(L): return bytes(buf[loc(L):loc(L) + 512])
def wr(L, d): buf[loc(L):loc(L) + 512] = d.ljust(512, b'\0')
b0 = rd(0); spc, rsv, nf, rent, fsz = b0[13], b0[14] | b0[15] << 8, b0[16], b0[17] | b0[18] << 8, b0[22] | b0[23] << 8
root0 = rsv + fsz * nf; data0 = root0 + rent * 32 // 512
fat = bytearray(b''.join(rd(rsv + i) for i in range(fsz)))
def get(c):
    o = c * 3 // 2; v = fat[o] | fat[o + 1] << 8; return v >> 4 if c & 1 else v & 0xFFF
def put(c, v):
    o = c * 3 // 2; w = fat[o] | fat[o + 1] << 8
    w = (w & 0x000F) | v << 4 if c & 1 else (w & 0xF000) | v
    fat[o] = w & 255; fat[o + 1] = w >> 8
ncl = (len(data) + spc * 512 - 1) // (spc * 512); free = [c for c in range(2, 1000) if get(c) == 0][:ncl]
assert len(free) == ncl
for i, c in enumerate(free): put(c, free[i + 1] if i + 1 < ncl else 0xFFF)
for i, c in enumerate(free):
    for k in range(spc):
        p = (i * spc + k) * 512; wr(data0 + (c - 2) * spc + k, data[p:p + 512])
for k in range(nf):
    for i in range(fsz): wr(rsv + k * fsz + i, bytes(fat[i * 512:(i + 1) * 512]))
name, _, ext = dst.partition('.'); key = name.ljust(8).encode() + ext.ljust(3).encode()
for L in range(root0, data0):
    b = bytearray(rd(L))
    for i in range(0, 512, 32):
        if b[i] in (0, 0xE5):
            b[i:i + 32] = key + bytes([0x20]) + bytes(14) + struct.pack('<H', free[0]) + struct.pack('<I', len(data))
            wr(L, bytes(b)); open(img, 'wb').write(buf); sys.exit(0)
sys.exit('root full')
