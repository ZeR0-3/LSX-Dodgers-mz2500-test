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
;	ページを CPU のバンク3(6000H-)またはバンク5(A000H-)へ一時的に割り当て、呼び出し元のバッファへ直接 LDIR する。
;	窓にするバンクは、呼び出し元バッファ(512B)の末尾がバンク5より下ならバンク5、それ以外ならバンク3
;	(バッファと窓が重ならない)。割り当て中は DI で、スタックを使わず LDIR と OUT だけを行う
;	(呼び出し元のスタックが窓のバンクにあっても壊れない)。コードはバンク6,7にあるので影響されない。
;	バンク3,5の通常のページは 03h,0Bh。TPAの内側(C000H等)には何も置かない。

RDRD:
	PUSH	BC
	PUSH	DE
	CALL	RDSEL		;B=窓バンク D=窓アドレス上位 E=ページ
	LD	A,B
	DI
	OUT	(0B4H),A
	LD	A,E
	OUT	(0B5H),A	;窓にページを割り当て
	LD	E,0
	EX	DE,HL		;HL=窓 DE=ユーザーバッファ
	LD	BC,512
	LDIR			;窓 -> ユーザーバッファ  DE=次のアドレス
	LD	H,D
	LD	L,E
	DEC	HL
	LD	A,H
	RLCA
	RLCA
	RLCA
	AND	7
	CP	5
	LD	A,5
	LD	C,0BH
	JR	C,RDRD1
	LD	A,3
	LD	C,3
RDRD1:
	OUT	(0B4H),A
	LD	A,C
	OUT	(0B5H),A	;窓を通常のページに戻す
	EI
	INC	HL		;HL=次のアドレス
	POP	DE
	INC	DE
	POP	BC
	DJNZ	RDRD
	AND	A
	RET

RDWT:
	PUSH	BC
	PUSH	DE
	CALL	RDSEL
	LD	A,B
	DI
	OUT	(0B4H),A
	LD	A,E
	OUT	(0B5H),A
	LD	E,0		;DE=窓
	LD	BC,512
	LDIR			;ユーザーバッファ -> 窓  HL=次のアドレス
	LD	D,H
	LD	E,L
	DEC	DE
	LD	A,D
	RLCA
	RLCA
	RLCA
	AND	7
	CP	5
	LD	A,5
	LD	C,0BH
	JR	C,RDWT1
	LD	A,3
	LD	C,3
RDWT1:
	OUT	(0B4H),A
	LD	A,C
	OUT	(0B5H),A
	EI
	POP	DE
	INC	DE
	POP	BC
	DJNZ	RDWT
	AND	A
	RET

RDSEL:				;HL=ユーザーバッファ E=セクタ(0-255) -> B=窓バンク(5か3) D=窓アドレス上位 E=ページ(10h+セクタ/16)。HL保存
	PUSH	HL
	LD	BC,511
	ADD	HL,BC
	LD	A,H
	RLCA
	RLCA
	RLCA
	AND	7		;A=バッファ末尾のバンク
	CP	5
	LD	B,5
	JR	C,RDSEL1
	LD	B,3
RDSEL1:
	POP	HL
	LD	A,E
	AND	00FH
	ADD	A,A		;(セクタ%16)*512 の上位バイト
	LD	D,A
	LD	A,B
	RRCA
	RRCA
	RRCA			;バンク*32 = 窓の先頭アドレスの上位バイト
	ADD	A,D
	LD	D,A
	LD	A,E
	RRCA
	RRCA
	RRCA
	RRCA
	AND	00FH
	OR	010H
	LD	E,A
	RET
