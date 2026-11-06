#!/usr/bin/env python3
"""標準LSX形式(FAT12, 512B/セクタ, 1トラック9セクタ x 2面)のD88から、ファイルを取り出して標準出力に書く。
  d88_cat.py image.d88 NAME.EXT     (ルート直下のファイルのみ)
BPB(論理セクタ0)から予約セクタ数・FAT・ルートの位置を求める。"""
import struct, sys
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from make_boot_disk import read_d88

def main():
    img, want = sys.argv[1], sys.argv[2].upper()
    s = read_d88(img)
    def lsn(L):
        t, r = divmod(L, 9)
        return s.get((t >> 1, t & 1, r + 1), b'\0' * 512)
    b0 = lsn(0)
    spc, rsv, nfat, rent, fsz = b0[13], b0[14] | b0[15] << 8, b0[16], b0[17] | b0[18] << 8, b0[22] | b0[23] << 8
    fat = b''.join(lsn(rsv + i) for i in range(fsz))
    root0 = rsv + fsz * nfat; rsec = rent * 32 // 512; data0 = root0 + rsec
    def nxt(c):
        o = c * 3 // 2; v = fat[o] | fat[o + 1] << 8
        return (v >> 4) if c & 1 else (v & 0xFFF)
    name, _, ext = want.partition('.')
    key = name.ljust(8).encode() + ext.ljust(3).encode()
    for L in range(root0, root0 + rsec):
        blk = lsn(L)
        for i in range(0, 512, 32):
            e = blk[i:i + 32]
            if e[0] == 0 or e[0] == 0xE5 or e[:11] != key: continue
            size = struct.unpack('<I', e[28:32])[0]; c = e[26] | e[27] << 8; out = b''
            while 2 <= c < 0xFF0 and len(out) < size:
                for k in range(spc): out += lsn(data0 + (c - 2) * spc + k)
                c = nxt(c)
            sys.stdout.buffer.write(out[:size]); return 0
    sys.stderr.write('not found\n'); return 1
sys.exit(main())
