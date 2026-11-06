
;	LSX-Dodgers MZ-2500 ブートローダ(IPLが読む8KBのページ。レコード32-63)
;	IPLがここ(8000H)へジャンプしてくる。FAT上の通常ファイル LD2500.BIN を
;	標準セクタ(512バイト/セクタ、9セクタ/トラック、BPBのディスク)から読み込んで実行する。
;
;	SYS_LSN0 : LD2500.BIN の先頭論理セクタ番号 (build.pyが定義)
;	SYS_NSEC : LD2500.BIN のセクタ数(512バイト単位、32以下)
;
;	IPLの環境(SP=FC00h, EI, IM2, バンク0-3=標準)をそのまま引き継いで LD2500.BIN の START へ渡す。
;	LD2500.BIN はページ0Ah,0Bhに読み込み、バンク4,5へ割り当ててから 8000H へジャンプする。

	ORG	08000H

BOOT:
	DI
	XOR	A
	OUT	(0DEH),A		;倍密度
	LD	A,084H
	OUT	(0DCH),A		;ドライブ0 モータON
	CALL	WAITMS
	LD	A,008H
	CALL	FDCMD			;RESTORE
	XOR	A
	LD	(CURCYL),A
	LD	A,5
	OUT	(0B4H),A
	LD	A,00AH
	OUT	(0B5H),A		;バンク5(A000H-) = ページ0Ah
	LD	DE,SYS_LSN0
	LD	HL,0A000H
	LD	A,SYS_NSEC
	LD	(CNT),A
LOOP:
	PUSH	DE
	PUSH	HL
	CALL	RDRET
	POP	HL
	POP	DE
	JR	C,FAIL
	INC	DE
	INC	H
	INC	H			;HL += 512
	LD	A,H
	CP	0C0H
	JR	NZ,NOPG
	LD	A,5
	OUT	(0B4H),A
	LD	A,00BH
	OUT	(0B5H),A		;バンク5 = ページ0Bh
	LD	H,0A0H
NOPG:
	LD	A,(CNT)
	DEC	A
	LD	(CNT),A
	JR	NZ,LOOP
	LD	HL,TRAMP
	LD	DE,0C000H
	LD	BC,TRAMPE-TRAMP
	LDIR
	JP	0C000H

FAIL:
	LD	A,'E'
	CALL	MARK
FAIL1:
	JR	FAIL1

;	バンク4,5 を LD2500.BIN のページへ切り替えて実行(バンク6のRAM上で動く)
TRAMP:
	LD	A,4
	OUT	(0B4H),A
	LD	A,00AH
	OUT	(0B5H),A		;バンク4 = ページ0Ah (B4は自動で+1)
	LD	A,00BH
	OUT	(0B5H),A		;バンク5 = ページ0Bh
	EI
	JP	08000H
TRAMPE:

;	論理セクタ DE(256未満) を HL へ 512バイト読む。CF=1でエラー
RDLSN:
	LD	A,E
	LD	B,0
RDL1:
	CP	9
	JR	C,RDL2
	SUB	9
	INC	B
	JR	RDL1
RDL2:
	INC	A
	LD	C,A			;C=セクタ(1-9) B=トラック
	LD	A,B
	AND	1
	OUT	(0DDH),A		;ヘッド(偶数トラック=0)
	LD	A,B
	SRL	A
	LD	B,A			;B=シリンダ
	LD	A,(CURCYL)
	CP	B
	JR	Z,RDL3
	LD	A,B
	LD	(CURCYL),A
	CPL
	OUT	(0DBH),A		;シーク先
	LD	A,018H
	CALL	FDCMD			;SEEK
	RET	C			;タイムアウト
RDL3:
	LD	A,C
	CPL
	OUT	(0DAH),A		;セクタ
	LD	A,080H
	CPL
	OUT	(0D8H),A		;READ SECTOR
	LD	BC,0			;待ちタイムアウト用(BC x D回)。データ受信中は触らない
	LD	D,3
RDL4:
	IN	A,(0D8H)
	CPL
	RRCA
	JR	NC,RDL6			;BUSY解除 = 終了
	RRCA
	JR	C,RDL5
	DEC	BC			;DRQ待ち
	LD	A,B
	OR	C
	JR	NZ,RDL4
	DEC	D
	JR	NZ,RDL4
	LD	A,0D0H			;タイムアウト: Force Interrupt して失敗で返す
	CPL
	OUT	(0D8H),A
	SCF
	RET
RDL5:
	IN	A,(0DBH)
	CPL				;反転バス
	LD	(HL),A
	INC	HL
	JR	RDL4
RDL6:
	IN	A,(0D8H)
	CPL
	AND	01CH			;RNF/CRC/LOST
	RET	Z
	SCF
	RET

;	RDLSN を最大5回試す。失敗のたびに RESTORE して先頭から。DE,HL は保存される。CF=1で最終失敗
RDRET:
	LD	A,5
	LD	(RTRY),A
RDR1:
	PUSH	DE
	PUSH	HL
	CALL	RDLSN
	POP	HL
	POP	DE
	RET	NC
	LD	A,(RTRY)
	DEC	A
	LD	(RTRY),A
	SCF
	RET	Z
	PUSH	DE
	PUSH	HL
	LD	A,008H
	CALL	FDCMD			;RESTORE
	XOR	A
	LD	(CURCYL),A
	POP	HL
	POP	DE
	JR	RDR1

;	A=コマンド を発行してBUSY解除まで待つ。タイムアウトで CF=1 (DE を壊す)
FDCMD:
	CPL
	OUT	(0D8H),A
	EX	(SP),HL
	EX	(SP),HL
	EX	(SP),HL
	EX	(SP),HL
	LD	DE,0
	LD	A,6
	LD	(TMO),A
FDC1:
	IN	A,(0D8H)
	CPL
	RRCA
	RET	NC			;BUSY解除(CF=0)
	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,FDC1
	LD	A,(TMO)
	DEC	A
	LD	(TMO),A
	JR	NZ,FDC1
	LD	A,0D0H			;タイムアウト: Force Interrupt して CF=1 で返す
	CPL
	OUT	(0D8H),A
	SCF
	RET

;	約0.3秒の待ち(モータ起動)
WAITMS:
	LD	BC,0
WM1:
	DEC	BC
	LD	A,B
	OR	C
	JR	NZ,WM1
	RET

;	12行目に A の文字を1桁表示(バンク3を一時的にVRAMへ)
MARK:
	PUSH	BC
	PUSH	DE
	PUSH	HL
	LD	C,A
	LD	A,3
	OUT	(0B4H),A
	LD	A,038H
	OUT	(0B5H),A
	LD	HL,06000H+12*40
	LD	A,C
	ADD	A,A
	ADD	A,A
	LD	(HL),A
	LD	DE,00800H
	ADD	HL,DE
	LD	(HL),007H
	ADD	HL,DE
	LD	A,C
	RLCA
	RLCA
	AND	3
	OR	08CH
	LD	(HL),A
	LD	A,3
	OUT	(0B4H),A
	LD	A,3
	OUT	(0B5H),A
	POP	HL
	POP	DE
	POP	BC
	RET

CURCYL:	DB	0
CNT:	DB	0
RTRY:	DB	0
TMO:	DB	0
