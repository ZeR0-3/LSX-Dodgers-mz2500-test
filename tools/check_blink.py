#!/usr/bin/env python3
"""frame-dump したPPM列から、カーソルセル(2桁目・2行目、80桁16ライン想定)の明暗が周期的に切り替わるか調べる。
使い方: check_blink.py <ppm dir> [x0 y0 x1 y1]   切り替わりが2回以上あり、間隔が一定(20〜40フレーム)なら終了コード0"""
import glob, sys
d = sys.argv[1]; x0, y0, x1, y1 = (int(v) for v in sys.argv[2:6]) if len(sys.argv) >= 6 else (16, 16, 24, 32)
seq = []
for fn in sorted(glob.glob(d + '/*.ppm')):
    b = open(fn, 'rb').read().split(b'\n', 3); w = int(b[1].split()[0]); px = b[3]
    seq.append(sum(px[(y * w + x) * 3 + c] for y in range(y0, y1) for x in range(x0, x1) for c in range(3)))
mx = max(seq); on = [v > mx / 2 for v in seq]
ch = [i for i in range(1, len(on)) if on[i] != on[i - 1]]
iv = [b - a for a, b in zip(ch, ch[1:])]
print('toggles', len(ch), 'intervals', iv)
sys.exit(0 if len(ch) >= 3 and iv and all(20 <= v <= 40 for v in iv) else 1)
