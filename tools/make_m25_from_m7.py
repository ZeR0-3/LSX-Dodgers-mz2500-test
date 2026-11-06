#!/usr/bin/env python3
"""M7IO.ASM / M7DISK.ASM から M25IO.ASM / M25DISK.ASM を生成する(差分が追跡できるよう置換で作る)。"""
import sys
src, dst = sys.argv[1], sys.argv[2]
def rd(n): return open(f'{src}/{n}', encoding='utf-8').read()
def rep(t, a, b, cnt=1):
    assert t.count(a) == cnt, (t.count(a), a[:60])
    return t.replace(a, b)

# ---------------- IO ----------------
t = rd('M7IO.ASM')
t = rep(t, ';\tMZ-700/1500\n', ';\tMZ-2500\n')

# FLGET: カーソルはリバース表示(アトリビュートbit6反転)。VBLANKを数えて約0.5秒ごとに切り替えて点滅させる
# (ハードのBL属性は字形のドットを消すだけで、空白セルのカーソルは点滅しない。IOCSのCURBLはIOCS用RAM(2000h台)と
#  タイマ割り込みを使うが、LSXはTPAにそのRAMを使い割り込みも止めているので流用できない)
a = t.index('FLGET:\n')
b = t.index('_SYS0A:')
t = t[:a] + '''FLGET:
	CALL	_FFLUSH
	PUSH	HL
	PUSH	BC
	LD	HL,(_TXADR)
	LD	A,H
	ADD	A,0E8H		;アトリビュートプレーン
	LD	H,A
	LD	(FLADR),HL
	CALL	RDMMIO
	LD	(FLSMC),A
	XOR	040H		;RV反転でカーソル表示
	CALL	WRMMIO
	LD	B,FLBLNK	;切り替えまでのVBLANK数
	LD	C,0		;前回のVBLANK状態
FLGET1:
	CALL	_INKEY
	JR	NZ,FLGET2
	CALL	RD556VSYNC
	AND	080H
	CP	C
	LD	C,A
	JR	Z,FLGET1
	OR	A		;VBLANKの立ち上がりだけ数える
	JR	Z,FLGET1
	DJNZ	FLGET1
	LD	B,FLBLNK
	PUSH	BC
	LD	HL,(FLADR)
	CALL	RDMMIO
	XOR	040H		;RV切り替え(点滅)
	CALL	WRMMIO
	POP	BC
	JR	FLGET1
FLGET2:
	PUSH	AF
	LD	HL,(FLADR)
	LD	A,0		;自己書き換え
FLSMC	EQU	$-1
	CALL	WRMMIO
	POP	AF
	POP	BC
	POP	HL
	RET
FLADR:	DW	0
FLBLNK	EQU	30

''' + t[b:]

# ANK: ASCII/カナはコードをそのままVRAMへ(変換表なし)
a = t.index('ANK:\n')
b = t.index('PRINTE5:\n')
t = t[:a] + '''ANK:
	LD	A,(_COLORF)
	LD	C,A
	LD	HL,(_TXADR)
	LD	A,H
	ADD	A,0E0H
	LD	H,A
	CALL	IO_PRINT	;E=文字コード
	CALL	CTRL1C
''' + t[b:]

# CTRL02(削除)
t = rep(t, '\tLD\tB,0D0H\n\tLD\tHL,(_TXADR)\n\tADD\tHL,BC\n', '\tLD\tB,0E0H\n\tLD\tHL,(_TXADR)\n\tADD\tHL,BC\n')
t = rep(t, '\tXOR\tA\t\t;A:Text\n\tCALL\tIO_INSBS\n\tPOP\tDE\n\tRET\n',
        '\tLD\tA,080H\t\t;A:Text1(消去セル)\n\tLD\tE,08CH\t\t;E:Text2\n\tCALL\tIO_INSBS\n\tPOP\tDE\n\tRET\n')
# CLLINE
t = rep(t, 'C08X1:\n\tLD\tHL,(_TXADR)\n\tLD\tA,H\n\tADD\tA,0D0H\n', 'C08X1:\n\tLD\tHL,(_TXADR)\n\tLD\tA,H\n\tADD\tA,0E0H\n')
# ビープ: 8255 PC2(SOUND)をビット操作で鳴らす
a = t.index('CTRL07:\n')
b = t.index('INSERT:\n')
t = t[:a] + '''CTRL07:
	LD	C,49
C07X0:
	LD	A,5
	OUT	(0E3H),A	;PC2(SOUND)=1
	LD	B,240
C07X1:
	DJNZ	C07X1
	LD	A,4
	OUT	(0E3H),A	;PC2(SOUND)=0
	LD	B,240
C07X2:
	DJNZ	C07X2
	DEC	C
	JR	NZ,C07X0
	RET

''' + t[b:]
# INSERT
t = rep(t, '\tLD\tHL,(_TXADR)\n\tLD\tA,H\n\tADD\tA,0D0H\n\tLD\tH,A\n\tLD\tA,(_COLORF)\t;C:Color\n',
           '\tLD\tHL,(_TXADR)\n\tLD\tA,H\n\tADD\tA,0E0H\n\tLD\tH,A\n\tLD\tA,(_COLORF)\t;C:Color\n')
t = rep(t, '''\tXOR\tA\t\t;A:Text
\tCALL\tIO_INSBS
\tOR\tA
\tJR\tNZ,INS1
''', '''\tLD\tA,080H\t\t;A:Text1(消去セル)
\tLD\tE,08CH\t\t;E:Text2
\tCALL\tIO_INSBS
\tLD\tE,A		;押し出されたセルが空白か(Text1=80H-83H かつ Text2=8CH)
\tAND\t0FCH
\tCP\t080H
\tJR\tNZ,INSB1
\tLD\tA,B
\tCP\t08CH
INSB1:
\tLD\tA,E
\tJR\tNZ,INS1
''')
t = rep(t, '''INS1:
\tLD\tB,WIDTH
\tPUSH\tAF
''', '''INS1:
\tLD\tE,B
\tLD\tB,WIDTH
\tPUSH\tAF
''')
# SCR
t = rep(t, '\tLD\tDE,0D000H\n\tLD\tHL,0D000H+WIDTH\n', '\tLD\tDE,0E000H\n\tLD\tHL,0E000H+WIDTH\n')
# GETL
t = rep(t, '\tLD\tC,L\n\tLD\tA,H\n\tADD\tA,0D0H\n\tLD\tB,A\n', '\tLD\tC,L\n\tLD\tA,H\n\tADD\tA,0E0H\n\tLD\tB,A\n')
# CHKEY 以降を置換 (CHKEY ... C_MON 終端まで)
a = t.index('CHKEY:\n')
t = t[:a] + '''CHKEY:
	PUSH	BC
	LD	A,11
	CALL	RDKEYDATA	;列11: D2=SHIFT D4=CTRL
	LD	C,0FFH
	BIT	2,A
	JR	NZ,CHKS1
	RES	0,C		;SHIFT
CHKS1:
	BIT	3,A
	JR	NZ,CHKSK
	RES	1,C		;KANA
CHKSK:
	BIT	4,A
	JR	NZ,CHKS2
	RES	6,C		;CTRL
CHKS2:
	LD	A,3
	CALL	RDKEYDATA	;列3: D7=BREAK
	BIT	7,A
	JR	NZ,CHKS3
	RES	7,C		;BREAK
CHKS3:
	LD	A,(_KEYST)
	CP	C
	LD	A,C
	LD	(_KEYST),A
	JR	Z,KEYST2
	CALL	GETKEYD
	JR	Z,KEYST1
	XOR	A
	LD	(_KEYD),A
	DB	03EH
	SCF
	LD	(GETKEYD_SWC),A
KEYST1:
	LD	A,C
KEYST2:
	BIT	7,A
	JP	Z,INKEYB
	PUSH	HL
	PUSH	DE
	LD	C,0
	LD	HL,KEY_TABLE
	BIT	1,A
	JR	NZ,CHKEYA
	LD	HL,KANA_TABLE
CHKEYA:
	BIT	0,A
	JR	NZ,CHKEY0
	LD	HL,SHIFT_TABLE
	BIT	1,A
	JR	NZ,CHKEY0
	LD	HL,KSHIFT_TABLE
CHKEY0:
	BIT	6,A
	JR	NZ,CHKEY1
	LD	HL,CTRL_TABLE
CHKEY1:
	LD	A,C
	CALL	RDKEYDATA
	LD	D,A
	LD	B,8
CHKEY2:
	SLA	D
	JR	C,CHKEY4	;bit=1は押されていない(0=押下)
	LD	A,(HL)		;押されているキー
	OR	A
	JR	NZ,CHKEY3
CHKEY4:
	INC	HL
	DJNZ	CHKEY2
	INC	C
	LD	A,C
	CP	14
	JR	NZ,CHKEY1
	XOR	A
CHKEY3:
	PUSH	AF
	LD	A,11
	CALL	RDKEYDATA	;LOCK(列11 D1)なら英小文字を大文字に
	LD	D,A
	POP	AF
	BIT	1,D
	JR	NZ,CHKEY5
	CP	'a'
	JR	C,CHKEY5
	CP	'z'+1
	JR	NC,CHKEY5
	SUB	020H
CHKEY5:
	POP	DE
	POP	HL
	POP	BC
	JP	SETKEYD

SCRN:
	PUSH	BC
	PUSH	DE
	CALL	RDMMIO_BC	;Text1
	SRL	A
	SRL	A
	LD	E,A
	SET	4,B
	CALL	RDMMIO_BC	;Text2
	AND	3
	RRCA
	RRCA
	OR	E
	JR	NZ,SCRN1
	LD	A,020H		;未初期化セルは空白
SCRN1:
	POP	DE
	POP	BC
	RET

C_MON:
	JP	IO_MON
'''
open(f'{dst}/M25IO.ASM','w',encoding='utf-8').write(t)

# ---------------- DISK ----------------
# 標準LSXディスク(X1/MZ-700で作った2D/2DD)をそのまま読み書きするため、MZ-700版の動きを保つ。
#  - ヘッド: DDh bit0=トラックの偶奇(偶数=ヘッド0)
#  - データ: 反転バスなので読み書きでCPL(MZ-700版と同じ。ディスク上は素のデータ)
d = rd('M7DISK.ASM')
d = rep(d, ';\tMZ-700/1500\n', ';\tMZ-2500\n')
# 倍密度指定(DEh) とドライブ1-4(DCHのb1-b0。3,4は外付け。実機未確認)
d = rep(d, '\tLD\tA,(_DRIVE)\n\tCP\t4\n\tCCF\n\tRET\tC\n',
           '\tXOR\tA\n\tOUT\t(0DEH),A\t;倍密度\n\tLD\tA,(_DRIVE)\n\tCP\t4\t\t;ドライブ1-4(DCHのb1-b0)。3,4は外付け(実機未確認)\n\tCCF\n\tRET\tC\n')
open(f'{dst}/M25DISK.ASM','w',encoding='utf-8').write(d)
print('ok')
