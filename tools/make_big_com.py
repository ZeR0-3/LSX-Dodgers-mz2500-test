#!/usr/bin/env python3
"""RAMディスクのテスト用: 約44KBのCOM。自分のデータ部の16bit和を計算して "LOAD OK"/"LOAD NG" を出し、終了する。
TPA全体(バンク0-5)へ読み込まれるので、RAMディスクドライバの窓バンク(5/3)の両方を通る。  使い方: make_big_com.py out.com [データ長。既定44000。52000だとC000h以降(RAMディスク旧版の中継バッファ位置)に届く]"""
import random, struct, sys
random.seed(2500); N = int(sys.argv[2]) if len(sys.argv) > 2 else 44000
data = bytes(random.randrange(256) for _ in range(N)); s = sum(data) & 0xFFFF
code = bytes([0x21]) + struct.pack('<H', 0x013B) + bytes([0x01]) + struct.pack('<H', N) + bytes([0x11, 0, 0,
 0x7E, 0x83, 0x5F, 0x8A, 0x93, 0x57, 0x23, 0x0B, 0x78, 0xB1, 0x20, 0xF4, 0x21]) + struct.pack('<H', s) + bytes([0xB7, 0xED, 0x52, 0x11]) + \
 struct.pack('<H', 0x012B) + bytes([0x28, 0x03, 0x11]) + struct.pack('<H', 0x0133) + bytes([0x0E, 0x09, 0xCD, 5, 0, 0xC3, 0, 0])
assert len(code) == 0x2B, hex(len(code))
open(sys.argv[1], 'wb').write(code + b'LOAD OK$' + b'LOAD NG$' + data)
