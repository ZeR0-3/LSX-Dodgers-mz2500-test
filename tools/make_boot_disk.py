#!/usr/bin/env python3
"""LSX-Dodgers MZ-2500 起動ディスク(標準LSX形式 2DD 80cyl x 2面 x 9sec x 512B)を作る。

  論理セクタ(LSN, 512B)  L0   : ブートセクタ(BPB。予約セクタ=36)
                          L1-8 : 未使用(予約)
                          L9-17: 〔IPL用トラック〕 cyl0/head1 を 256Bx16 に差し替え(レコード0-15)
                          L18-35: 〔IPL用トラック〕 cyl1/head0,1 を 256Bx16 に差し替え(レコード32-63)
                          L36-41: FAT x2 (3sec x 2)   L42-48: ルートDIR(112エント)   L49-: データ
  * LD2500.BIN(システム)は先頭クラスタ(L49)から連続配置される通常ファイル
  * IPL用トラックのデータは補数(MZ-2500のIPLが IPLPRO を検査する前提)。標準領域は素のデータ
  * IPLレコードr -> D88位置 i=r^10h : cyl=i//32, head=(i//16)&1, sec=i%16+1
使い方:
  make_boot_disk.py out.d88 LD2500.BIN boot_payload.bin [--import ldsys.d88] [--name LSX2500]
"""
import struct, sys, argparse
BPS, SPT, CYLS, HEADS = 512, 9, 80, 2
TOTSEC = SPT * CYLS * HEADS
RSV, FATSZ, NFAT, ROOTENT = 36, 3, 2, 112
ROOTSEC = ROOTENT * 32 // BPS
FAT0 = RSV
ROOT0 = RSV + FATSZ * NFAT
DATA0 = ROOT0 + ROOTSEC
SECPCL = 2
NCL = (TOTSEC - DATA0) // SECPCL

def lsn_of_cluster(c): return DATA0 + (c - 2) * SECPCL

def build_ipl_header(start=0x8000, rec=32, name=b'LSX-DODGERS'):
    h = bytearray(256)
    h[0] = 1; h[1:7] = b'IPLPRO'; h[7:7 + len(name) + 1] = name + b'\r'
    h[0x18:0x1A] = start.to_bytes(2, 'little'); h[0x1E:0x20] = rec.to_bytes(2, 'little')
    h[0x20:0x23] = bytes([0x08, 0xFF, 0xFF])               # ページ08のみ(32レコード=8KB)
    h[0x30:0x37] = bytes([0x00, 0x01, 0x02, 0x03, 0x08, 0x05, 0x06])  # 起動時のバンク0-6
    return bytes(h)

def read_d88(fn):
    d = open(fn, 'rb').read(); offs = struct.unpack('<164I', d[0x20:0x2B0]); secs = {}
    for o in offs:
        if not o: continue
        p = o
        ns = struct.unpack('<H', d[p + 4:p + 6])[0]
        for _ in range(ns):
            C, H, R, N, ns2, den, dele, st, sz = struct.unpack('<BBBBHBBBxxxxxH', d[p:p + 16])
            secs[(C, H, R)] = d[p + 16:p + 16 + sz]; p += 16 + sz
    return secs

def import_files(fn, skip=('LD.BIN', 'LD88.BIN', 'LDMSX.BIN', 'HDD.COM', 'M8A40.COM', 'M8A80.COM', 'LA.COM')):  # 後者4つは原本リポジトリにソースが無い他者のツール(LD-hdd, M8A Graphic Loader 等)
    """標準LSXディスク(2D)から通常ファイルを取り出す: [(name8, ext3, attr, data)]"""
    s = read_d88(fn)
    def lsn(L): t, r = divmod(L, 9); return s.get((t >> 1, t & 1, r + 1), b'\0' * 512)
    fat = b''.join(lsn(i) for i in (1, 2))
    def nxt(c):
        o = c * 3 // 2; v = fat[o] | fat[o + 1] << 8
        return (v >> 4) if c & 1 else (v & 0xFFF)
    out = []
    for L in range(5, 12):
        b = lsn(L)
        for i in range(0, 512, 32):
            e = b[i:i + 32]
            if e[0] in (0, 0xE5) or e[11] & 0x18: continue
            nm, ext = e[:8], e[8:11]
            if (nm.decode('latin1').rstrip() + '.' + ext.decode('latin1').rstrip()) in skip: continue
            cl = struct.unpack('<H', e[26:28])[0]; size = struct.unpack('<I', e[28:32])[0]
            data = b''
            while 2 <= cl < 0xFF0 and len(data) < size:
                data += lsn(12 + (cl - 2) * 2) + lsn(12 + (cl - 2) * 2 + 1); cl = nxt(cl)
            data = data[:size]
            if (nm.decode('latin1').rstrip(), ext.decode('latin1').rstrip()) == ('FORMAT', 'COM'): data = patch_format_com(data)
            out.append((nm, ext, e[11], data))
    return out

# FORMAT.COM v1.22 は BDOS 6Fh の機種ID(L)が 0(X1)/1(MZ-700)/2(PC-88) のときだけ物理フォーマットに進み、
# それ以外は論理フォーマットのみ。本移植の機種IDは 4(MODE.COMがMZ-700扱い(1)だと画面を壊すため 1 にできない)。
# 判定の `CP 1` を `CP 4` に1バイト変えて、機種ID 4 のときも物理フォーマット(WTTRK)に進ませる。
# 該当バイト列が(ちょうど1か所)見つからなければ何もしない。環境変数 LSX_NO_FORMAT_PATCH=1 で無効。
_FMT_PAT = bytes.fromhex('7DB7283CFE012838FE0228 03C31B03'.replace(' ', ''))   # LD A,L / OR A / JR Z / CP 1 / JR Z / CP 2 / JR Z / JP 031Bh
def patch_format_com(data):
    import os
    if os.environ.get('LSX_NO_FORMAT_PATCH'): return data
    if data.count(_FMT_PAT) != 1:
        print('note: FORMAT.COM のパッチ位置が見つからないため未パッチ (物理フォーマットは機種ID 0/1/2 のみ)'); return data
    i = data.index(_FMT_PAT) + 5          # `CP 1` の即値
    assert data[i] == 1
    print('FORMAT.COM: 機種ID判定 CP 1 -> CP 4 (file offset 0x%X)' % i)
    return data[:i] + bytes([4]) + data[i + 1:]

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('out'); ap.add_argument('sysbin'); ap.add_argument('payload')
    ap.add_argument('--import', dest='imp'); ap.add_argument('--name', default='LSX2500')
    a = ap.parse_args()
    sysbin = open(a.sysbin, 'rb').read(); payload = open(a.payload, 'rb').read()
    assert len(payload) <= 8192, 'ローダが8KBを超えています'
    payload = payload.ljust(8192, b'\0')
    img = bytearray(TOTSEC * BPS)
    # ブートセクタ(BPB) -- X1/MZで作った標準ディスクと同じ形
    bs = bytearray(BPS)
    bs[0:3] = b'\xEB\xFE\x90'; bs[3:11] = b'LD      '
    bs[11:13] = struct.pack('<H', BPS); bs[13] = SECPCL; bs[14:16] = struct.pack('<H', RSV)
    bs[16] = NFAT; bs[17:19] = struct.pack('<H', ROOTENT); bs[19:21] = struct.pack('<H', TOTSEC)
    bs[21] = 0xF9; bs[22:24] = struct.pack('<H', FATSZ); bs[24:26] = struct.pack('<H', SPT)
    bs[26:28] = struct.pack('<H', HEADS); bs[31] = 0xC9
    img[0:BPS] = bs
    # ファイル配置
    files = [(b'LD2500  ', b'BIN', 0x20, sysbin)] + (import_files(a.imp) if a.imp else [])
    fat = bytearray(FATSZ * BPS); fat[0:3] = b'\xF9\xFF\xFF'
    def setfat(n, v):
        o = n * 3 // 2
        if n & 1: fat[o] = (fat[o] & 0x0F) | ((v & 0xF) << 4); fat[o + 1] = v >> 4
        else: fat[o] = v & 0xFF; fat[o + 1] = (fat[o + 1] & 0xF0) | (v >> 8)
    root = bytearray(ROOTSEC * BPS); nxtc = 2; ent = 0
    for nm, ext, attr, data in files:
        ncl = max(1, -(-len(data) // (SECPCL * BPS))); first = nxtc
        assert nxtc + ncl - 2 <= NCL, 'ディスクがいっぱいです'
        for k in range(ncl):
            c = nxtc + k; setfat(c, c + 1 if k < ncl - 1 else 0xFFF)
            chunk = data[k * SECPCL * BPS:(k + 1) * SECPCL * BPS]
            o = lsn_of_cluster(c) * BPS; img[o:o + len(chunk)] = chunk
        e = bytearray(32); e[0:8] = nm; e[8:11] = ext; e[11] = attr
        e[22:24] = struct.pack('<H', 0); e[24:26] = struct.pack('<H', 0x2100)
        e[26:28] = struct.pack('<H', first); e[28:32] = struct.pack('<I', len(data))
        root[ent * 32:(ent + 1) * 32] = e; ent += 1; nxtc += ncl
    assert ent <= ROOTENT
    for k in range(NFAT): o = (FAT0 + k * FATSZ) * BPS; img[o:o + len(fat)] = fat
    o = ROOT0 * BPS; img[o:o + len(root)] = root
    # D88: 標準トラック
    tracks = {}
    for t in range(CYLS * HEADS):
        c, h = divmod(t, 2); secs = []
        for r in range(SPT):
            L = t * SPT + r; secs.append((c, h, r + 1, 2, bytes(img[L * BPS:(L + 1) * BPS])))
        tracks[t] = secs
    # IPLトラックを 256Bx16 に差し替え(データは補数)
    rec = {0: build_ipl_header()}
    for q in range(32): rec[32 + q] = payload[q * 256:(q + 1) * 256]
    ipl_tracks = {}
    for r in range(64):
        data = rec.get(r, bytes(256)); i = r ^ 0x10; c, h, s = i // 32, (i // 16) & 1, i % 16 + 1
        ipl_tracks.setdefault(c * 2 + h, []).append((c, h, s, 1, bytes(b ^ 0xFF for b in data)))
    for t, secs in ipl_tracks.items():
        if not any(len(v) for v in secs): continue
        if t in (1, 2, 3): tracks[t] = sorted(secs, key=lambda x: x[2])
    # D88書き出し
    body = []; offs = []; pos = 0x2B0
    for t in range(CYLS * HEADS):
        offs.append(pos); blk = b''
        for (c, h, s, n, data) in tracks[t]:
            blk += struct.pack('<BBBBHBBB5xH', c, h, s, n, len(tracks[t]), 0x00, 0, 0, len(data)) + data
        body.append(blk); pos += len(blk)
    offs += [0] * (164 - len(offs))
    hdr = a.name.encode().ljust(17, b'\0') + bytes(9) + bytes([0, 0x10]) + struct.pack('<I', pos) + b''.join(struct.pack('<I', o) for o in offs)
    assert len(hdr) == 0x2B0
    open(a.out, 'wb').write(hdr + b''.join(body))
    free = (NCL - (nxtc - 2)) * SECPCL * BPS
    print('wrote %s: %d files, system LSN %d (%d sectors), free %d bytes' % (a.out, len(files), lsn_of_cluster(2), -(-len(sysbin) // BPS), free))
if __name__ == '__main__': main()
