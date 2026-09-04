# 作業結果・引き渡し報告書(原本)

本書は、WSUSサーバー構築作業(案件ID `SM-WSUS-001`)の「予定」と「実績」、試験結果、差異、障害、残存リスク、受領判断を1件にまとめるための原本です。対象ホストごとに `docs/evidence/YYYY-MM-DD-work-result-<change-id>.md` へ複製して記入し、この原本は上書きしません。命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせます。

初期値の `NOT SET` は情報未確定、`NOT RUN` は未実行、`NOT READY` は完了条件未達です。空欄や `NOT RUN` を `PASS` として集計しません。

本書はフェーズ1(ホスト単体構築)とフェーズ2(中央監視統合)を区別して記載します。フェーズ2は[要件定義書](00-requirements.md)に記載した「未実装」3点(Windows対応Ansible roleの不在、`compose.yaml`の`monitoring`ネットワークの`internal: true`制約、Windows向けログ集約経路の不在)が解消するまで`BLOCKED`が前提であり、`BLOCKED`のままであること自体はフェーズ1の完了判定を妨げません。この3点の理由付けは[Windows版パック](../build-package-windows/11-work-result-report.md)・[AD版パック](../build-package-ad/11-work-result-report.md)と同一とし、本パック独自の理由へ作り替えません。

`wsus-01`に相当する実ホストの構築そのものがまだ行われていないため、本書に対応する日付付きevidenceは現時点で1件もありません。以下の空欄は次の構築作業で複製して使う原本であり、実ホストでの作業結果は現在も`NOT RUN`です。依存案件の[AD版パック](../build-package-ad/README.md)は実機評価済みの体裁ですが、本パックはこれを踏襲せず、[Windows版パック](../build-package-windows/11-work-result-report.md)と同じ「作成済みだが未実施」の状態を保ちます。

## 1. 文書・作業管理

| 項目 | 値 |
| --- | --- |
| 案件 ID | `SM-WSUS-001` |
| 依存案件 ID | `SM-AD-001`(既存ADドメイン`corp.example.test`。[AD版パック](../build-package-ad/README.md)が正本) |
| 変更 ID / チケット | `NOT SET` |
| 作業目的 | `NOT SET` |
| 対象環境 / ホスト | `NOT SET`(論理ホスト名`wsus-01`、FQDN`wsus-01.corp.example.test`) |
| 対象フェーズ(フェーズ1のみ / フェーズ1+2) | `NOT SET` |
| 作業者 / 確認者 | `NOT SET` |
| 作業予定日時 | `NOT SET` |
| 作業実績日時 | `NOT RUN` |
| 対象ホストのビルド番号(`winver` または `Get-ComputerInfo` の `OsBuildNumber`) | `NOT SET` |
| 変更前の状態識別子(チェックポイント名 または直前の`OsBuildNumber`) | `NOT SET` |
| ドメイン参加状態(`Get-ADComputer wsus-01 -Properties DistinguishedName`のDN) | `NOT SET` |
| WSUSロールのバージョン / コンテンツストア空き容量 | `NOT SET` |
| windows_exporter バージョン / SHA256 | `NOT SET` |
| 中央inventory適用commit SHA(フェーズ2有効化時、`app_node_exporter_targets`追記分) | `NOT SET` |
| 作業結果 | `NOT READY` |
| 関連 Issue / PR | `NOT SET` |

WSUS版にはLinux版のような単一のcommit SHAで対象ホストの構成全体を再現する手段がありません(Windows対応Ansible roleが`ansible/roles`配下に無いため、[Windows版パック](../build-package-windows/11-work-result-report.md)・[AD版パック](../build-package-ad/11-work-result-report.md)と同じ制約です)。そのため対象ホストの状態識別子はチェックポイント名または`OsBuildNumber`で記録し、中央側(`monitor-01`)への変更だけを既存のGit/Ansible基準のcommit SHAで記録します。両者を混同しないでください。

## 2. 作業前判定

| 確認項目 | 判定 | 証跡 / 備考 |
| --- | --- | --- |
| 対象、影響範囲、停止時間が合意済み | NOT SET | — |
| ADドメイン`corp.example.test`(`ad-dc01`、`ad-dc02`)が稼働中であることを確認 | NOT RUN | 依存案件`SM-AD-001`の前提条件 |
| 管理端末からWinRM(HTTPS)が利用可能 | NOT RUN | — |
| RDP一時許可またはコンソール等の代替接続手段を確認 | NOT RUN | RDPは既定Disableのため、代替接続手段の確保が前提 |
| コンテンツストア用のDドライブ(100GB以上)がVM/ハイパーバイザー側で確保済み | NOT RUN | — |
| 変更前後の状態識別子(チェックポイント名 / `OsBuildNumber`)を固定 | NOT SET | — |
| VM/ハイパーバイザーのスナップショット取得可否を確認 | NOT RUN | — |
| Windows Server Backupの直近バージョンを確認 | NOT RUN | — |
| Go / No-Go 条件を確認 | NOT SET | [変更・ロールバック計画兼記録票](08-change-rollback-plan.md) |

## 3. 計画対実績

| 工程 | 予定操作 | 実績開始–終了 / 所要時間 | 結果 | 証跡 | 差異・備考 |
| --- | --- | --- | --- | --- | --- |
| 事前確認 | 対象host特定、ADドメイン疎通、WinRM疎通、backup/スナップショット可否、変更前状態 | `NOT RUN` | NOT RUN | — | — |
| ドメイン参加(フェーズ1) | `wsus-01`を`corp.example.test`へ参加、コンピューターオブジェクトを`Servers`OUへ移動(SUT-01) | `NOT RUN` | NOT RUN | — | — |
| 初回構築(フェーズ1) | [構築手順書](05-build-procedure.md)のWSUSロール導入(WID)、`wsusutil postinstall`、コンテンツストア配置、`WsusPool`チューニング一式(SIT-01) | `NOT RUN` | NOT RUN | — | — |
| 冪等性(フェーズ1) | 同一手順2回目実行、ロール再作成・GPOリンク重複・Firewallルール重複なし(SIT-02) | `NOT RUN` | NOT RUN | — | — |
| Microsoft Update初回同期(フェーズ1) | 言語(英語/日本語)・製品(Windows Server 2022、Windows 11)・分類(Critical/Security/Updates/Update Rollups)を指定した初回同期(SIT-03) | `NOT RUN` | NOT RUN | — | — |
| GPO適用・自己登録(フェーズ1) | `WSUS-Client-Policy`の`Servers`OUへのリンク、`wsus-01`自身の自己登録確認(SIT-04) | `NOT RUN` | NOT RUN | — | — |
| 承認・適用一巡(フェーズ1) | 手動承認と自動承認ルールによる更新のダウンロード・インストール確認(SIT-05、SIT-06) | `NOT RUN` | NOT RUN | — | — |
| クリーンアップ・バックアップ(フェーズ1) | クリーンアップウィザード相当の手動実行・タスク登録確認、SUSDB/コンテンツストア/IIS構成のバックアップ・リストア(SIT-07、SIT-08) | `NOT RUN` | NOT RUN | — | — |
| 構築後確認(フェーズ1) | WSUSサービス稼働、IISサイト正常性、windows_exporter稼働、Firewall、WinRM listener | `NOT RUN` | NOT RUN | — | — |
| 実機network検証(フェーズ1) | SNW-01〜09 | `NOT RUN` | NOT RUN | — | — |
| 中央統合(フェーズ2) | `app_node_exporter_targets`追記、中央`site.yml`再適用、scrape確認(SIT-09) | `NOT RUN` | BLOCKED | — | 未実装3点が未解消のためBLOCKED |
| 障害復旧 | サービス停止復旧演習、必要に応じてロールバック/復元 | `NOT RUN` | NOT RUN | — | — |
| 後処理 | RDP一時許可・試験データ削除、最終状態取得 | `NOT RUN` | NOT RUN | — | — |

結果は`PASS / FAIL / BLOCKED / NOT RUN`のいずれかとし、実行コマンド、主要出力、所要時間を日付付きevidenceへ残します。Microsoft Updateとの初回同期は、選択した製品・分類のメタデータ取得だけでも相応の時間がかかる見込みであり、実施時は所要時間を記録しますが、現時点で具体的な所要時間を断定しません。中央統合(フェーズ2)は未実装3点が解消するまで、実施しても前提が揃わず`BLOCKED`になることが設計時点で分かっています。

## 4. 試験集計

| 区分 | 対象件数 | PASS | FAIL | BLOCKED | NOT RUN | 結果票 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 単体・設定確認(SUT) | 5 | 0 | 0 | 0 | 5 | `NOT SET` |
| 構築・結合試験(SIT) | 9 | 0 | 0 | 0 | 9 | `NOT SET` |
| セキュリティ試験(SST) | 6 | 0 | 0 | 0 | 6 | `NOT SET` |
| ネットワーク実機検証(SNW) | 9 | 0 | 0 | 0 | 9 | `NOT SET` |
| 合計 | 29 | 0 | 0 | 0 | 29 | [試験仕様書・結果票](06-test-specification.md) |

対象件数は[試験仕様書・結果票](06-test-specification.md)に定義された`SUT-01`〜`05`、`SIT-01`〜`09`、`SST-01`〜`06`、`SNW-01`〜`09`の件数です。集計値は個別結果票(ネットワーク実機検証は[WSUS版ネットワーク結果票テンプレート](../evidence/templates/network-host-validation-wsus.md))から転記し、合計が一致することを確認します。対象ホストが違う結果や、別の変更前状態識別子の結果を合算しません。フェーズ2に属する`SIT-09`は、未実装3点が解消するまで`BLOCKED`が前提であり、`BLOCKED`件数が残っていること自体はフェーズ1の集計の妥当性を損ないません。実行後は上表の`NOT RUN`列を実績(`PASS`/`FAIL`/`BLOCKED`/`NOT RUN`)へ置き換え、`SUT-01`〜`05`・`SIT-01`〜`08`・`SST-01`〜`06`・`SNW-01`〜`09`(フェーズ1必須ID)がすべて`PASS`することを確認します。

## 5. 設計値と実績値の差異

| 項目 | 設計値 | 実績値 | 影響 | 対応 / 承認 |
| --- | --- | --- | --- | --- |
| OS / ビルド番号 | [パラメータシート](03-parameter-sheet.md)参照(Windows Server 2022 Standard, Desktop Experience) | `NOT RUN` | `NOT SET` | `NOT SET` |
| CPU / memory / disk(C:/D:) | 同上(4 vCPU/メモリ8GB/C:80GB/D:100GB以上) | `NOT RUN` | `NOT SET` | `NOT SET` |
| IP / DNS / route | [ネットワーク設計・IPアドレス表](04-network-ip-plan.md)参照(`192.0.2.52/24`) | `NOT RUN` | `NOT SET` | `NOT SET` |
| ドメイン参加 / コンピューターオブジェクトの配置先OU | [パラメータシート](03-parameter-sheet.md)参照(`corp.example.test`、`Servers`OU) | `NOT RUN` | `NOT SET` | `NOT SET` |
| データベース方式(系統A: WID / 系統B: 外部SQL Server) | 系統A(WID)固定。系統Bは対象外 | `NOT RUN` | `NOT SET` | `NOT SET` |
| WSUS管理サイトのポート(HTTP 8530 / HTTPS 8531) | HTTP(8530)固定。HTTPS化は次点課題 | `NOT RUN` | `NOT SET` | `NOT SET` |
| コンテンツストア配置先 | `D:\WSUS\WSUSContent`(Dドライブ) | `NOT RUN` | `NOT SET` | `NOT SET` |
| `WsusPool`設定(アイドルタイムアウト/キュー長/メモリ制限) | 同上(0分/2000/0) | `NOT RUN` | `NOT SET` | `NOT SET` |
| GPO「WSUS-Client-Policy」の対象グループ名とWSUSコンピューターグループ名の一致 | 両者とも`Servers` | `NOT RUN` | `NOT SET` | `NOT SET` |
| windows_exporter バージョン / SHA256 | [パラメータシート](03-parameter-sheet.md)参照(実機決定時に固定) | `NOT RUN` | `NOT SET` | `NOT SET` |
| port / Firewallプロファイル | 同上(5986/8530/9182許可、Domainプロファイル) | `NOT RUN` | `NOT SET` | `NOT SET` |

差異が無い場合も「差異なし」と記録し、未確認のまま空欄にしません。承認されていない差異が残る場合は作業完了にしません。

## 6. 障害・課題・再試験

| ID | 発生時刻 | 事象 / 影響 | 原因 | 対応 | 再試験 | Issue |
| --- | --- | --- | --- | --- | --- | --- |
| `NOT SET` | `NOT RUN` | `NOT SET` | `NOT SET` | `NOT SET` | NOT RUN | `NOT SET` |

切り分けは[一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)へ仮説、コマンド、実出力、判断を残します。既知の実例は[欠陥台帳](../evidence/defects-found.md)を参照します。`wsusutil postinstall`未実行によるコンソール起動エラーのような、実務でよく知られたつまずきが実際に発生した場合も、本表へ日付・事象・対応を記録します。

## 7. 残存リスク・未実施

この原本の初期状態では、少なくとも次は引き渡し対象ホストで`NOT RUN`または`BLOCKED`です。実施した項目だけ、日付付き結果と置き換えます。

| 項目 | 状態 | 解除条件 |
| --- | --- | --- |
| 対象ホストの新規構築・冪等性・受け入れ(フェーズ1) | NOT RUN | 対象ホストで[構築手順書](05-build-procedure.md)と[立ち上げ対象ホストの立ち上げと受け入れ試験](10-host-bringup-and-acceptance.md)を実行 |
| 実管理端末 / DNS / Firewall(フェーズ1) | NOT RUN | [ネットワーク実機検証手順](09-network-validation-procedure.md)でSNW-01〜09を実行 |
| Microsoft Updateとの初回同期(フェーズ1) | NOT RUN | 対象ホストでSIT-03を実行 |
| GPOクライアント側ターゲティング・自己登録(フェーズ1) | NOT RUN | 対象ホストでSIT-04を実行 |
| 自動承認ルールの動作確認(フェーズ1) | NOT RUN | 対象ホストでSIT-06を実行 |
| クリーンアップウィザード定期実行の確認(フェーズ1) | NOT RUN | 対象ホストでSIT-07を実行 |
| SUSDB・コンテンツストア・IIS構成のバックアップ復元試験(フェーズ1) | NOT RUN | 別ボリューム/別ホストへの復元でSIT-08を実行 |
| 再起動後の永続性、24h/72h稼働(フェーズ1) | NOT RUN | [立ち上げ・受け入れ手順](10-host-bringup-and-acceptance.md)を実行 |
| 複数クライアントでの大規模検証 | 対象外(発展課題) | 本パックの範囲では対応しない。`wsus-01`自身の自己登録・承認・適用の一巡にとどめ、他ホスト(`ad-dc01`、`ad-dc02`、`monitor-win-01`等)をWSUS管理下に追加する展開は発展課題として別途計画・承認を要する |
| WSUS通信のHTTPS化(8531番、証明書配布) | 対象外・次点課題 | 内部CA(AD証明書サービス)をラボへ導入し、証明書配布・GPO側URL変更を含めた設計を別途追加 |
| 外部SQL Serverへの移行(データベース方式の系統B) | 対象外(設計差分のみ) | クライアント数がおよそ数百台を超える規模、またはSSRSによるレポート連携が必要になった時点で、[基本設計書](01-basic-design.md)の系統B差分を基に別途計画 |
| レプリカ/ダウンストリームWSUSサーバーによる階層化構成 | 対象外 | 複数拠点・大規模展開が要件化した時点で別途計画 |
| windows_exporterサービスアカウントの最小権限化 | NOT READY | 現状LocalSystemでの運用実績を積んだうえで、最小権限アカウントへの移行方針を検討・適用 |
| WSUSコンソールのレポート機能用ランタイム | NOT RUN | 実機でレポート機能を確認し、表示用ランタイムの追加インストールが必要かどうかを記録(NFR-08) |
| 中央監視統合(フェーズ2、SIT-09) | BLOCKED | Windows対応Ansible roleが`ansible/roles`に無いこと、`compose.yaml`の`monitoring`ネットワークが`internal: true`でPrometheusが`wsus-01`のwindows_exporter(9182/tcp)へ到達できないこと、Windows Event Log / IISログを既存Lokiへ送る経路(Grafana Alloy for Windows等)が無いこと、の3点が解消するまで実行不能。[Windows版パック](../build-package-windows/00-requirements.md)・[AD版パック](../build-package-ad/00-requirements.md)と同一の理由付け |
| Windows対応Ansible role(`common_windows`等)の追加 | NOT READY | `ansible/roles`配下へWindows対応roleを新設し、フェーズ1のPowerShell手順を自動化するかを検討 |

## 8. 引き渡し物

| 成果物 | 対象版 / 保存先 | 受領確認 |
| --- | --- | --- |
| 対象ホストの状態識別子(チェックポイント名 / `OsBuildNumber`) | `NOT SET` | NOT SET |
| 設計・パラメータ | `docs/build-package-wsus/` | NOT SET |
| GPO「WSUS-Client-Policy」のエクスポート(`Backup-GPO`) | `NOT SET` | NOT SET |
| WSUSコンピューターグループ・自動承認ルールの設定記録 | `NOT SET` | NOT SET |
| 中央inventory変更(フェーズ2有効化時) | 40桁commit SHA: `NOT SET` | NOT SET |
| 試験結果・実行ログ | `NOT SET` | NOT SET |
| ネットワーク実機検証結果票 | `NOT SET` | NOT SET |
| 運用ランブック | [運用runbook索引](../runbooks/README.md) | NOT SET |
| backup / restore手順(SUSDB・コンテンツストア・IIS構成) | [`docs/backup-restore.md`](../backup-restore.md) | NOT SET |
| 変更 / rollback記録 | `NOT SET` | NOT SET |
| 秘密値の受け渡し・再発行方法(ローカルAdministrator/ドメインアカウントのパスワード等) | 値そのものは記載しない | NOT SET |

## 9. 完了・受領判定

- [ ] フェーズ1の必須試験(SUT-01〜05、SIT-01〜08、SST-01〜06、SNW-01〜09)がすべて`PASS`で、結果票と集計が一致する
- [ ] フェーズ1に`FAIL` / `BLOCKED` / 必須の`NOT RUN`が残っていない
- [ ] フェーズ2(SIT-09)が「未実装」3点の解消条件とともに`BLOCKED`として明記されている
- [ ] 設計差異、障害、残存リスク、未解決Issueを説明した
- [ ] 複数クライアント検証・HTTPS化・SQL Server移行(系統B)が対象外・次点課題であることを説明した
- [ ] RDP一時許可、一時設定、テストデータを撤去し、最終状態を採録した
- [ ] ロールバックまたは復元の開始条件と連絡先を共有した
- [ ] [引き渡しチェックリスト](07-handover-checklist.md)を完了した

| 判定 | 値 |
| --- | --- |
| 作業完了(フェーズ1) | `NOT READY` |
| 作業完了(フェーズ2) | `BLOCKED`(未実装3点の解消が前提) |
| 引き渡し可否 | `NOT READY` |
| 判定理由 | 必須試験と受領情報が未記入 |
| 引き渡し日時 | `NOT SET` |
| 引き渡し元 / 先 | `NOT SET` |
| 承認者 | `NOT SET` |
