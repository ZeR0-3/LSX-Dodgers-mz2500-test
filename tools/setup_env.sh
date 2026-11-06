#!/usr/bin/env bash
# 開発環境を一から作る(z80asm と mz2500-web-emulator のCLI、ROMの配置)
# 使い方: tools/setup_env.sh <作業dir> <z88dk-*.tgz または z88dk の作業ツリー(git clone --depth 1 --recurse-submodules https://github.com/z88dk/z88dk.git)> <mz2500-web-emulator-main.zip> <ROMS.zip>
# 注意  : 最近の z88dk は最上位の Makefile 等が必要なので、tgz を作り直すより git clone した作業ツリーをそのまま渡すのが確実
# 出力  : <作業dir>/env.sh  (LSX_Z80ASM / LSX_CLI / LSX_ROMDIR / Z80_OZFILES を export する。source して使う)
# 注意  : 環境変数名を Z80ASM にしてはいけない(z80asm自身がこの名前を読んで誤動作する)
# 必要  : gcc g++ make perl python3 unzip tar (cmake は不要)
set -euo pipefail
W=$(mkdir -p "$1" && cd "$1" && pwd); Z88TGZ=$2; WEBZIP=$3; ROMZIP=$4
HERE=$(cd "$(dirname "$0")" && pwd)

echo "[1/3] z88dk の z80asm をビルド"
if [ -d "$Z88TGZ" ] && [ ! -e "$W/z88dk" ]; then ln -s "$(cd "$Z88TGZ" && pwd)" "$W/z88dk"; fi
if [ ! -x "$W/z88dk/src/z80asm/z88dk-z80asm" ] && [ -d "$W/z88dk/src/z80asm" ]; then
  (cd "$W/z88dk/src/z80asm" && make -j"$(nproc)" >"$W/z80asm_build.log" 2>&1) || { tail -20 "$W/z80asm_build.log"; exit 1; }
fi
if [ ! -x "$W/z88dk/src/z80asm/z88dk-z80asm" ]; then
  mkdir -p "$W/z88dk-x" && tar -xzf "$Z88TGZ" -C "$W/z88dk-x" z88dk/src z88dk/ext z88dk/lib
  rm -rf "$W/z88dk" && mv "$W/z88dk-x/z88dk" "$W/z88dk" && rmdir "$W/z88dk-x"
  (cd "$W/z88dk/src/z80asm" && make -j"$(nproc)" >"$W/z80asm_build.log" 2>&1) || { tail -20 "$W/z80asm_build.log"; exit 1; }
fi

echo "[2/3] mz2500-web-emulator の CLI をビルド(FDCトレースのパッチ付き)"
if [ ! -x "$W/mz2500w-cli" ]; then
  rm -rf "$W/webemu" && mkdir -p "$W/webemu" && unzip -q "$WEBZIP" -d "$W/webemu"
  SRC=$(ls -d "$W"/webemu/*/ | head -1)
  (cd "$SRC" && patch -p0 core/mz2500.cpp < "$HERE/webemu_fdctrace.patch" >/dev/null)
  mkdir -p "$W/obj"; cd "$SRC"; CXXF="-O2 -std=c++17 -I. -Ivendor -w"; objs=""
  for f in core/banked_memory core/cmt core/d88 core/dummy_ipl core/fdc_mb8877 core/mz2500 core/opn core/adpcm \
           core/printer core/renderer core/sasi core/z80_sio vendor/ymfm/ymfm_opn vendor/ymfm/ymfm_ssg \
           vendor/ymfm/ymfm_adpcm vendor/ymfm/ymfm_opl vendor/ymfm/ymfm_pcm cli/main; do
    o="$W/obj/$(echo $f | tr / _).o"; g++ $CXXF -c $f.cpp -o $o & objs="$objs $o"
  done
  gcc -O2 -std=c11 -I. -Ivendor -w -c vendor/z80/z80.c -o "$W/obj/z80.o" &
  wait
  g++ -O2 $objs "$W/obj/z80.o" -o "$W/mz2500w-cli"
fi

echo "[3/3] ROM を小文字名で配置"
mkdir -p "$W/roms" && python3 - "$ROMZIP" "$W/roms" <<'PY'
import sys, zipfile, os
z = zipfile.ZipFile(sys.argv[1])
for i in z.infolist():
    open(os.path.join(sys.argv[2], os.path.basename(i.filename).lower()), 'wb').write(z.read(i))
PY

cat > "$W/env.sh" <<ENV
export LSX_Z80ASM="$W/z88dk/src/z80asm/z88dk-z80asm"
export Z80_OZFILES="$W/z88dk/lib"
export LSX_CLI="$W/mz2500w-cli"
export LSX_ROMDIR="$W/roms"
ENV
echo "完了。 source $W/env.sh"
