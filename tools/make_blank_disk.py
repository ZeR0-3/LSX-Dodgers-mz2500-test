#!/usr/bin/env python3
"""X1/MZ-700のLSXでフォーマットしたものと同じ形式の空ディスク(標準LSX形式)を作る。
  2D : 40cyl x 2面 x 9sec x 512B, media FDh, FAT 2sec   -> DIRの空き 362496
  2DD: 80cyl x 2面 x 9sec x 512B, media F9h, FAT 3sec   -> DIRの空き 730112
  unf2d / unf2dd : 未フォーマット(トラックが1つも無い)のD88。FORMAT.COM の物理フォーマットのテスト用
使い方: make_blank_disk.py out.d88 {2d|2dd|unf2d|unf2dd}"""
import struct, sys
out, kind = sys.argv[1], sys.argv[2].lower()
if kind.startswith('unf'):
    mt = 0x10 if kind == 'unf2dd' else 0x00
    open(out, 'wb').write(b'UNFORMATTED'.ljust(17, b'\0') + bytes(9) + bytes([0, mt]) + struct.pack('<I', 0x2B0) + bytes(164 * 4))
    print('wrote', out); sys.exit(0)
cyls, media, fatsz, mt = (40, 0xFD, 2, 0x00) if kind == '2d' else (80, 0xF9, 3, 0x10)
tot = cyls * 2 * 9
img = bytearray(tot * 512)
bs = bytearray(512); bs[0:3] = b'\xEB\xFE\x90'; bs[3:11] = b'LD      '
bs[11:13] = struct.pack('<H', 512); bs[13] = 2; bs[14:16] = struct.pack('<H', 1); bs[16] = 2
bs[17:19] = struct.pack('<H', 112); bs[19:21] = struct.pack('<H', tot); bs[21] = media
bs[22:24] = struct.pack('<H', fatsz); bs[24:26] = struct.pack('<H', 9); bs[26:28] = struct.pack('<H', 2); bs[31] = 0xC9
img[:512] = bs
for k in range(2): o = (1 + k * fatsz) * 512; img[o:o + 3] = bytes([media, 0xFF, 0xFF])
body = []; offs = []; pos = 0x2B0
for t in range(cyls * 2):
    c, h = divmod(t, 2); offs.append(pos); blk = b''
    for r in range(9):
        L = t * 9 + r; blk += struct.pack('<BBBBHBBB5xH', c, h, r + 1, 2, 9, 0, 0, 0, 512) + bytes(img[L * 512:(L + 1) * 512])
    body.append(blk); pos += len(blk)
offs += [0] * (164 - len(offs))
hdr = b'BLANK'.ljust(17, b'\0') + bytes(9) + bytes([0, mt]) + struct.pack('<I', pos) + b''.join(struct.pack('<I', o) for o in offs)
open(out, 'wb').write(hdr + b''.join(body)); print('wrote', out)
