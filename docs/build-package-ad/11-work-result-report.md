# 作業結果・引き渡し報告書（原本）

本書は、Active Directory構築作業(案件ID `SM-AD-001`)の「予定」と「実績」、試験結果、差異、障害、残存リスク、受領判断を1件にまとめるための原本です。対象ホストごとに `docs/evidence/YYYY-MM-DD-work-result-<change-id>.md` へ複製して記入し、この原本は上書きしません。命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせます。

初期値の `NOT SET` は情報未確定、`NOT RUN` は未実行、`NOT READY` は完了条件未達です。空欄や `NOT RUN` を `PASS` として集計しません。

本書はフェーズ1(ホスト単体構築)とフェーズ2(中央監視統合)を区別して記載します。フェーズ2は[要件定義書](00-requirements.md)に記載した「未実装」3点(Windows対応Ansible roleが無いこと、`compose.yaml`のmonitoring networkが`internal: true`であること、Windows Event Log/AD監査ログをLokiへ送る経路が無いこと)が解消するまで`BLOCKED`が前提であり、`BLOCKED`のままであること自体はフェーズ1の完了判定を妨げません。

`ad-dc01`に相当する実ホストの構築そのものがまだ行われていないため、本書に対応する日付付きevidenceは現時点で1件もありません。以下の空欄は次の構築作業で複製して使う原本であり、実ホストでの作業結果は現在も`NOT RUN`です。

## 1. 文書・作業管理

| 項目 | 値 |
| --- | --- |
| 案件ID | `SM-AD-001` |
| 変更ID / チケット | `NOT SET` |
| 作業目的 | `NOT SET` |
| 対象環境 / ホスト | `NOT SET`(論理ホスト名`ad-dc01`) |
| 対象フェーズ(フェーズ1のみ / フェーズ1+2) | `NOT SET` |
| ドメインFQDN | `corp.example.test`(設計値、[要件定義書](00-requirements.md)参照)。実環境で別名を使う場合の値は`NOT SET` |
| NetBIOS名 | `CORP`(設計値)。実環境で別名を使う場合の値は`NOT SET` |
| DSRM(ディレクトリサービス復元モード)パスワードの受け渡し状況 | `NOT SET` — 秘密値台帳(Git管理外)で生成・保管・受け渡しする予定。値そのものはこのリポジトリのどの文書・証跡にも記載しない |
| 作業者 / 確認者 | `NOT SET` |
| 作業予定日時 | `NOT SET` |
| 作業実績日時 | `NOT RUN` |
| 対象ホストのビルド番号(`winver` または `Get-ComputerInfo` の `OsBuildNumber`) | `NOT SET` |
| 変更前の状態識別子(スナップショット名 または直前の`OsBuildNumber`) | `NOT SET` |
| windows_exporter バージョン / SHA256 | `NOT SET` |
| 中央inventory適用commit SHA(フェーズ2有効化時、`app_node_exporter_targets`追記分) | `NOT SET` |
| 作業結果 | `NOT READY` |
| 関連 Issue / PR | `NOT SET` |

AD版にはLinux版のような単一のcommit SHAで対象ホストの構成全体を再現する手段がありません(Windows対応Ansible roleが`ansible/roles`配下に無く、フォレスト作成・DC昇格は本パックのPowerShell手順による「済(手動)」のため)。そのため対象ホストの状態識別子はスナップショット名または`OsBuildNumber`で記録し、中央側(`monitor-01`)への変更だけを既存のGit/Ansible基準のcommit SHAで記録します。両者を混同しないでください。DSRMパスワードは新規フォレスト作成時にのみ入力する値であり、実値はこの報告書を含むリポジトリのどこにも記載せず、受け渡し状況(誰が・いつ・どの手段で受領したか)だけをここに記録します。

## 2. 作業前判定

| 確認項目 | 判定 | 証跡 / 備考 |
| --- | --- | --- |
| 対象、影響範囲、停止時間が合意済み | NOT SET | — |
| 管理端末からWinRM(HTTPS)が利用可能 | NOT RUN | — |
| 初回フォレスト作成用のコンソール直接ログオン手段を確認(WinRMではなくハイパーバイザーコンソールから実施) | NOT RUN | — |
| RDP一時許可またはコンソール等の代替接続手段を確認 | NOT RUN | — |
| DSRMパスワードが秘密値台帳で生成・保管され、パスワードポリシー(NFR-07)相当の強度を満たしている | NOT SET | AUT-02 |
| 変更前後の状態識別子(スナップショット名 / `OsBuildNumber`)を固定 | NOT SET | — |
| VM/ハイパーバイザーのスナップショット取得可否を確認 | NOT RUN | — |
| Go / No-Go 条件を確認 | NOT SET | [変更・ロールバック計画兼記録票](08-change-rollback-plan.md) |

## 3. 計画対実績

| 工程 | 予定操作 | 実績開始–終了 / 所要時間 | 結果 | 証跡 | 差異・備考 |
| --- | --- | --- | --- | --- | --- |
| 事前確認 | 対象host特定、WinRM疎通、スナップショット可否、DSRMパスワード準備、変更前状態 | `NOT RUN` | NOT RUN | — | — |
| 初回構築(フェーズ1) | コンソール直接ログオンによる新規フォレスト作成・初回DC昇格(AIT-01) | `NOT RUN` | NOT RUN | — | — |
| 昇格後確認(フェーズ1) | 必須サービス、AD統合DNS、OU/既定ドメインGPO、FSMO確認(AIT-02〜05) | `NOT RUN` | NOT RUN | — | — |
| バックアップ・復元(フェーズ1) | System Stateバックアップ取得、ADごみ箱によるオブジェクト復元(AIT-06、AIT-07) | `NOT RUN` | NOT RUN | — | — |
| 障害復旧(フェーズ1) | ディレクトリサービス関連サービスの停止復旧演習、検知〜復旧のRTO記録(AIT-08) | `NOT RUN` | NOT RUN | — | — |
| 実機network検証(フェーズ1) | ANW-01〜09(AIT-10) | `NOT RUN` | NOT RUN | — | — |
| 再実行安全性(フェーズ1) | 昇格済みDCへ`Install-ADDSForest`相当を誤って再実行する試験(AIT-11) | `NOT RUN` | NOT RUN | — | — |
| 中央統合(フェーズ2) | `app_node_exporter_targets`へ`ad-dc01`追記、中央`site.yml`再適用、host/ADメトリクスscrape確認(AIT-09) | `NOT RUN` | BLOCKED | — | monitoring networkの`internal: true`制約のためBLOCKED |
| 後処理 | RDP一時許可・検証用OU/ユーザーの削除、最終状態取得 | `NOT RUN` | NOT RUN | — | — |

結果は`PASS / FAIL / BLOCKED / NOT RUN`のいずれかとし、実行コマンド、主要出力、所要時間を日付付きevidenceへ残します。中央統合(フェーズ2)は未実装3点が解消するまで、実施しても前提が揃わず`BLOCKED`になることが設計時点で分かっています。

## 4. 試験集計

| 区分 | 対象件数 | PASS | FAIL | BLOCKED | NOT RUN | 結果票 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 単体・設定確認(AUT) | `NOT SET` | 0 | 0 | 0 | `NOT SET` | `NOT SET` |
| 構築・結合試験(AIT) | `NOT SET` | 0 | 0 | 0 | `NOT SET` | `NOT SET` |
| セキュリティ試験(AST) | `NOT SET` | 0 | 0 | 0 | `NOT SET` | `NOT SET` |
| ネットワーク実機検証(ANW) | `NOT SET` | 0 | 0 | 0 | `NOT SET` | `NOT SET` |
| 合計 | `NOT SET` | 0 | 0 | 0 | `NOT SET` | [試験仕様書・結果票](06-test-specification.md) |

集計値は個別結果票(ネットワーク実機検証は[結果票テンプレート](../evidence/templates/network-host-validation-ad.md)から作成した日付付きevidence)から転記し、合計が一致することを確認します。対象ホストが違う結果や、別の変更前状態識別子の結果を合算しません。フェーズ2に属するAIT-09は、未実装3点が解消するまで`BLOCKED`が前提であり、`BLOCKED`件数が残っていること自体はフェーズ1の集計の妥当性を損ないません。

## 5. 設計値と実績値の差異

| 項目 | 設計値 | 実績値 | 影響 | 対応 / 承認 |
| --- | --- | --- | --- | --- |
| OS / ビルド番号 | [パラメータシート](03-parameter-sheet.md)参照(Windows Server 2022 Standard, Desktop Experience) | `NOT RUN` | `NOT SET` | `NOT SET` |
| CPU / memory / disk | 同上 | `NOT RUN` | `NOT SET` | `NOT SET` |
| ドメインFQDN / NetBIOS名 / フォレスト・ドメイン機能レベル | [パラメータシート](03-parameter-sheet.md)参照(`corp.example.test` / `CORP` / WinThreshold) | `NOT RUN` | `NOT SET` | `NOT SET` |
| IP / DNS / route | [ネットワーク設計・IPアドレス表](04-network-ip-plan.md)参照 | `NOT RUN` | `NOT SET` | `NOT SET` |
| FSMO役割保持者 | [パラメータシート](03-parameter-sheet.md)参照(5役割すべて`ad-dc01`) | `NOT RUN` | `NOT SET` | `NOT SET` |
| OU構造 / 既定ドメインGPOパスワードポリシー | 同上 | `NOT RUN` | `NOT SET` | `NOT SET` |
| windows_exporter バージョン / SHA256 | 同上(実機決定時に固定) | `NOT RUN` | `NOT SET` | `NOT SET` |
| port / Windows Defender Firewallプロファイル・許可範囲 | 同上 | `NOT RUN` | `NOT SET` | `NOT SET` |

差異が無い場合も「差異なし」と記録し、未確認のまま空欄にしません。承認されていない差異が残る場合は作業完了にしません。

## 6. 障害・課題・再試験

| ID | 発生時刻 | 事象 / 影響 | 原因 | 対応 | 再試験 | Issue |
| --- | --- | --- | --- | --- | --- | --- |
| `NOT SET` | `NOT RUN` | `NOT SET` | `NOT SET` | `NOT SET` | NOT RUN | `NOT SET` |

切り分けは[一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)へ仮説、コマンド、実出力、判断を残します。既知の実例は[欠陥台帳](../evidence/defects-found.md)を参照します。

## 7. 残存リスク・未実施

この原本の初期状態では、少なくとも次は引き渡し対象ホストで`NOT RUN`または`BLOCKED`です。実施した項目だけ、日付付き結果と置き換えます。

| 項目 | 状態 | 解除条件 |
| --- | --- | --- |
| 対象ホストの新規構築・受け入れ(フェーズ1) | NOT RUN | 対象ホストで[構築手順書](05-build-procedure.md)と[立ち上げ対象ホストの立ち上げと受け入れ試験](10-host-bringup-and-acceptance.md)を実行 |
| 実管理端末 / 内部ネットワーク / Firewall検証(フェーズ1) | NOT RUN | [ネットワーク実機検証手順](09-network-validation-procedure.md)でANW-01〜09を実行 |
| サービス停止復旧演習・RTO記録(フェーズ1) | NOT RUN | 対象ホストでAIT-08(ディレクトリサービス関連サービスの一時停止、検知〜復旧の時間記録)を実行 |
| System Stateバックアップ / ADごみ箱復元試験(フェーズ1) | NOT RUN | 対象ホストでAIT-06(System Stateバックアップ取得)、AIT-07(ADごみ箱によるオブジェクト復元)を実行 |
| host/ADメトリクスscrape(フェーズ2、AIT-09) | BLOCKED | `compose.yaml`の`monitoring` networkが`internal: true`であるため、Prometheusコンテナがサーバー外にある実machine(`ad-dc01`)の`windows_exporter`(既定9182/tcp)へ到達できない。Prometheusサービスを追加の管理用bridge networkにも接続する`compose.yaml`変更が必要(現状未実装) |
| Windows対応Ansible role(`common_windows`等)の追加 | NOT READY | `ansible/roles`配下へWindows対応roleを新設し、フェーズ1の手動PowerShell手順(フォレスト作成・DC昇格を除く)を自動化するかを検討 |
| 2台目DC追加によるレプリケーション実測 | NOT RUN | [基本設計書](01-basic-design.md)2.4節の発展構成として、`Install-ADDSDomainController`で2台目を追加し`repadmin /replsummary`・`repadmin /showrepl`でレプリケーション状態を確認 |
| monitor-win-01のドメイン参加検証 | NOT RUN | [Windows版パック](../build-package-windows/01-basic-design.md)の系統B(既存ADに参加させる場合の差分)を、実際に`ad-dc01`を使って統合演習として確認 |
| windows_exporterサービスアカウントの最小権限化 | NOT READY | 現状`LocalSystem`での運用実績を積んだうえで、最小権限アカウントへの移行方針を検討・適用 |
| ログ集約(フェーズ2) | BLOCKED | Windows Event Log / AD監査ログを既存Lokiへ送る経路(Grafana Alloy for Windowsの導入、Lokiのpush APIをloopback以外からも安全に受け付けるための認証・network設計)が無い(現状未実装) |

## 8. 引き渡し物

| 成果物 | 対象版 / 保存先 | 受領確認 |
| --- | --- | --- |
| 対象ホストの状態識別子(スナップショット名 / `OsBuildNumber`) | `NOT SET` | NOT SET |
| 設計・パラメータ | `docs/build-package-ad/` | NOT SET |
| 中央inventory変更(フェーズ2有効化時) | 40桁commit SHA: `NOT SET` | NOT SET |
| 試験結果・実行ログ | `NOT SET` | NOT SET |
| ネットワーク実機検証結果票 | `NOT SET` | NOT SET |
| 運用ランブック | [運用runbook索引](../runbooks/README.md) | NOT SET |
| backup / restore手順 | [`docs/backup-restore.md`](../backup-restore.md)、[パラメータシート](03-parameter-sheet.md)の「バックアップ設計」節 | NOT SET |
| 変更 / rollback記録 | `NOT SET` | NOT SET |
| DSRMパスワードの受け渡し・再発行方法 | 秘密値台帳(Git管理外)を経由した受け渡し手順のみを記録し、値そのものは記載しない | NOT SET |
| その他の秘密値(ローカルAdministrator名、証明書秘密鍵等)の受け渡し・再発行方法 | 値そのものは記載しない | NOT SET |

## 9. 完了・受領判定

- [ ] フェーズ1の必須試験がすべて`PASS`で、結果票と集計が一致する
- [ ] フェーズ1に`FAIL` / `BLOCKED` / 必須の`NOT RUN`が残っていない
- [ ] フェーズ2が「未実装」3点の解消条件とともに`BLOCKED`として明記されている
- [ ] 設計差異、障害、残存リスク、未解決Issueを説明した
- [ ] RDP一時許可、一時設定、検証用OU/ユーザー等のテストデータを撤去し、最終状態を採録した
- [ ] ロールバックまたは復元の開始条件と連絡先を共有した
- [ ] DSRMパスワードの受け渡し・再発行方法を、値を記載せずに共有した
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
