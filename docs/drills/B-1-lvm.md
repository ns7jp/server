# B-1: ディスク設計・LVM 拡張演習

## 1. 目的

「VG を作る / LV を切る / mount する / 容量が足りなくなって online で拡張する」という、
LVM の一連の操作を安全に体験する。予備ディスクの無い PC でも、loop device（ファイルを
仮想的なディスクとして扱う仕組み）を使うことで、実ディスクを追加せずに同じ操作を
再現できる。

| 項目 | 値 |
| --- | --- |
| 頻度 | 環境を作り直したとき、および関連コードを変更した PR |
| 想定時間 | 10 分 |
| 環境 | Linux + root 権限（loop device が使える環境） |
| 対象 | `storage` role が管理する VG / LV / filesystem / fstab |
| 関連ラーニングパス | [一本道ラーニングパス](../learning-path.md) Level 6（発展・選択） |

## 2. なぜ物理PCで実行してもよいのか

この演習は `sudo` で LVM 操作を行うため、初めての場合は身構えるかもしれません。
物理 PC（会社や共有端末ではなく、自分の検証用 PC）で直接実行してもよいのは、
次の理由からです。

- 対象は実ディスクのパーティションではなく、`/var/tmp` 配下に作った**loopファイル**
  （256MBの仮想ディスクイメージ）2本だけです。実ディスクの `/dev/sdX` には一切触れません。
- VG 名は `vg_drill`、LV 名は `lv_drill` という演習専用の名前を使い、既存の VG/LV と
  衝突しないようにしています。
- スクリプト自身が実行前に `require_root` と `require_tools` で前提を確認し、
  必要なコマンドが無ければ実行前に停止します。

とはいえ、`sudo` での LVM 操作そのものに不慣れな場合は、誤って対象デバイスを
指定し間違えるリスクをさらに小さくするため、使い捨ての検証用 VM（[一本道ラーニングパス](../learning-path.md)のLevel 0の前で用意したものなど）での実行を推奨します。

## 3. 事前準備

1. `sudo -l` で管理者権限を使えることを確認する。
2. `df -h /var/tmp` で、loopファイル用の空き容量（256MB×2以上）があることを確認する。
3. 学習記録を開き、実行環境（`uname -sr`）を記録する準備をする。

## 4. 演習スクリプト

```bash
# 自分が誰として・どこで実行したかを記録に残す
export DRILL_OPERATOR="<自分の名前>"

sudo -E ./scripts/labs/lvm-drill.sh
```

スクリプトは次を自動で行う。

1. loop device 2 本を用意する
2. `storage` role で VG / LV / filesystem / fstab を作る
3. 2 回目を流して `changed=0`（冪等性）を確認する
4. LV をわざと使い切り、`No space left on device` を再現する
5. 2 本目の PV を足して online で LV とファイルシステムを拡張する
6. 拡張後に書き込めることを確認する

結果は `docs/drills/logs/<日付>-B-1.md` に証跡として自動生成される。数値は実行時の
測定値であり、実行者が自分で読み、書き換えずに採録する。

## 5. 期待される結果

| ID | 試験 | 期待結果 |
| --- | --- | --- |
| B1-01 | storage role の初回適用 | VG / LV / filesystem / fstab が作られ、mount済みになる |
| B1-02 | 冪等性 | 2回目の適用で `changed=0` |
| B1-03 | 容量枯渇の再現 | 書き込みが `ENOSPC`（No space left on device）で失敗する |
| B1-04 | PV追加によるonline拡張 | `umount`せずにLVとfilesystemが広がる |
| B1-05 | 拡張後の書き込み | 追記できる |

5件すべてPASSなら合格。1件でもFAILがあれば、原因を記録してから[storage role](../../ansible/roles/storage/)の該当taskを見直す。

## 6. 安全装置の確認（任意）

このスクリプト自体が「宣言しているVGのときだけ許す」という安全装置を持っているかは、
[`scripts/labs/storage-guard-test.sh`](../../scripts/labs/storage-guard-test.sh)が別途検証する
（存在しないデバイス、`/`へのmount、既存署名のあるディスクなどを与えて、LVM操作の手前で
止まることを確認する）。この演習の一部ではなく、独立した検証なので、時間が無ければ
省略してよい。

## 7. 後始末

```bash
sudo ./scripts/labs/lvm-drill.sh --cleanup
```

`--cleanup`はこの演習が作ったloop device・VG・LV・mount・loopファイルだけを削除する。
実ディスクには何も残らない。

## 8. 振り返り

B-1はスクリプトが`docs/drills/logs/YYYY-MM-DD-B-1.md`へ証跡を自動生成するため、
D-1のように[docs/drill-template.md](../drill-template.md)を別途コピーする必要はない
（[演習一覧](README.md)冒頭の「Bシリーズは手でPASSを書き込む余地がない」を参照）。
生成された証跡を自分で読み、数値と「この演習で確認していないこと」節を確認したうえで、
気づいた点があれば学習記録や改善Issueに追記する。
