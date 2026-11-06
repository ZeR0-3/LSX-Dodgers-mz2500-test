# LSX-Dodgers for SHARP MZ-2500

CP/M-80 / MSX-DOS 互換OS **LSX-Dodgers**(原作: Gaku 氏)を **SHARP MZ-2500** に移植したものです。
MZ-700/1500 版(`M7*.ASM`)を土台に、機種依存部を `src/M25*.ASM` に置き換えています(共通部 `LD*.ASM` は無改造)。

> **状態: v0.1(エミュレータで動作確認済み / 実機では未確認)**
> mz2500-web-emulator の CLI(実IPL ROM で起動)で、起動、`DIR`、`COPY`、`FORMAT`、各ドライブの読み書きなど 64 項目の自動テストが通ります。**実機での動作は確認できていません。**

## できること
- 実IPLから起動 → LSX のプロンプト。80桁/40桁表示、カーソル点滅、LOCK / カナキー、ビープ、`MON`(IOCS の ROM モニタ呼び出し)
- X1 / MZ-700 の LSX で作った標準形式の 2D/2DD(512B×9セクタ、BPB)をそのまま読み書き。物理フォーマット対応
- ワイルドカード、階層ディレクトリなど LSX 本体の機能

| ドライブ | 内容 | 状態 |
|---|---|---|
| A: B: | 内蔵FDD 1/2(2D/2DD 自動判別) | エミュレータで確認 |
| C: D: | 外付けFDD 3/4 | 実装のみ。実体のあるドライブでは未確認 |
| E: | EMM(MZ-1R37、最大640KB)。使う前に `FORMAT E:` | エミュレータで確認 |
| F: | RAMディスク(拡張RAM 128KB)。起動時に自動フォーマット | エミュレータで確認 |

**未対応・未確認**: 2HD(MZ-2500 に存在するか資料で確認できていないため実装していません)、F1〜F10/GRAPH/HELP キー、実機での全般的な動作。詳細は [docs/HANDOFF.md](docs/HANDOFF.md) の状況表を参照してください。

## 起動ディスクイメージ(dist/)
すぐ試せるよう、ビルド済みの起動ディスク(標準LSX形式の2DD)を `dist/` に置いています。

| ファイル | 内容 |
|---|---|
| `LSX2500_80col.d88` | **推奨**。80桁25行 |
| `LSX2500_40col.d88` | 40桁25行 |
| `LSX2500_40col_noiocs.d88` / `LSX2500_80col_noiocs.d88` | IOCSを呼ばない版(フォールバック) |

ディスクには LSX-Dodgers 原本のコマンド(`FORMAT.COM`、`MKDIR.COM`、`TYPE.COM` など。**原本リポジトリにソースがあるもの**)を取り込んであります。
- `FORMAT.COM` は機種ID判定の1バイトだけパッチしています(`CP 1`→`CP 4`。理由は [docs/porting-notes.md](docs/porting-notes.md))。
- 原本の `ldsys.d88` に含まれる他者のツール(`HDD.COM`=LD-hdd、`M8A40/M8A80.COM`=M8A Graphic Loader、`LA.COM`)は、原本リポジトリにソースが無くライセンスがそれぞれ別なので**入れていません**。
- 取り込んだコマンドの中には MZ-2500 では動かないもの(`MAG`/`GL3`/`EMM`/`HDD` 系など、他機種専用)があります。

## ビルドして試す
自分でビルドする場合に必要なもの(リポジトリには含まれません。各自で用意してください):
- [LSX-Dodgers 原本](https://github.com/tablacus/LSX-Dodgers)のソース(`LD*.ASM` など)と、原本のシステムディスク `ldsys.d88`(起動ディスクにツール `FORMAT.COM` 等を取り込むため。無しでも `LD2500.BIN` は作れます)
- [z88dk](https://github.com/z88dk/z88dk) の z80asm
- 動作確認には [mz2500-web-emulator](https://github.com/zabaglione/mz2500-web-emulator) と、**自分で用意した MZ-2500 の IPL ROM など**(ROM は同梱できません)

```bash
tools/setup_env.sh <作業dir> <z88dk作業ツリー> <mz2500-web-emulator.zip> <ROMS.zip>   # z80asm とエミュレータCLIを用意
source <作業dir>/env.sh
tools/build_all.sh <LSX-Dodgers原本dir> <ldsys.d88> <出力dir>                      # 起動ディスク(.d88)4種を作る
tools/test_all.sh <出力dir>                                                         # 自動テスト 64 本(約12分)
```
出力: `LSX2500_80col.d88`(推奨)、`LSX2500_40col.d88`、`LSX2500_40col_noiocs.d88`、`LSX2500_80col_noiocs.d88`。

## ドキュメント
- [docs/hardware-notes.md](docs/hardware-notes.md): 確認済みのハード仕様と根拠
- [docs/porting-notes.md](docs/porting-notes.md): 起動の仕組み、デバッグで判明した事項


## 謝辞
- **LSX-Dodgers**(作者: Gaku 氏、[tablacus/LSX-Dodgers](https://github.com/tablacus/LSX-Dodgers) で公開)。この移植はすべてその設計と共通部ソースの上に成り立っています。
- **[mz2500-web-emulator](https://github.com/zabaglione/mz2500-web-emulator)**(Zabaglione 氏): FDC/VRAM の挙動をソースで裏取りできたため、実機なしで開発・検証できました。
- [z88dk](https://github.com/z88dk/z88dk) の z80asm、および MZ-2500 の資料・S-OS 移植版を公開されている方々。

## ライセンス
MIT([LICENSE](LICENSE))。LSX-Dodgers 原本の著作権表示(Gaku)を保持しています。`dist/` のイメージに入っている原本のコマンドも原本リポジトリ(MIT)のものです。
