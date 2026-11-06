#!/usr/bin/env python3
"""起動ディスクの LD2500.BIN 2セクタ目(LSN50: cyl2/head1/sec6)を壊したD88を作る(ブートローダのエラー動作テスト用)
使い方: make_bad_boot_disk.py in.d88 out.d88 crc|rnf|data
  data: シリンダ5以降の全セクタをCRCエラーにする(OS動作中の読み出しエラー時の復帰テスト用。起動には影響しない)"""
import struct, sys
src, dst, mode = sys.argv[1:4]
d = bytearray(open(src, 'rb').read())
offs = [struct.unpack_from('<I', d, 0x20 + 4 * i)[0] for i in range(164)]
if mode == 'data':
    for t in range(164):
        if offs[t] == 0 or t // 2 < 5: continue
        o = offs[t]
        for _ in range(9):
            sz = struct.unpack_from('<H', d, o + 14)[0]; d[o + 8] = 0xB0; o += 16 + sz
    open(dst, 'wb').write(d); sys.exit(0)
o = offs[2 * 2 + 1]                       # cyl2/head1
while True:
    c, h, r, n = d[o:o + 4]; sz = struct.unpack_from('<H', d, o + 14)[0]
    if (c, h, r) == (2, 1, 6): break
    o += 16 + sz
if mode == 'crc': d[o + 8] = 0xB0          # データCRCエラー
else: d[o + 2] = 0x7F                      # IDのRを変えて RNF にする
open(dst, 'wb').write(d)
