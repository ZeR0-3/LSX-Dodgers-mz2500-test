;	LSX-Dodgers MEM
;	MZ-2500 : E: EMM (MZ-1R37) / F: RAMディスク(拡張RAM)
;	DPBドライバの呼び出し規約: IX=DPB B=セクタ数 CDE=セクタ番号 HL=アドレス
;	                    戻り値   CF=0 DE=次のセクタ HL=次のアドレス

;	EMM DRIVER (512B/セクタ)
;	ポートACh: B(=A15-A8)の下位4bit=EMMアドレス19-16 / データ=EMMアドレス15-8
;	ポートADh: B(=A15-A8)=EMMアドレス7-0 / データ=読み書き(自動加算なし)
;	セクタ s は 256B x2 : ページ番号 p=2*s と p+1 (p=偶数なのでp+1はビット0を立てるだけ)

EDRD:
	PUSH	BC
	CALL	EMMLAT
	PUSH	BC
	CALL	EMMPG
	CALL	EMMRD
	POP	BC
	INC	C		;mid | 1
	CALL	EMMPG
	CALL	EMMRD
	POP	BC
	INC	DE
	DJNZ	EDRD
	AND	A
	RET

EDWT:
	PUSH	BC
	CALL	EMMLAT
	PUSH	BC
	CALL	EMMPG
	CALL	EMMWR
	POP	BC
	INC	C
	CALL	EMMPG
	CALL	EMMWR
	POP	BC
	INC	DE
	DJNZ	EDWT
	AND	A
	RET

EMMLAT:				;DE=セクタ -> B=アドレス19-16 C=アドレス15-8 (=2*DE)
	LD	A,E
	ADD	A,A
	LD	C,A
	LD	A,D
	ADC	A,A
	AND	00FH
	LD	B,A
	RET

EMMPG:				;BC=(上位,中位) でアドレスラッチを設定。B=0 C=0ADh で戻る
	LD	A,C
	LD	C,0ACH
	OUT	(C),A
	LD	C,0ADH
	LD	B,0
	RET

EMMRD:
	IN	A,(C)
	LD	(HL),A
	INC	HL
	INC	B
	JR	NZ,EMMRD
	RET

EMMWR:
	LD	A,(HL)
	OUT	(C),A
	INC	HL
	INC	B
	JR	NZ,EMMWR
	RET

;	RAM DISK DRIVER (拡張RAM ページ10h-1Fh = 128KB, 512B/セクタ x 256)
;	ページはバンク5(A000H-BFFFH)へ一時的に割り当てて RDBUF 経由でコピーする
;	(呼び出し元のバッファやスタックがバンク5にあってもよいように、割り当て中はDIでLDIRだけを行う)

RDRD:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	CALL	RDADR		;HL=窓のアドレス A=ページ
	LD	B,A
	DI
	LD	A,5
	OUT	(0B4H),A
	LD	A,B
	OUT	(0B5H),A
	LD	DE,RDBUF
	LD	BC,512
	LDIR			;拡張RAM -> RDBUF
	LD	A,5
	OUT	(0B4H),A
	LD	A,RAM5_PG
	OUT	(0B5H),A
	EI
	POP	DE		;DE=呼び出し元のアドレス
	LD	HL,RDBUF
	LD	BC,512
	LDIR
	EX	DE,HL		;HL=次のアドレス
	POP	DE
	INC	DE
	POP	BC
	DJNZ	RDRD
	AND	A
	RET

RDWT:
	PUSH	BC
	PUSH	DE
	LD	DE,RDBUF
	LD	BC,512
	LDIR			;呼び出し元 -> RDBUF  HL=次のアドレス
	POP	DE
	PUSH	DE
	PUSH	HL
	CALL	RDADR
	LD	B,A
	DI
	LD	A,5
	OUT	(0B4H),A
	LD	A,B
	OUT	(0B5H),A
	EX	DE,HL		;DE=窓のアドレス
	LD	HL,RDBUF
	LD	BC,512
	LDIR			;RDBUF -> 拡張RAM
	LD	A,5
	OUT	(0B4H),A
	LD	A,RAM5_PG
	OUT	(0B5H),A
	EI
	POP	HL
	POP	DE
	INC	DE
	POP	BC
	DJNZ	RDWT
	AND	A
	RET

RDADR:				;DE=セクタ(0-255) -> A=ページ(10h+セクタ/16) HL=A000h+(セクタ%16)*512
	LD	A,E
	AND	00FH
	ADD	A,A
	ADD	A,0A0H
	LD	H,A
	LD	L,0
	LD	A,E
	RRCA
	RRCA
	RRCA
	RRCA
	AND	00FH
	OR	010H
	RET
