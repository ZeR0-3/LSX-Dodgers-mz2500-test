#!/usr/bin/env bash
# dist/ の4種類をエミュレータ(実IPL)で起動して DIR/COPY を確認する。全部通れば PASS
# 使い方: tools/test_all.sh <distdir>   (事前に source <作業dir>/env.sh)
set -uo pipefail
D=$1; HERE=$(cd "$(dirname "$0")" && pwd); rc=0
python3 "$HERE/make_blank_disk.py" /tmp/_blank2dd.d88 2dd >/dev/null
python3 "$HERE/make_blank_disk.py" /tmp/_blank2d.d88 2d >/dev/null
for f in "$D"/LSX2500_*.d88; do
  for b in /tmp/_blank2dd.d88:729088 /tmp/_blank2d.d88:361472; do
    disk=${b%%:*}; want=${b##*:}
    out=$("$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --disk-b "$disk" --frames 2000 \
      --type 'dir ld2500.bin\r:700' --type 'copy a:type.com b:\r:900' --type 'dir b:\r:1200' --screen-report 2>&1 | grep '^screen:')
    if echo "$out" | grep -q "LD2500.BIN" && echo "$out" | grep -q "TYPE.COM" && echo "$out" | grep -q "$want free"; then
      echo "PASS $(basename $f) + $(basename $disk)"; else echo "FAIL $(basename $f) + $(basename $disk)"; echo "$out" | head -12; rc=1; fi
  done
done
# ディスクが無いドライブへのアクセスはタイムアウトして Error! になり、システムが続行できること
# (E1h bit0 の時間基準が止まっているとここでハングする。C6h bit3=VBLANK許可が必要)
for f in "$D"/LSX2500_*.d88; do
  out=$("$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --frames 1500 \
    --type 'dir b:\r:700' --type 'dir ld2500.bin\r:1100' --screen-report 2>&1 | grep '^screen:')
  if echo "$out" | grep -q "Error!" && echo "$out" | grep -q "A:LD2500.BIN"; then echo "PASS $(basename $f) (B:にディスク無し)"
  else echo "FAIL $(basename $f) (B:にディスク無し)"; echo "$out" | head -8; rc=1; fi
done

# 物理フォーマット(FORMAT.COM -> WTTRK): 未フォーマットのD88を物理+論理フォーマットし、標準値の空き容量になること
# (FORMAT.COM は取り込み時に機種ID判定を1バイトパッチしてある: tools/make_boot_disk.py)
python3 "$HERE/make_blank_disk.py" /tmp/_unf2dd.d88 unf2dd >/dev/null
python3 "$HERE/make_blank_disk.py" /tmp/_unf2d.d88 unf2d >/dev/null
for f in "$D"/LSX2500_*.d88; do
  for b in /tmp/_unf2dd.d88:1:730112 /tmp/_unf2d.d88:0:362496; do
    IFS=: read disk kind want <<<"$b"
    rm -f /tmp/_fmt_out.d88
    "$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --disk-b "$disk" --disk-save 1:/tmp/_fmt_out.d88 --frames 10000 \
      --type 'format b:\r:600' --type "$kind:800" --type '\r:1000' >/dev/null 2>&1
    out=$("$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --disk-b /tmp/_fmt_out.d88 --frames 1500 \
      --type 'dir b:\r:700' --type 'copy a:type.com b:\r:900' --type 'dir b:\r:1200' --screen-report 2>&1 | grep '^screen:')
    if echo "$out" | grep -q "$want free" && echo "$out" | grep -q "TYPE.COM"; then echo "PASS $(basename $f) 物理フォーマット $(basename $disk)"
    else echo "FAIL $(basename $f) 物理フォーマット $(basename $disk)"; echo "$out" | head -8; rc=1; fi
  done
done
# MODE.COM は機種ID未対応として何もせず終了し、画面を壊さないこと(機種IDを1にすると壊れる: HANDOFF §5)
for f in "$D"/LSX2500_*.d88; do
  out=$("$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --frames 1200 \
    --type 'mode 40\r:500' --type 'dir ld2500.bin\r:800' --screen-report 2>&1 | grep '^screen:')
  if echo "$out" | grep -q "A:LD2500.BIN" && echo "$out" | grep -q "A>mode 40"; then echo "PASS $(basename $f) MODE.COM無害"
  else echo "FAIL $(basename $f) MODE.COM無害"; echo "$out" | head -8; rc=1; fi
done

# カーソル点滅: プロンプトで待機中にカーソルセルが約30フレーム間隔で明暗を繰り返すこと
for f in "$D"/LSX2500_80col.d88 "$D"/LSX2500_40col.d88 "$D"/LSX2500_80col_noiocs.d88; do
  rm -rf /tmp/_blink && mkdir -p /tmp/_blink
  "$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --frames 400 --frame-dump /tmp/_blink:300:399 >/dev/null 2>&1
  case $(basename $f) in *80col*) box="16 16 24 32";; *) box="32 16 48 32";; esac   # 40桁は1文字=16ドット幅
  if python3 "$HERE/check_blink.py" /tmp/_blink $box >/tmp/_blink.log; then echo "PASS $(basename $f) カーソル点滅 ($(cat /tmp/_blink.log))"
  else echo "FAIL $(basename $f) カーソル点滅"; cat /tmp/_blink.log; rc=1; fi
done

# ワイルドカード: SHIFTを押したまま * / ? を入力する(--type は SHIFT 保持が4フレームと短く文字が化けるので --key-pulse で明示)
# SHIFT=行11/bit2, '*'=行9/bit2, '?'=行4/bit0
for f in "$D"/LSX2500_*.d88; do
  o1=$("$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --frames 1500 --type 'dir :600' --key-pulse 11,2:640:12 --key-pulse 9,2:643:4 --type '.com\r:700' --screen-report 2>&1 | grep '^screen:')
  o2=$("$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --frames 1500 --type 'dir ma:600' --key-pulse 11,2:640:12 --key-pulse 4,0:643:4 --type '.com\r:700' --screen-report 2>&1 | grep '^screen:')
  if echo "$o1" | grep -q "TYPE.COM" && ! echo "$o1" | grep -q "LD2500.BIN" && echo "$o2" | grep -q "A:MAG.COM" && ! echo "$o2" | grep -q "MAGA.COM"; then echo "PASS $(basename $f) ワイルドカード(* ?)"
  else echo "FAIL $(basename $f) ワイルドカード(* ?)"; rc=1; fi
done

# LOCK(列11 bit1)で英小文字が大文字になり、KANA(列11 bit3)で半角カナが入力できること
# '/'=行4/bit0 -> ﾒ, 'H'=行5/bit0 -> ｸ, 'S'=行6/bit3 -> ﾄ, SHIFT+'Z'(行7/bit2... 下の表記参照) は省略
for f in "$D"/LSX2500_*.d88; do
  o1=$("$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --frames 900 --key-pulse 11,1:500:300 --type 'abc:600' --screen-report 2>&1 | grep '^screen:')
  o2=$("$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --frames 900 --key-pulse 11,3:500:300 --key-pulse 4,0:600:6 --key-pulse 5,0:620:6 --key-pulse 6,3:640:6 --screen-report 2>&1 | grep '^screen:')
  if echo "$o1" | grep -q "A>ABC" && echo "$o2" | grep -q "A>ﾒｸﾄ"; then echo "PASS $(basename $f) LOCK/KANA"
  else echo "FAIL $(basename $f) LOCK/KANA"; echo "$o1" | sed -n 2p; echo "$o2" | sed -n 2p; rc=1; fi
done

# ブートローダ: LD2500.BIN のセクタが読めない(CRCエラー/RNF)とき、リトライの後 'E' を出して止まる(ハングしない・暴走しない)
for f in "$D"/LSX2500_80col.d88; do
  for m in crc rnf; do
    python3 "$HERE/make_bad_boot_disk.py" "$f" /tmp/_bad_$m.d88 $m
    out=$("$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a /tmp/_bad_$m.d88 --frames 3000 --screen-report 2>&1 | grep '^screen:')
    if echo "$out" | grep -q "IPL is loading" && echo "$out" | grep -qE "^screen: E +$" && ! echo "$out" | grep -q "LSX-Dodgers"; then echo "PASS ブート時セクタ不良($m) -> E 表示"
    else echo "FAIL ブート時セクタ不良($m)"; echo "$out" | head -4; rc=1; fi
  done
done

# OS動作中にデータセクタが読めない(CRCエラー)とき、COPYが Error! で終わり、その後もシステムが使えること
for f in "$D"/LSX2500_*.d88; do
  python3 "$HERE/make_bad_boot_disk.py" "$f" /tmp/_bad_data.d88 data
  out=$("$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a /tmp/_bad_data.d88 --disk-b /tmp/_blank2dd.d88 --frames 6000 \
    --type 'copy a:type.com b:\r:700' --type 'dir ld2500.bin\r:4000' --screen-report 2>&1 | grep '^screen:')
  if echo "$out" | grep -q "Error!" && echo "$out" | grep -q "A:LD2500.BIN"; then echo "PASS $(basename $f) データ読み出しエラーから復帰"
  else echo "FAIL $(basename $f) データ読み出しエラーから復帰"; echo "$out" | head -8; rc=1; fi
done

# MON: IOCSのモニタ(機能00h)が起動し(メモリ表示 D0 ができ)、R で LSX に戻って DIR が使えること
for f in "$D"/LSX2500_*.d88; do
  o1=$("$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --frames 1300 --type 'mon\r:800' --type 'd0\r:1100' --screen-report 2>&1 | grep '^screen:')
  o2=$("$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --frames 2400 --type 'mon\r:800' --type 'd0\r:1100' --type 'r\r:1500' --type 'dir ld2500.bin\r:2000' --screen-report 2>&1 | grep '^screen:')
  if echo "$o1" | grep -q ":0000=80 BB" && echo "$o2" | grep -q "A:LD2500.BIN" && ! echo "$o2" | grep -q "Error!"; then echo "PASS $(basename $f) MON(IOCSモニタ)往復"
  else echo "FAIL $(basename $f) MON(IOCSモニタ)往復"; echo "$o1" | head -4; echo "$o2" | head -4; rc=1; fi
done

# ビープ(Ctrl+G): PC2(E3h bit set/reset)が約953Hz(IOCSのBELLと同じ周期 6294T@6MHz)で49周期。周期は±2%、回数は49
for f in "$D"/LSX2500_80col.d88; do
  r=$(MZ_TRACE_ALL=1 "$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --frames 900 --key-pulse 11,4:600:14 --key-pulse 4,7:603:6 --trace-io 2>&1 \
    | python3 -c "
import sys
t=[int(l.split()[1]) for l in sys.stdin if l.startswith('[iot]') and l.split()[4:6]==['OUT','E3'] and l.split()[7] in ('05','04')]
n=len(t)//2
per=(t[2]-t[0]) if len(t)>2 else 0
print('OK' if n==49 and abs(per-6294)<=6294*0.02 else 'NG', n, per)")
  if [ "${r%% *}" = OK ]; then echo "PASS $(basename $f) ビープ($r)"; else echo "FAIL $(basename $f) ビープ($r)"; rc=1; fi
done

# ドライブ3,4(C:,D:)に実体が無いとき、Error! になってシステムが続行できること(エミュレータのFDDは2台のみ。実機の外付けFDDは未確認)
for f in "$D"/LSX2500_*.d88; do
  out=$("$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --frames 3500 \
    --type 'dir c:\r:700' --type 'dir d:\r:1400' --type 'dir ld2500.bin\r:2300' --screen-report 2>&1 | grep '^screen:')
  if [ "$(echo "$out" | grep -c 'Error!')" = 2 ] && echo "$out" | grep -q "A:LD2500.BIN"; then echo "PASS $(basename $f) C:,D:(実体なし)でも続行"
  else echo "FAIL $(basename $f) C:,D:(実体なし)"; echo "$out" | head -8; rc=1; fi
done

# F:(拡張RAMのRAMディスク)と E:(EMM)。INITが検出してDPBを設定する(E:のFATLN=F280h: 640KB=4セクタ, F:のFATLN=F2A0h: 1)。EMMなし(--no-emm)ならE:は0
for f in "$D"/LSX2500_*.d88; do
  m=$("$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --frames 800 --memory-report F280 --memory-report F2A0 2>&1 | tr '\n' ' ')
  n=$("$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --no-emm --frames 800 --memory-report F280 --memory-report F2A0 2>&1 | tr '\n' ' ')
  if echo "$m" | grep -q "memory\[f280\]=04" && echo "$m" | grep -q "memory\[f2a0\]=01" && echo "$n" | grep -q "memory\[f280\]=00"; then echo "PASS $(basename $f) E:,F:の検出(EMMあり/なし)"
  else echo "FAIL $(basename $f) E:,F:の検出"; echo "$m"; echo "$n"; rc=1; fi
done

# F:,E: へ複数クラスタのファイルをコピーして B: へ戻し、内容がバイト単位で一致すること(E:は FORMAT E: が必要)
for f in "$D"/LSX2500_*.d88; do
  want=$(python3 "$HERE/d88_cat.py" "$f" LD2500.BIN | md5sum)
  for drv in f e; do
    python3 "$HERE/make_blank_disk.py" /tmp/_mb.d88 2dd >/dev/null
    pre=(); [ $drv = e ] && pre=(--type 'format e:\r:500' --type '\r:800' --type '\r:1000')
    "$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --disk-b /tmp/_mb.d88 --disk-save 1:/tmp/_mo.d88 --frames 6000 "${pre[@]}" \
      --type "copy a:ld2500.bin $drv:\r:1600" --type "copy $drv:ld2500.bin b:x.bin\r:3200" >/dev/null 2>&1
    got=$(python3 "$HERE/d88_cat.py" /tmp/_mo.d88 X.BIN | md5sum)
    if [ "$got" = "$want" ]; then echo "PASS $(basename $f) ${drv^^}: 経由のコピーが一致"; else echo "FAIL $(basename $f) ${drv^^}: 経由のコピー"; rc=1; fi
  done
done

# F:を使い切り、E:は64KB/128KBを超えるまで書いて、最初と最後のファイルが一致すること(アドレス上位の検証)
for f in "$D"/LSX2500_80col.d88; do
  want=$(python3 "$HERE/d88_cat.py" "$f" LD2500.BIN | md5sum)
  for drv in f e; do
    N=12; t=600; args=()
    if [ $drv = e ]; then N=15; t=1300; args+=(--type 'format e:\r:500' --type '\r:800' --type '\r:1000'); fi
    for i in $(seq 1 $N); do args+=(--type "copy a:ld2500.bin $drv:f$i.bin\r:$t"); t=$((t+300)); done
    args+=(--type "copy $drv:f$N.bin b:last.bin\r:$t"); t=$((t+400))
    args+=(--type "copy $drv:f1.bin b:first.bin\r:$t"); t=$((t+400))
    python3 "$HERE/make_blank_disk.py" /tmp/_mb.d88 2dd >/dev/null
    "$LSX_CLI" --real-ipl --rom-dir "$LSX_ROMDIR" --disk-a "$f" --disk-b /tmp/_mb.d88 --disk-save 1:/tmp/_mo.d88 --frames $((t+300)) "${args[@]}" >/dev/null 2>&1
    g1=$(python3 "$HERE/d88_cat.py" /tmp/_mo.d88 FIRST.BIN | md5sum); g2=$(python3 "$HERE/d88_cat.py" /tmp/_mo.d88 LAST.BIN | md5sum)
    if [ "$g1" = "$want" ] && [ "$g2" = "$want" ]; then echo "PASS $(basename $f) ${drv^^}: ${N}ファイル(全域)の先頭と末尾が一致"; else echo "FAIL $(basename $f) ${drv^^}: 全域"; rc=1; fi
  done
done
exit $rc
