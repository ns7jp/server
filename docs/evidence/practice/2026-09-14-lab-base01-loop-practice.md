# lab-base01：Ansible loop演習（2026-09-14）

## 結果と範囲

本人VMのホーム内で3種類の設定ファイルを生成し、同内容での再実行、productionだけの変更、
変更後の再実行を確認した。changedの集計は2→0→1→0で、全回failed0・終了コード0。
**productionも演習用の名前**であり、実運用環境・実サービス・ポート待受を構築した実績ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付）。操作・撮影の正確な時刻は未採録 |
| 環境 | Hyper-V VM lab-base01、opsadmin。OS・Ansible版は今回再採録していない |
| 実行場所 | /home/opsadmin/ansible-first-lab。公開用serverとは別 |
| 入力 | loop-demo.yml、既存templates/app.conf.j2。Playbook全文・ハッシュは未採録 |
| 出力 | managed-loop配下のtraining/staging/production各app.conf |
| 証拠 | [原画像5枚とハッシュ](../screenshots/2026-09-14-lab-base01-loop-practice/README.md) |

## 実施構成

既存テンプレートはenvironment_nameとlisten_portを参照する2行（E01）。
案内したPlaybookでは環境一覧をloopで処理し、各ディレクトリを作成してからtemplateを実行する。
タスク変数でitem.name/item.portをテンプレートの変数へ対応付け、registerした結果を
debugで環境別に表示する構成とした。実ファイル全文を読戻した証跡ではなく、以下は画面で確認した範囲である。

## 確認結果

LP番号は本結果票専用。PASSは画像に示された観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| LP-01 | 開始状態 | PASS | main、前段2パスが未追跡。loop用2パスNOT FOUNDと既存テンプレート本文（E01） |
| LP-02 | 初回生成 | PASS | ディレクトリ・設定の各loopで3対象changed。環境別True、ok3/changed2/failed0、終了0（E02） |
| LP-03 | 初回本文 | PASS | training/8080、staging/8081、production/8082の本文（E02） |
| LP-04 | 同内容再実行 | PASS | 3環境ともFalse、ok3/changed0/failed0、終了0（E03） |
| LP-05 | 部分変更 | PASS | ディレクトリは全件ok。設定はproductionだけTrue、他2件False、changed1/failed0、終了0（E04） |
| LP-06 | 部分変更の本文 | PASS | training/8080、staging/8081を維持し、production/8090を確認（E04） |
| LP-07 | 変更後再実行 | PASS | 3環境ともFalse、ok3/changed0/failed0、終了0、本文8080/8081/8090を維持（E05） |
| LP-08 | 最終Git状態 | PASS | main、handlers-demo.yml・loop-demo.yml・managed-handlers/・managed-loop/が未追跡（E05） |

集計のchangedは対象ファイル数ではなく変更のあったタスク数。
初回はディレクトリ作成と設定生成の2タスク、部分変更時は設定生成の1タスクがchangedとなった。
環境別のTrue/Falseはdebug出力で確認した。register結果の全構造や配列長の独立検査は未採録。

## 実行コマンドと証拠の境界

- 初回の構文確認と通常実行を案内したが、E02には入力行・syntax-check結果が写っていない。
  通常実行のタスク結果と終了コード0は確認した。構文確認の実行結果は未採録。
- E03には引数なしの通常再実行コマンドが写っている。
- 部分変更と最後の再実行は`-e production_port=8090`を案内した。
  E04/E05ではコマンド入力行が画面外で、指定引数そのものは未採録。
  それぞれの変更判定・終了コード・生成本文から確認できる結果に限定して記録する。
- 入力Playbookの作成画面・全文・SHA-256、実行対象コミットは未採録。

## 最終状態・未実施

- 最後の設定値は8080/8081/8090。productionを既定値8082へ戻す操作は未実施。
- 新規Playbookと生成物は未追跡のまま保持。Gitコミット・ignore追加・削除は未実施。
- 実サービスの起動・ポート待受、複数VMへの配備、site.yml実行は**NOT RUN**。
- ネストしたloop、失敗時の継続、block/rescue/always演習は**NOT RUN**。
- ファイル権限・全内容ハッシュ、連続rawログ、Git bundleは未採録。
- server側の文書検査・CIと本人VMの実行主体・対象を区別する。

## 手順案との差異と復習

原案に不足していたディレクトリ作成とテンプレートへの変数対応を案内に含めた。
テンプレート自体を変更せず、production_port変数で1対象だけの変更を試した。
loopは対象を順番に処理し、変更の有無は対象ごとに判定される。
この説明はAIによる復習用で、本人独力による説明の採録ではない。

- [前段：ハンドラー](2026-09-14-lab-base01-handlers-practice.md)
- [手順案](../../roadmap/lab-base01-ansible-next-exercises.md)
- [検証証跡台帳](../README.md)
