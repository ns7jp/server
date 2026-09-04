# 要件定義書

> 💡 **初めて読む方へ**: この文書は「何を作るか」「完成の合格基準」を先に決める文書です。`NFR`（非機能要件）や`AIT-xx`のような略語につまずいたら、先に[案件パック 初心者ガイド](beginner-guide.md#00-要件定義書)を確認してください。

## 1. 文書の位置づけ

本パックは、新規のActive Directoryフォレスト・ドメイン(`corp.example.test`)を作成し、最初のドメインコントローラー(論理ホスト名`ad-dc01`)を構築して運用担当者へ引き渡す案件(案件ID `SM-AD-001`)として扱います。既存の監視基盤([Linux版パック](../build-package/README.md)、案件ID`SM-LAB-001`)や、既存の監視対象ホスト追加パック([Windows版パック](../build-package-windows/README.md)、案件ID`SM-WIN-001`)とは独立した、新しい構築案件です。本書は要求と受け入れ条件を定義し、設計値の正本は後続資料、実行結果の正本は[検証証跡台帳](../evidence/README.md)に分離します。

本書に「済(自動)」「済(手動)」と書いてあっても、実ホストでの構築・試験完了を意味しません。受け入れ可否は[試験仕様書・結果票](06-test-specification.md)の結果で判定します。[Windows版パック](../build-package-windows/00-requirements.md)と同じ3区分の実装状態を使い、混同しません。

| 区分 | 意味 |
| --- | --- |
| 済(自動) | 既存のAnsible機能で今すぐ実行できるもの。本パックには該当項目がありません(Windows対応role自体が未実装のため) |
| 済(手動) | Ansible化はされていないが、本パックのPowerShell手順で今すぐ実施できるもの(フォレスト作成、DC昇格、OU/GPO設計、windows_exporter導入、バックアップ等) |
| 未実装 | 本パックは設計のみを示しており、コードが無いもの(Windows対応Ansible role、Dockerホストと`ad-dc01`間の実ネットワーク接続およびwindows_exporterのFirewall許可(Dockerホストの実IP)、Windows Event Log/AD監査ログをLokiへ送る経路) |

構築は2段階のフェーズに分かれます。フェーズ1(ホスト単体構築)は「済(手動)」の範囲で`ad-dc01`単体として完結し、フェーズ2(中央監視統合)は上記「未実装」3点の解消まで`BLOCKED`として扱います。これは[Windows版パック](../build-package-windows/00-requirements.md)が抱える制約と同一であり、Windows Serverを新しく中央監視へつなぐ経路そのものが、まだこのリポジトリに無いためです。

## 2. 案件概要

| 項目 | 内容 |
| --- | --- |
| 案件ID | `SM-AD-001` |
| 利用者 | Active Directoryを構築・運用する担当者 |
| 対象環境 | Windows Server 2022 Standard(Desktop Experience基準)、検証用VM 1台、論理ホスト名`ad-dc01` |
| 構築対象 | 新規フォレスト・新規ドメイン(FQDN`corp.example.test`、NetBIOS名`CORP`)の、最初のドメインコントローラー |
| 構築方式 | 本パックのPowerShell手順による手動構築(Windows対応Ansible roleは未実装。[Windows版パック](../build-package-windows/00-requirements.md)と同じ制約) |
| 提供機能 | フォレスト・ドメイン、AD統合DNSゾーン、OU/グループポリシー(パスワードポリシー)、FSMO 5役割、System Stateバックアップ、AD ごみ箱、サービス停止復旧手順 |
| 引き渡し単位 | 設計書、パラメータシート、構築手順、試験結果、作業結果報告、秘密値(DSRMパスワード等)の受け渡し方法 |
| 完了判定 | フェーズ1の必須試験がすべて`PASS`し、フェーズ2は未実装3点の解消条件とともに`BLOCKED`として明記され、計画対実績・差異・未解決事項・残存リスクが作業結果報告と受領記録に記載済み |

## 3. 機能要件

| ID | 要件 | 受け入れ確認 | 実装・設計先 |
| --- | --- | --- | --- |
| FR-01 | 運用者がWinRM(HTTPS)経由で`ad-dc01`を管理できること | AIT-01 | [構築手順書](05-build-procedure.md) |
| FR-02 | 新規フォレスト・ドメイン(`corp.example.test`)が作成され、`ad-dc01`が最初のドメインコントローラーとして昇格を完了すること | AIT-01、AIT-02 | [構築手順書](05-build-procedure.md) |
| FR-03 | AD統合DNSゾーンにより、DC自身とクライアント予定ホストの名前解決(Aレコード・SRVレコード)ができること | AIT-03 | [構築手順書](05-build-procedure.md) |
| FR-04 | 設計したOU構造と既定ドメインGPOのパスワードポリシーが新規オブジェクトへ適用されること | AIT-04 | [詳細設計書](02-detailed-design.md) |
| FR-05 | FSMO 5役割(スキーママスター、ドメイン名前付けマスター、RIDマスター、PDCエミュレータ、インフラストラクチャマスター)がすべて`ad-dc01`に存在することを確認できること | AIT-05 | [構築手順書](05-build-procedure.md) |
| FR-06 | System Stateバックアップを取得し、AD ごみ箱で誤削除オブジェクトを復元できること | AIT-06、AIT-07 | [構築手順書](05-build-procedure.md) |
| FR-07 | ディレクトリサービス関連サービスの停止を検知し、復旧と正常性確認までの時間を記録できること | AIT-08 | [構築手順書](05-build-procedure.md) |
| FR-08 | 管理端末から`ad-dc01`までの名前解決、経路、待受、LDAP/Kerberos到達性、Firewallを確認できること | ANW-01〜09 | [ネットワーク実機検証手順](09-network-validation-procedure.md) |
| FR-09 | windows_exporterのAD/DNS collectorを中央Prometheusが収集できること(フェーズ2、実接続・Firewall許可が未確立) | AIT-09 | `ansible/roles/app/defaults/main.yml`(`app_node_exporter_targets`)、Dockerホスト↔`ad-dc01`間の実接続・windows_exporterのFirewall許可(未確立) |

## 4. 非機能要件

| ID | 分類 | 要件 | 受け入れ確認 |
| --- | --- | --- | --- |
| NFR-01 | 再現性 | 未構築の対象VMへ本パックの手順(手動PowerShell)を適用し、エラーなく完了すること | AIT-01 |
| NFR-02 | 再実行安全性 | 既に昇格済みの`ad-dc01`に対して昇格コマンドを誤って再実行した場合、安全に失敗し既存ドメインを破壊しないこと([Linux版](../build-package/00-requirements.md)・[Windows版](../build-package-windows/00-requirements.md)の「冪等性」とは異なる、AD固有の非機能要件。詳細は[初心者ガイド](beginner-guide.md#5-現場用語ブリッジ)参照) | AIT-11 |
| NFR-03 | セキュリティ | WinRMはHTTPS専用とし、Basic認証を無効化すること | AST-01 |
| NFR-04 | セキュリティ | RDPは既定Disableとし、必要時のみ管理元CIDR限定で一時有効化すること | AST-02 |
| NFR-05 | セキュリティ | LDAP署名とチャネルバインディングを必須化すること | AST-04 |
| NFR-06 | セキュリティ | SMBv1を無効化すること | AST-05 |
| NFR-07 | パスワードポリシー | 既定ドメインGPOで最小長14文字、複雑性要件、ロックアウトしきい値(10回/観察10分/ロックアウト10分)を設定すること | AST-03 |
| NFR-08 | 最小権限 | `Domain Admins`等の特権グループのメンバーを最小限に保ち、Tier0(最高権限層)の考え方を設計へ反映すること | AST-07 |
| NFR-09 | 監査性 | ディレクトリサービスの変更監査を有効化すること | AST-06 |
| NFR-10 | 時刻同期 | PDCエミュレータを権威時刻源とし、外部NTPと同期すること(Kerberosの既定許容時刻差5分の前提を維持) | AIT-02、ANW-04 |
| NFR-11 | 復旧性 | System Stateバックアップ、AD ごみ箱、サービス停止復旧演習でRTOを記録すること | AIT-06、AIT-07、AIT-08 |
| NFR-12 | 保守性 | 変更前後の状態、検証、ロールバック(スナップショット復元を最優先手段とする)条件と結果を記録すること | [変更・ロールバック計画](08-change-rollback-plan.md) |
| NFR-13 | 追跡性 | 実行日時、環境、ホストのビルド番号、実行コマンド、実出力、判定を証跡へ残すこと | 全必須試験 |
| NFR-14 | 完了管理 | 計画対実績、試験集計、設計差異、障害、未実施、受領可否を1件の報告へまとめること | [作業結果・引き渡し報告書](11-work-result-report.md) |
| NFR-15 | 実装境界の明示 | Ansible化されていない手順を「済(手動)」と明記し、既存の`site.yml`のような自動化済み経路と混同しないこと | 全文書共通 |
| NFR-16 | ネットワーク | Windows Defender Firewallは既定Inbound Blockを維持し、AD DS関連の自動生成ルール群は内部ネットワークCIDR、管理系(WinRM/RDP)は管理元CIDR限定で許可すること | AST-08 |

## 5. 制約と対象外

- 単一フォレスト・単一ドメイン・単一ドメインコントローラー(`ad-dc01`1台)の検証用構成であり、複数DCによる可用性・冗長化は対象外です。2台目のDC追加によるレプリケーション実測、RODC(読み取り専用ドメインコントローラー)は、[基本設計書](01-basic-design.md)に記す発展構成としてのみ言及します。
- 24時間有人監視、複数拠点、実組織の個人情報、商用SLAは対象外です。
- AD CS(証明書サービス)、AD FS(フェデレーションサービス)、Microsoft Entra ID(旧Azure AD)連携は対象外です。
- 中央監視基盤本体(Prometheus/Grafana/Loki/Alertmanagerの構成)の変更は対象外です。既存のLinux版設計([詳細設計書](../build-package/02-detailed-design.md))のまま変更しません。
- [Windows版パック](../build-package-windows/README.md)の監視対象ホスト(`monitor-win-01`)をこのドメインへ参加させる作業(系統B相当)は、本パックの対象外です。将来の統合演習として[基本設計書](01-basic-design.md)に言及するにとどめます。
- フェーズ2(中央監視統合)に必要な3点(Windows対応Ansible role、Dockerホストと`ad-dc01`間の実ネットワーク接続およびwindows_exporterのFirewall許可(Dockerホストの実IP)、Windows向けログ集約経路)は、[Windows版パック](../build-package-windows/00-requirements.md)と共通の制約であり、「対象外」ではなく「解消条件付きの`BLOCKED`」として扱います。
- Windows Server 2022 Server Coreでの構築は検討課題であり、本案件の基準VMはDesktop Experienceです。
- クラウド(Azure/AWS等)のWindows Serverインスタンスでの構築は[立ち上げ環境の選択肢](10-host-bringup-and-acceptance.md)に示す選択肢の一つに過ぎず、`apply`/`destroy`相当の実行証跡がない限り本案件の構築実績には含めません。

## 6. 前提条件

- 管理端末からWinRM(HTTPS)で対象VMへ接続でき、接続アカウントが対象VMの管理者権限(ローカルAdministrator相当)を持つこと。初回のフォレスト作成のみ、ハイパーバイザーのコンソールから直接ログオンして行うこと。
- 対象IP、管理元CIDR、内部ネットワークCIDR、ドメインFQDN、NetBIOS名、作業時間帯、費用上限(クラウド利用時)が作業前に確定していること。
- DSRM(ディレクトリサービス復元モード)パスワードを、Git管理外の秘密値台帳で安全に生成・保管・受け渡しできること。実値はこのリポジトリのどの文書にも記載しません。
- windows_exporterのインストーラのSHA256とダウンロード元を実機決定時に記録できること。
- VM/ハイパーバイザーのスナップショット取得手段が利用でき、変更前に取得するタイミングを合意できること。

## 7. 要件トレーサビリティと判定

詳細な操作・期待結果は[試験仕様書・結果票](06-test-specification.md)を正本とします。結果はその原本へ直接記入せず、日付付きのevidenceへコピーして保存します。

| 判定 | 意味 |
| --- | --- |
| `PASS` | 期待結果を実出力で確認し、証跡への参照がある |
| `FAIL` | 実行したが期待結果と一致しない |
| `BLOCKED` | 前提不足で実行できず、理由と解除条件がある |
| `NOT RUN` | 未実行。成功実績として数えない |

設計値と実績値は必ず分けて記録し、未実施の実績値は`NOT SET`/`NOT RUN`/`NOT READY`のいずれかを使います。安易に`PASS`へ書き換えないでください。現時点の結果は[検証証跡台帳](../evidence/README.md)を参照してください。資料が揃ったことと、構築案件が完了したことは別の状態です。
