
;	LSX-Dodgers IO
;	MZ-2500
;	テキストVRAM(ページ38h)をバンク7(0E000H-0FFFFH)に出し入れしてアクセスする。
;	VRAMを見ている間は0E000H-0FFFFH(ワーク・テーブル)が見えないので、
;	このファイルのルーチンは0E000H未満に置き、スタックも0E000H未満であること。
;
;	VRAMの構造(1文字=3プレーン,行間隔80バイト)
;	  +0000H テキスト1 : (コード AND 3FH) * 4   (16ライン文字モード: F7h bit0=0。偶数コード=R0)
;	  +0800H アトリビュート : bit7 BL / bit6 RV / bit2 G / bit1 R / bit0 B
;	  +1000H テキスト2 : 8CH + (コード / 64)
;	  消去セル/空白は 80H / 属性 / 8CH。8ライン文字モード(F7h bit0=1)では +2(R=1) が必要

IO_BDOS:
	JP	BDOS0

VRAM_ON:
	PUSH	AF
	LD	A,7
	OUT	(0B4H),A	;マッピングレジスタ(バンク7)
	LD	A,VRAM_PG
	OUT	(0B5H),A	;テキストVRAM
	POP	AF
	RET

VRAM_OFF:
	PUSH	AF
	LD	A,7
	OUT	(0B4H),A
	LD	A,RAM7_PG
	OUT	(0B5H),A	;RAM
	POP	AF
	RET

IO_CLR:
	CALL	VRAM_ON
C1AX1:
	LD	A,D
	ADD	A,0E0H
	LD	D,A
	LD	A,080H
	LD	(DE),A		;Text1
	SET	3,D
	LD	A,0		;自己書き換え
				;BDOS0+13Hが外部から書き換えされても動くようにする
ICSMC	EQU	$-1
	LD	(DE),A		;Attribute
	RES	3,D
	SET	4,D
	LD	A,08CH
	LD	(DE),A		;Text2
	LD	A,D
	SUB	0F0H
	LD	D,A
	INC	DE
	LD	HL,0-WIDTH*LINE
_NEG_PAGE_SWC	EQU	$-2
	ADD	HL,DE
	JR	NC,C1AX1
	CALL	VRAM_OFF
	POP	HL
	POP	DE
	EI
	RET

;	キーボード: A=ストローブ列(0-13) -> A=列のデータ(0=押されている)
;	PIO E8h: bit5=CH80(80桁なら1) bit4=1で列指定 bit3-0=列。上位3ビットは読み戻して保持
RDKEYDATA:
	PUSH	BC
	LD	B,A
	IN	A,(0E8H)	;E8hは読み戻せる(ROMのTWIDも読み戻して使う)
	AND	0E0H		;DISP/HCLG/CH80 を保持
	OR	010H		;bit4=1: 列指定
	OR	B
	OUT	(0E8H),A
	NOP
	NOP
	IN	A,(0EAH)
	POP	BC
	RET

;	A bit7 = VBLANK中=1  (8255 PB bit0 は /VBLANK: 0=ブランク中)
RD556VSYNC:
	IN	A,(0E1H)
	CPL
	RRCA
	RET

RDMMIO:
	DI
	CALL	VRAM_ON
	LD	A,(HL)
	CALL	VRAM_OFF
	EI
	RET

WRMMIO:
	DI
	CALL	VRAM_ON
	LD	(HL),A
	CALL	VRAM_OFF
	EI
	RET

RDMMIO_BC:
	DI
	CALL	VRAM_ON
	LD	A,(BC)
	CALL	VRAM_OFF
	EI
	RET

WRMMIO_BC:
	DI
	CALL	VRAM_ON
	LD	(BC),A
	CALL	VRAM_OFF
	EI
	RET

;	HL=0E000H+桁行オフセット, E=文字コード, C=属性
IO_PRINT:
	DI
	CALL	VRAM_ON
	LD	A,E
	ADD	A,A
	ADD	A,A
	LD	(HL),A		;Text1 (16ライン文字: R=0,x=0 の偶数コード)
	SET	3,H
	LD	(HL),C		;Attribute
	RES	3,H
	SET	4,H
	LD	A,E
	RLCA
	RLCA
	AND	3
	OR	08CH
	LD	(HL),A		;Text2
	CALL	VRAM_OFF
	EI
	RET

;	HL=0E000H+オフセット, B=個数, C=属性 を消去セルで埋める
IO_CLLINE:
	DI
	CALL	VRAM_ON
CLLINE1:
	LD	(HL),080H	;Text1
	SET	3,H
	LD	(HL),C		;Attribute
	RES	3,H
	SET	4,H
	LD	(HL),08CH	;Text2
	RES	4,H
	INC	HL
	DJNZ	CLLINE1
	CALL	VRAM_OFF
	EI
	RET

;	行内の挿入/削除(1セル=3プレーンを順送り)
;	入力 A=Text1, C=属性, E=Text2, B=個数, HL=開始位置(0E000H+),
;	     IO_INCDEC=INC HL(挿入)/DEC HL(削除)
;	出力 A=押し出されたText1, C=その属性, B=その Text2, HL=最後の次, D保存
IO_INSBS:
	DI
	CALL	VRAM_ON
	PUSH	DE
	LD	D,B
IO_INSBS1:
	LD	B,(HL)
	LD	(HL),A
	LD	A,B
	SET	3,H
	LD	B,(HL)
	LD	(HL),C
	LD	C,B
	RES	3,H
	SET	4,H
	LD	B,(HL)
	LD	(HL),E
	LD	E,B
	RES	4,H
IO_INCDEC	EQU	$	; 自己書き換え
	INC	HL		;INS->INC HL or BS->DEC HL
	DEC	D
	JR	NZ,IO_INSBS1
	LD	B,E
	POP	DE
	CALL	VRAM_OFF
	EI
	RET

IO_SCRUP:
	DI
	CALL	VRAM_ON
SCRUP1:
	JR	Z,SCRCL
	PUSH	DE
	PUSH	HL
	SET	3,D
	SET	3,H
	LD	BC,WIDTH
	LDIR			;Attribute
	POP	HL
	POP	DE
	PUSH	DE
	PUSH	HL
	SET	4,D
	SET	4,H
	LD	BC,WIDTH
	LDIR			;Text2
	POP	HL
	POP	DE
	LD	BC,WIDTH
	LDIR			;Text1
	DEC	A
	JR	SCRUP1

SCRCL:
	LD	B,WIDTH
	EX	DE,HL
	CALL	VRAM_OFF
	CALL	CLLINE
	POP	HL
	POP	DE
	POP	BC
	RET

IO_MON:
;	MON : IOCSのモニタ(機能00h MONOP)を呼ぶ。モニタのコマンド R で戻ってくる(S-OS移植版で確認済みの動作)
;	IOCSのRAM(0000h-25FFh)はLSXのTPA/ページ0に使われて壊れているので、起動時(M25INIT)に
;	ページ0Ch,0Dへ退避しておいた内容を戻してから呼ぶ。LSXのページ0(0000h-00FFh)は6600hに退避して、戻ったら復元する。
;	TPAのプログラムは消える(CCPから呼ぶ前提)。
	DI
	LD	SP,0CE00H
	CALL	MON_MAP
	LD	HL,0
	LD	DE,06600H
	LD	BC,00100H
	LDIR				;LSXのページ0を退避
	LD	HL,04000H
	LD	DE,0
	LD	BC,02600H
	LDIR				;IOCSのRAMを復元
	CALL	MON_UNMAP
#IF EXISTS USE_TINIT
#ELSE
#IF EXISTS COLS80
	IN	A,(0E8H)		;IOCS内部は40桁のつもりなので、IOCSなし80桁ではハードを40桁に戻す
	AND	0DFH
	OUT	(0E8H),A
	LD	A,7
	OUT	(0F4H),A
	LD	A,008H
	OUT	(0F5H),A
	LD	A,8
	OUT	(0F4H),A
	LD	A,058H
	OUT	(0F5H),A
#ENDIF
#ENDIF
	LD	A,007H
	OUT	(0C6H),A		;IPL終了時の割り込み許可に戻す(S-OS版が動いている状態)
	LD	A,2
	LD	I,A
	IM	2
	LD	SP,01900H		;スタックは低位RAM(S-OS版と同じ1900h)。バンク7(FC00h)に置くとモニタのメモリ表示で暴走する
	EI
	RST	18H
	DB	000H			;MONOP
	DI
	IM	1
#IF EXISTS USE_TINIT
#ELSE
#IF EXISTS COLS80
	IN	A,(0E8H)
	OR	020H
	OUT	(0E8H),A
	LD	A,7
	OUT	(0F4H),A
	LD	A,009H
	OUT	(0F5H),A
	LD	A,8
	OUT	(0F4H),A
	LD	A,059H
	OUT	(0F5H),A
#ENDIF
#ENDIF
	LD	A,008H
	OUT	(0C6H),A		;VBLANKだけ許可に戻す
	LD	SP,0CE00H
	CALL	MON_MAP
	LD	HL,06600H
	LD	DE,0
	LD	BC,00100H
	LDIR				;LSXのページ0を復元
	CALL	MON_UNMAP
	LD	C,00CH
	CALL	CPM_CONOUT		;画面を消してホームへ
	JP	CPM_WBOOT

MON_MAP:				;バンク2,3 = ページ0Ch,0Dh (IOCS RAMの退避先)
	LD	A,2
	OUT	(0B4H),A
	LD	A,00CH
	OUT	(0B5H),A
	LD	A,00DH
	OUT	(0B5H),A
	RET

MON_UNMAP:				;バンク2,3 = 標準(ページ02h,03h)
	LD	A,2
	OUT	(0B4H),A
	LD	A,002H
	OUT	(0B5H),A
	LD	A,003H
	OUT	(0B5H),A
	RET

;	IM1の割り込み処理(VBLANKのみ許可: C6h=08h)。E1h bit0(/VBLANK)はこの許可があるときだけ動き、
;	RD556VSYNC(キーリピート・FDCのREADYタイムアウトの時間基準)が使う。許可が無いと常に1のまま止まる。
IO_INT8253:
	EI
	RETI
