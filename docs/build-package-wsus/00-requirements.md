# 要件定義書

## 1. 文書の位置づけ

本パックは、既存のActive Directoryドメイン(`corp.example.test`。[AD版パック](../build-package-ad/README.md)、案件ID`SM-AD-001`が正本)へ、WSUS(Windows Server Update Services。Microsoft製の更新プログラム集中配信サーバー)を1台追加する案件(案件ID`SM-WSUS-001`)として扱います。[Windows版パック](../build-package-windows/00-requirements.md)と[AD版パック](../build-package-ad/00-requirements.md)のパラメータシート・基本設計書には、いずれも「自動更新はWindows Updateから直接。実務ではWSUS/グループポリシー経由の集中管理を推奨するが、本パックの基準ではない」という一文が明記されていました。本パックは、この「推奨だが対象外」とされてきた欠落を埋めるパックです。既存の中央監視基盤([Linux版パック](../build-package/README.md)、案件ID`SM-LAB-001`)そのものは変更しません。本書は要求と受け入れ条件を定義し、設計値の正本は後続資料、実行結果の正本は[検証証跡台帳](../evidence/README.md)に分離します。

本書に「済(自動)」「済(手動)」と書いてあっても、実ホストでの構築・試験完了を意味しません。受け入れ可否は[試験仕様書・結果票](06-test-specification.md)の結果で判定します。[Windows版パック](../build-package-windows/00-requirements.md)・[AD版パック](../build-package-ad/00-requirements.md)と同じ3区分の実装状態を使い、混同しません。

| 区分 | 意味 |
| --- | --- |
| 済(自動) | 既存のAnsible機能で今すぐ実行できるもの。本パックには該当項目がありません(Windows対応role自体が未実装のため) |
| 済(手動) | Ansible化はされていないが、本パックのPowerShell手順で今すぐ実施できるもの(ドメイン参加、WSUSロール導入、GPO設計、承認ルール設計、クリーンアップ・バックアップのスケジュール登録、windows_exporter導入等) |
| 未実装 | 本パックは設計のみを示しており、コードが無いもの(Windows対応Ansible role、`compose.yaml`の`monitoring`ネットワークの外部到達、Windows向けログ集約経路) |

構築は2段階のフェーズに分かれます。フェーズ1(ホスト単体構築)は「済(手動)」の範囲で`wsus-01`単体として完結し、`wsus-01`自身をWSUSクライアントとして自己登録・同期・承認・適用まで一巡させます。フェーズ2(中央監視統合)は上記「未実装」3点の解消まで`BLOCKED`として扱います。これは[Windows版パック](../build-package-windows/00-requirements.md)・[AD版パック](../build-package-ad/00-requirements.md)が抱える制約と全く同一の理由(Windows対応Ansible roleの不在、`compose.yaml`の`monitoring`ネットワークの`internal: true`制約、Windows向けログ集約経路の不在)であり、本パック独自の理由を作り替えていません。

現在の引き渡し判定は`NOT READY`です。設計・手順書は作成済みですが、実機での構築・試験実績はまだありません。[Windows版パック](../build-package-windows/00-requirements.md)と同じ「作成済みだが未実施」の状態であり、[AD版パック](../build-package-ad/00-requirements.md)のような実機評価済みの体裁は取りません。

## 2. 案件概要

| 項目 | 内容 |
| --- | --- |
| 案件ID | `SM-WSUS-001` |
| 依存案件 | `SM-AD-001`(既存ADドメイン`corp.example.test`。[AD版パック](../build-package-ad/README.md)が正本)。ドメインが未構築の状態では本パックは開始できません |
| 利用者 | WSUSサーバーを構築・運用する担当者(既存ADドメインの運用者と共通) |
| 対象環境 | Windows Server 2022 Standard(Desktop Experience基準)、検証用VM 1台、論理ホスト名`wsus-01` |
| 最小構成の目安 | 4 vCPU / メモリ8GB / OSボリューム(Cドライブ)80GB / コンテンツストア専用ボリューム(Dドライブ)100GB以上。他パックの基準VM(2 vCPU / 4GB / 60GB)より重めなのは、WSUSがMicrosoft Update全メタデータの取得・WID(Windows Internal Database。Windows同梱の軽量データベース機能)によるインデックス処理・IIS(Internet Information Services。Windows同梱のWebサーバー機能)による大容量コンテンツ配信を1台で担うためです |
| 構築対象 | 既存ドメイン`corp.example.test`へ`wsus-01`をメンバーサーバーとして参加させ、WSUSロール(データベースはWID)を構築し、グループポリシーによる更新プログラムの集中管理を実現すること |
| 構築方式 | 本パックのPowerShell手順による手動構築(Windows対応Ansible roleは未実装。[Windows版パック](../build-package-windows/00-requirements.md)・[AD版パック](../build-package-ad/00-requirements.md)と同じ制約) |
| データベース方式 | 系統A(WID。本パックの既定)。系統B(外部SQL Server)は差分のみを記載し対象外とします。詳細は[基本設計書](01-basic-design.md)を参照してください |
| 組織単位(OU) | [AD版パック](../build-package-ad/00-requirements.md)が定義した6OU構成をそのまま利用し、`wsus-01`のコンピューターオブジェクトは既定の`Computers`コンテナではなく`Servers`OUへ明示的に移動します |
| 提供機能 | WSUSロール(WID使用)、専用コンテンツストア、Microsoft Updateとの同期、GPOによるクライアント側ターゲティング、コンピューターグループ・自動承認ルール、クリーンアップウィザードの定期実行、SUSDB/コンテンツストア/IIS構成のバックアップ手順、windows_exporterのローカル導入 |
| 引き渡し単位 | 設計書、パラメータシート、構築手順、試験結果、作業結果報告、既存の運用・変更手順([運用手順](../runbooks/README.md)、[変更管理](../change-management.md))への追記差分 |
| 完了判定 | `NOT READY`。フェーズ1の必須試験がすべて`PASS`し、フェーズ2は未実装3点の解消条件とともに`BLOCKED`として明記され、計画対実績・差異・未解決事項・残存リスクが作業結果報告と受領記録に記載された時点で初めて判定が更新されます |

## 3. 機能要件

| ID | 要件 | 受け入れ確認 | 実装・設計先 |
| --- | --- | --- | --- |
| FR-01 | `wsus-01`を`corp.example.test`ドメインへメンバーサーバーとして参加させ、コンピューターオブジェクトを`Servers`OUへ配置すること | SUT-01, SIT-01 | [構築手順書](05-build-procedure.md) |
| FR-02 | WSUSロール(WID使用)をインストールし、コンテンツストアをOSボリュームとは別の専用ボリュームに配置すること | SUT-02, SUT-03, SIT-01 | [構築手順書](05-build-procedure.md)、[詳細設計書](02-detailed-design.md) |
| FR-03 | Microsoft Updateを同期元とし、対象製品・分類を絞った初回同期を成功させること | SIT-03 | [構築手順書](05-build-procedure.md) |
| FR-04 | GPOによるクライアント側ターゲティングを構成し、`wsus-01`自身をWSUSクライアントとして登録・承認・適用まで一巡させること | SIT-04, SIT-05 | [構築手順書](05-build-procedure.md)、[詳細設計書](02-detailed-design.md) |
| FR-05 | コンピューターグループ・承認ルールを設計し、少なくとも1件の自動承認ルールを構成すること | SIT-06 | [詳細設計書](02-detailed-design.md) |
| FR-06 | WSUSサーバークリーンアップウィザード相当のコマンドレットの定期実行をスケジュールすること | SIT-07 | [構築手順書](05-build-procedure.md) |
| FR-07 | SUSDB・コンテンツストア・IIS構成のバックアップ手順を用意すること | SIT-08 | [構築手順書](05-build-procedure.md) |
| FR-08 | 中央Linux監視基盤へ`wsus-01`を監視対象ホストとして統合すること(フェーズ2、要ネットワーク拡張。`BLOCKED`前提) | SIT-09 | `ansible/roles/app/defaults/main.yml`(`app_node_exporter_targets`)、`compose.yaml`(`monitoring`ネットワークの拡張が必要) |

## 4. 非機能要件

| ID | 分類 | 要件 | 受け入れ確認 |
| --- | --- | --- | --- |
| NFR-01 | 可用性/冪等性 | 構築手順の2回目実行で不要な変更(ロール再インストール、GPO重複作成、Firewallルール重複等)が発生しないこと | SIT-02 |
| NFR-02 | セキュリティ | Windows Defender FirewallはDefault Inbound Blockとし、許可経路(WinRM/WSUSコンテンツ/windows_exporter)を個別に最小化すること | SST-01, SNW-08 |
| NFR-03 | セキュリティ | WinRMはHTTPS専用とし、Basic認証を無効化すること | SST-02, SNW-09 |
| NFR-04 | セキュリティ | RDPは既定Disableとすること | SST-03 |
| NFR-05 | 運用性 | コンテンツストアの増加を抑えるため、同期対象の言語・製品・分類を絞ること | SIT-03 |
| NFR-06 | 運用性 | クリーンアップウィザード相当のコマンドレットを定期実行し、ディスク枯渇を防ぐこと | SIT-07 |
| NFR-07 | 性能 | IISアプリケーションプール(`WsusPool`)の推奨設定(アイドルタイムアウト0、キュー長拡大、プライベートメモリ制限0)を適用し、同期・クライアント通信の失敗を防ぐこと | SIT-01, SNW-06 |
| NFR-08 | 可観測性 | WSUSコンソールのレポート機能で承認状況・準拠状況を確認できること。Windows Server 2016以降のWSUSコンソールでレポート機能を使うには、別途レポート表示用ランタイムの追加インストールが必要になる場合があるという、実務でよく知られたつまずきを手順へ明記すること | SIT-06 |
| NFR-09 | 復旧性 | SUSDB・コンテンツストアのバックアップ/リストア手順を用意すること | SIT-08 |

## 5. 制約と対象外

- 複数クライアントでの大規模検証は対象外です。本パックは`wsus-01`自身をWSUSクライアントとして自己登録・承認・適用まで一巡させる範囲にとどめ、他ホスト(`ad-dc01`、`ad-dc02`、`monitor-win-01`等)をWSUS管理下に追加する展開は発展課題とします。
- WSUS通信のHTTPS化(証明書配布、8531番ポート)は対象外・次点課題です。内部CA(AD証明書サービス)がこのラボに存在しないため、本パックの既定はHTTP(8530番ポート)とします。
- 外部SQL Serverへの移行(データベース方式の系統B)は設計差分のみを記載し、実装・構築は対象外です。
- レプリカ/ダウンストリームWSUSサーバーによる階層化構成は対象外です。本パックの`wsus-01`は最初かつ唯一のWSUSサーバー(スタンドアロン/ルート)とします。
- SSRS(SQL Server Reporting Services)連携は対象外です。データベース方式がWIDであるため、SSRSは利用できません。
- プロキシ経由でのMicrosoft Update同期は対象外です。ラボでは直接接続とします。
- 24時間有人監視、複数拠点、実組織の個人情報、商用SLAは対象外です。
- 中央監視基盤本体(Prometheus/Grafana/Loki/Alertmanagerの構成)の変更は対象外です。既存のLinux版設計([詳細設計書](../build-package/02-detailed-design.md))のまま変更しません。
- フェーズ2(中央監視統合)に必要な3点(Windows対応Ansible role、`compose.yaml`の`monitoring`ネットワークの外部到達、Windows向けログ集約経路)は、[Windows版パック](../build-package-windows/00-requirements.md)・[AD版パック](../build-package-ad/00-requirements.md)と共通の制約であり、「対象外」ではなく「解消条件付きの`BLOCKED`」として扱います。
- Windows Server 2022 Server Coreでの構築は検討課題であり、本案件の基準VMはDesktop Experienceです。
- クラウド(Azure/AWS等)のWindows Serverインスタンスでの構築は[立ち上げ環境の選択肢](10-host-bringup-and-acceptance.md)に示す選択肢の一つに過ぎず、`apply`/`destroy`相当の実行証跡がない限り本案件の構築実績には含めません。

## 6. 前提条件

- [AD版パック](../build-package-ad/00-requirements.md)の構築(`ad-dc01`、`ad-dc02`)が完了し、ドメイン`corp.example.test`のAD統合DNS、`Servers`OUを含む6OU構成が既に存在すること。
- 管理端末からWinRM(HTTPS)で`wsus-01`へ接続でき、接続アカウントがドメイン参加操作および対象VMの管理者権限(ローカルAdministrator相当、またはドメインの委任された権限)を持つこと。
- 対象IPv4/prefix(例示`192.0.2.52/24`。`ad-dc01`=`192.0.2.50/24`、`ad-dc02`=`192.0.2.51/24`と同一レンジで、重複を避けて52を使用)、管理元CIDR、内部ネットワークCIDR、作業時間帯が作業前に確定していること。管理元CIDR・内部ネットワークCIDRは環境ごとに`NOT SET`です。
- コンテンツストア用のDドライブ(100GB以上)をVM/ハイパーバイザー側で事前に確保できること。
- windows_exporterのインストーラのSHA256とダウンロード元を実機決定時に記録できること。バージョンは現時点で`NOT SET`です。
- PowerShell 7.4系を導入する場合の配布元・SHA256を確認できること。
- 中央監視host(`monitor-01`)側の変更(`app_node_exporter_targets`への追記、`site.yml`の再適用)を実施できる権限を持つ運用者が別途存在すること(本パックはWindows側のみを担当します)。

## 7. 要件トレーサビリティと判定

詳細な操作・期待結果は[試験仕様書・結果票](06-test-specification.md)を正本とします。結果はその原本へ直接記入せず、日付付きのevidenceへコピーして保存します。試験ID体系は、単体・設定確認を`SUT`、構築・結合試験を`SIT`、セキュリティ試験を`SST`、ネットワーク実機検証を`SNW`とし、[Windows版パック](../build-package-windows/06-test-specification.md)の`W`、[AD版パック](../build-package-ad/06-test-specification.md)の`A`、[Zabbix版パック](../build-package-zabbix/06-test-specification.md)の`Z`と衝突しないよう、本パック専用の接頭辞`S`(末尾の"SUS"に由来)を使います。

| 判定 | 意味 |
| --- | --- |
| `PASS` | 期待結果を実出力で確認し、証跡への参照がある |
| `FAIL` | 実行したが期待結果と一致しない |
| `BLOCKED` | 前提不足で実行できず、理由と解除条件がある |
| `NOT RUN` | 未実行。成功実績として数えない |

設計値と実績値は必ず分けて記録し、未実施の実績値は`NOT SET`/`NOT RUN`/`NOT READY`のいずれかを使います。安易に`PASS`へ書き換えないでください。現時点の結果は[検証証跡台帳](../evidence/README.md)を参照してください。資料が揃ったことと、構築案件が完了したことは別の状態です。

フェーズ1必須ID(`SUT-01`〜`05`、`SIT-01`〜`08`、`SST-01`〜`06`、`SNW-01`〜`09`)はすべて`NOT RUN`です。フェーズ2必須ID(`SIT-09`)は、実行しても前提が揃わず`BLOCKED`になることが設計時点で分かっています。

| 要件ID | 対応する試験ID |
| --- | --- |
| FR-01 | SUT-01, SIT-01 |
| FR-02 | SUT-02, SUT-03, SIT-01 |
| FR-03 | SIT-03 |
| FR-04 | SIT-04, SIT-05 |
| FR-05 | SIT-06 |
| FR-06 | SIT-07 |
| FR-07 | SIT-08 |
| FR-08 | SIT-09(`BLOCKED`前提) |
| NFR-01 | SIT-02 |
| NFR-02 | SST-01, SNW-08 |
| NFR-03 | SST-02, SNW-09 |
| NFR-04 | SST-03 |
| NFR-05 | SIT-03 |
| NFR-06 | SIT-07 |
| NFR-07 | SIT-01, SNW-06 |
| NFR-08 | SIT-06 |
| NFR-09 | SIT-08 |

`SUT-04`(windows_exporterインストーラのSHA256検証)、`SUT-05`(PowerShell 7.4系導入確認)は個別のFR/NFRに一対一で対応せず、フェーズ1全体の前提条件確認として扱います。`SNW-01`〜`05`、`07`(interface/IP/CIDR、route/gateway、DNS、ICMP、待受port、packet capture)も同様に、NFR-02・NFR-03の実機確認を補強する項目です。
