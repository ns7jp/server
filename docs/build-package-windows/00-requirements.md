# 要件定義書

## 1. 文書の位置づけ

`server-monitor` の既存監視基盤(案件ID SM-LAB-001、正本は[Linux版構築案件パック](../build-package/README.md))に、Windows Server を新しい監視対象ホストとして追加登録する案件(案件ID SM-WIN-001)として扱います。Prometheus / Grafana / Loki / Alertmanager の監視スタックを Windows 上にもう 1 式作るのではなく、既存の中央監視基盤(論理ホスト名 monitor-01、変更なし)を拡張します。本書は要求と受け入れ条件を定義し、設計値の正本は後続資料と本パックのコード断片、実行結果の正本は[検証証跡台帳](../evidence/README.md)に分離します。

本書に「済(自動)」「済(手動)」と書いてあっても、実ホストでの構築・試験完了を意味しません。受け入れ可否は[試験仕様書・結果票](06-test-specification.md)の結果で判定します。本パック全体を通じて実装状態は次の 3 区分のみを使い、混同しません。

| 区分 | 意味 |
| --- | --- |
| 済(自動) | 既存の Ansible 機能で今すぐ実行できるもの。`ansible/roles/app/defaults/main.yml` の `app_node_exporter_targets` 変数へ Windows ホストを 1 行追加し、中央 host 側で `site.yml` を再適用する経路のみが該当します |
| 済(手動) | Ansible 化はされていないが、本パックの PowerShell 手順で今すぐ実施できるもの(OS 設定、Firewall、IIS、windows_exporter 導入、バックアップ等) |
| 未実装 | 本パックは設計のみを示しており、コードが無いもの(Windows 対応 Ansible role、Windows Event Log/IIS ログを Loki へ送る経路)。あわせて、Docker ホストと対象 Windows ホストの実ネットワーク接続、および windows_exporter の Firewall 許可(Docker ホストの実 IP 向け)も未確立(`NOT SET`)であり、これはコード未実装ではなく実機での接続・許可設定が未検証という意味で、他の2点と合わせて計3点がフェーズ 2 を `BLOCKED` にしています |

構築は 2 段階のフェーズに分かれます。フェーズ 1(ホスト単体構築)は「済(手動)」の範囲で monitor-win-01 単体として完結し、フェーズ 2(中央監視統合)は上記「未実装」3 点の解消まで `BLOCKED` として扱います。

## 2. 案件概要

| 項目 | 内容 |
| --- | --- |
| 案件ID | SM-WIN-001(既存 SM-LAB-001 の監視対象拡張) |
| 利用者 | Windows Server を構築・運用する担当者(既存 Linux 監視基盤の運用者と共通) |
| 対象環境 | Windows Server 2022 Standard(Desktop Experience 基準)、検証用 VM 1 台、論理ホスト名 monitor-win-01 |
| 監視対象アプリ | IIS(Web サーバー機能)で公開する検証用サイト。Linux 版における Nginx + Flask アプリの「監視される側」に相当 |
| 構築方式 | フェーズ 1 は本パックの PowerShell 手順による手動構築(Windows 対応 Ansible role は未実装)。フェーズ 2 は中央監視 host 側の既存 Ansible 機能(`app_node_exporter_targets`)への 1 行追加のみ「済(自動)」 |
| 中央監視基盤 | 既存 Linux host(論理名 monitor-01、[パラメータシート](../build-package/03-parameter-sheet.md)参照)を変更せず、Windows ホストからのメトリクス収集・ログ集約先として拡張する対象 |
| 提供機能 | IIS 監視対象サイトの稼働、windows_exporter によるホストメトリクス収集(フェーズ 2)、IIS 到達性の blackbox probe(フェーズ 2)、Windows Event Log/IIS ログの集約(フェーズ 2)、バックアップと復旧手順 |
| 引き渡し単位 | 設計書、パラメータシート、構築手順、試験結果、作業結果報告、既存の運用・変更手順([運用手順](../runbooks/README.md)、[変更管理](../change-management.md))への追記差分 |
| 完了判定 | フェーズ 1 の必須試験がすべて `PASS` し、フェーズ 2 は未実装 3 点の解消条件とともに `BLOCKED` として明記され、計画対実績・差異・未解決事項・残存リスクが作業結果報告と受領記録に記載済み |

## 3. 機能要件

| ID | 要件 | 受け入れ確認 | 実装・設計先 |
| --- | --- | --- | --- |
| FR-01 | 運用者が WinRM(HTTPS)経由で Windows Server を管理できること | WIT-01 | [構築手順書](05-build-procedure.md)(WinRM HTTPS リスナー設定) |
| FR-02 | IIS の監視対象サイトが稼働し、health 用エンドポイントを提供すること | WIT-04 | [構築手順書](05-build-procedure.md)(IIS Web-Server 機能) |
| FR-03 | CPU/memory/disk などのホストメトリクスを windows_exporter 経由で中央 Prometheus が収集できること(フェーズ 2、要 Docker ホスト↔対象ホスト間の実接続・Firewall 許可) | WIT-03 | `ansible/roles/app/defaults/main.yml`(`app_node_exporter_targets`)、`ansible/roles/app/templates/prometheus.yml.j2`、Docker ホストと対象 Windows ホストの実 L3 到達性および windows_exporter 側 Firewall(Docker ホストの実 IP 向けの許可が必要) |
| FR-04 | IIS サイトの HTTP 到達性を中央の blackbox-exporter で probe できること(フェーズ 2、要テンプレート拡張) | WIT-05 | `ansible/roles/app/templates/prometheus.yml.j2`(`blackbox-probe-health` ジョブの汎用化が必要) |
| FR-05 | Windows Event Log/IIS ログを既存 Loki へ集約し Grafana から検索できること(フェーズ 2、要 Alloy for Windows 導入) | WIT-06 | [詳細設計書](02-detailed-design.md)(Grafana Alloy for Windows は未導入、設計のみ) |
| FR-06 | サービス停止を検知し、復旧と正常性確認までの時間を記録できること(D-1 相当) | WIT-08 | [構築手順書](05-build-procedure.md)、[試験仕様書・結果票](06-test-specification.md) |
| FR-07 | 管理端末から Windows Server までの名前解決、経路、待受、HTTP、Firewall を確認できること | WNW-01〜09, WST-01, WST-04 | [ネットワーク実機検証手順](09-network-validation-procedure.md) |

## 4. 非機能要件

| ID | 分類 | 要件 | 受け入れ確認 |
| --- | --- | --- | --- |
| NFR-01 | 再現性 | 未構築の対象 VM へ本パックの手順(現時点は手動 PowerShell)を適用し、エラーなく完了すること | WIT-01 |
| NFR-02 | 冪等性 | 同一手順を 2 回目実行しても不要な変更(サービス再作成、Firewall ルール重複等)が発生しないこと | WIT-02 |
| NFR-03 | セキュリティ | WinRM は HTTPS 専用とし、Basic 認証を無効化すること | WST-01 |
| NFR-04 | セキュリティ | RDP は既定 Disable とし、必要時のみ管理元 CIDR 限定で一時有効化すること | WST-02 |
| NFR-05 | 最小権限 | windows_exporter サービスの実行アカウント(既定 LocalSystem)を記録し、是正余地を残存課題とすること | WST-03 |
| NFR-06 | ネットワーク | Windows Defender Firewall は Default Inbound Block とし、WinRM/IIS/windows_exporter を管理元 CIDR 限定で許可すること | WST-04 |
| NFR-07 | 可観測性 | メトリクス・外形監視・ログを関連付けて一次切り分けできること(フェーズ 2 の範囲は未実装区間ありと明記) | WIT-05、WIT-06 |
| NFR-08 | 復旧性 | サービス停止演習で検知から復旧までの RTO を記録すること | WIT-08 |
| NFR-09 | 保守性 | 変更前後の状態、検証、ロールバック条件と結果を記録すること | [変更・ロールバック計画](08-change-rollback-plan.md) |
| NFR-10 | 追跡性 | 実行日時、環境、ホストのビルド番号、コマンド、実出力、判定を証跡へ残すこと | 全必須試験 |
| NFR-11 | 完了管理 | 計画対実績、試験集計、設計差異、障害、未実施、受領可否を 1 件の報告へまとめること | [作業結果・引き渡し報告書](11-work-result-report.md) |
| NFR-12 | 実装境界の明示 | Ansible 化されていない手順を「済(手動)」と明記し、既存の `site.yml` のような自動化済み経路と混同しないこと(このパック自体の誠実性要件) | 全文書共通 |

## 5. 制約と対象外

- 単一ホスト(monitor-win-01)の検証用構成であり、ホスト障害時の無停止継続は提供しません。
- 24 時間有人監視、複数拠点、SSO、商用 SLA、実組織の個人情報は対象外です。
- 中央監視基盤本体(Prometheus/Grafana/Loki/Alertmanager の構成)の変更は対象外です。既存の Linux 版設計([詳細設計書](../build-package/02-detailed-design.md))のまま変更しません。
- 既存 AD ドメインへ参加させる場合の設定差分を示すに留め、Active Directory 自体の新規構築・設計は対象外です。
- バックアップは Windows Server Backup(`wbadmin`)機能のみを対象とし、商用バックアップ製品の導入・評価は対象外です。
- 複数の Windows Server ホストによる冗長構成・負荷分散・フェイルオーバーは対象外です。監視対象ホストは monitor-win-01 の 1 台です。
- Windows Server 2022 Server Core は構成の対応を検討する課題ですが、本案件の基準 VM は Desktop Experience です。Server Core での実測は個別の証跡が必要です。
- クラウド(Azure/AWS 等)の Windows Server インスタンスでの構築は[立ち上げ環境の選択肢](10-host-bringup-and-acceptance.md)に示す選択肢の一つに過ぎず、`apply`/`destroy` 相当の実行証跡がない限り本案件の構築実績には含めません。
- フェーズ 2(中央監視統合)に必要な 3 点(Windows 対応 Ansible role、Docker ホストと対象 Windows ホストの実ネットワーク接続および windows_exporter の Firewall 許可(Docker ホストの実 IP 向け)、Windows 向けログ集約経路)は「対象外」ではなく「解消条件付きの `BLOCKED`」として扱います。本案件の範囲には含まれますが、現時点では実行できません。

## 6. 前提条件

- 管理端末から WinRM(HTTPS)で対象 VM へ接続でき、接続アカウントが対象 VM の管理者権限(ローカル Administrator 相当)を持つこと。
- 証明書(自己署名または内部 CA 発行)による WinRM HTTPS、または AD ドメイン参加による Kerberos/Negotiate 認証のいずれかが用意できること。
- 対象 IP、管理元 CIDR、FQDN、作業時間帯、費用上限(クラウド利用時)が作業前に確定していること。
- windows_exporter のインストーラの SHA256 とダウンロード元を実機決定時に記録できること。
- 中央監視 host(monitor-01)側の変更(`app_node_exporter_targets` への追記、`site.yml` の再適用)を実施できる権限を持つ運用者が別途存在すること(本パックは Windows 側のみを担当します)。

## 7. 要件トレーサビリティと判定

詳細な操作・期待結果は[試験仕様書・結果票](06-test-specification.md)を正本とします。結果はその原本へ直接記入せず、日付付きの evidence へコピーして保存します。

| 判定 | 意味 |
| --- | --- |
| `PASS` | 期待結果を実出力で確認し、証跡への参照がある |
| `FAIL` | 実行したが期待結果と一致しない |
| `BLOCKED` | 前提不足で実行できず、理由と解除条件がある |
| `NOT RUN` | 未実行。成功実績として数えない |

設計値と実績値は必ず分けて記録し、未実施の実績値は `NOT SET`/`NOT RUN`/`NOT READY` のいずれかを使います。安易に `PASS` へ書き換えないでください。現時点の結果は[検証証跡台帳](../evidence/README.md)を参照してください。資料が揃ったことと、構築案件が完了したことは別の状態です。
