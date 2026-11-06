#!/usr/bin/env bash
# 4種類の起動ディスクをビルドして dist/ に出力する
# 使い方: tools/build_all.sh <LSX-Dodgers原本dir(LD*.ASM)> <ldsys.d88(原本のシステムディスク。無ければ空文字)> <出力dir>
# 事前に source <作業dir>/env.sh (LSX_Z80ASM が必要)
set -euo pipefail
ORIG=$1; IMP=${2:-}; OUT=$3
HERE=$(cd "$(dirname "$0")/.." && pwd); mkdir -p "$OUT"
build() { n=$1; shift; LSX_IMPORT="$IMP" python3 "$HERE/build.py" "$ORIG" "$LSX_Z80ASM" "$OUT/_$n" "$@" | tail -2
          cp "$OUT/_$n/LSX2500.d88" "$OUT/LSX2500_$n.d88"; }
build 80col USE_TINIT COLS80 KEEP_ENV
build 40col USE_TINIT KEEP_ENV
build 40col_noiocs
build 80col_noiocs COLS80
ls -la "$OUT"/*.d88
