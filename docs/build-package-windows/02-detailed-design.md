# 詳細設計書

本書は[基本設計書](01-basic-design.md)を受けて、monitor-win-01(Windows Server 2022 Standard、Desktop Experience基準)側のコンポーネント構成・配備手順・アクセス制御・ログ監視・バックアップ/ロールバックを定義します。中央監視host(論理名 monitor-01)側の構成は変更しません。フェーズ1(ホスト単体構築)とフェーズ2(中央監視統合)の区分は[要件定義書](00-requirements.md)のとおりで、フェーズ2は「未実装」2点が解消するまで`BLOCKED`です。

## コンポーネント設計

| コンポーネント | 実装 | 依存先 | 正常性確認 |
| --- | --- | --- | --- |
| IIS | Windows付属のWeb-Server機能(`Web-Common-Http`, `Web-Mgmt-Console`)。検証用サイトとhealth用エンドポイントを公開 | Windows Defender Firewall(80/443許可、内部/管理ネットワークのみ)、host OS | フェーズ1: health用エンドポイントが200(WIT-04) |
| windows_exporter | 署名付きMSI導入、Windowsサービス(既定LocalSystem)。`--collectors.enabled`でcpu, cs, logical_disk, net, os, service, system, iisを有効化 | Windows Defender Firewall(9182許可、中央Prometheus hostのIPのみ)、host OS | フェーズ1: `curl.exe http://localhost:9182/metrics`がローカルで200。フェーズ2: 中央Prometheus Targets画面で`up{job="linux-node", host="monitor-win-01"}=1`(WIT-03。`remote-targets` network追加によりコードは実装済み、対象ホスト未構築のため`NOT RUN`) |
| Grafana Alloy for Windows | 未実装。導入すれば既存`compose.yaml`のAlloyと合わせv1.16.1系を基準にする設計のみ | 中央Loki(push API)、Windows Event Log、IISログファイル | 未実装のため実行不可。導入後はGrafanaでLogQL検索できること(WIT-06、現状`BLOCKED`) |
| Windows Defender Firewall | `netsh advfirewall`または`New-NetFirewallRule`によるinbound rule管理。Default Inbound Block | host OS標準機能(追加依存なし) | フェーズ1: `Get-NetFirewallRule \| Where Enabled`で許可Portと送信元が設計と一致(WST-04) |
| WinRMリスナー | HTTPSリスナー+証明書(自己署名または内部CA)。Basic/Negotiateの平文相当は無効化 | 証明書ストア、Windows Defender Firewall(5986許可) | フェーズ1: `winrm enumerate winrm/config/listener`でHTTPSのみ、Basic無効を確認(WST-01) |
| 中央Prometheus | 既存Compose上のPrometheus本体はコード変更なし。scrape対象は`ansible/roles/app/defaults/main.yml`の`app_node_exporter_targets`変数で管理。`compose.yaml`側はPrometheusサービスのみ`remote-targets` networkを追加接続 | `app_node_exporter_targets`変数、windows_exporter(9182到達は`remote-targets` network追加によりコード実装済み) | フェーズ2: `up{job="linux-node", host="monitor-win-01"}=1`(WIT-03。monitoring networkの外部到達制約は`remote-targets` network追加で解消済み。対象ホスト未構築のため`NOT RUN`) |
| 中央Grafana | 既存provisioning(変更なし) | 中央Prometheus、中央Loki | 既存のまま`/api/health`が正常(Windows追加による変更なし) |
| 中央Alertmanager | 既存route/inhibit設定(変更なし) | 中央Prometheus | 既存のまま`/-/ready`が200(Windows追加による変更なし) |
| 中央Loki | 既存filesystem store(変更なし) | Alloy(Linux側は既存稼働、Windows側は未導入) | 既存のまま`/ready`が200。Windows側ログ検索はAlloy for Windows導入まで未対応(WIT-06、`BLOCKED`) |

## 配備設計

フェーズ1はAnsible role化されていないため、[構築手順書](05-build-procedure.md)のPowerShell手順による「済(手動)」が中心です。系統A(ワークグループ)/系統B(ADドメイン参加)の差分は[基本設計書](01-basic-design.md)および[パラメータシート](03-parameter-sheet.md)を正本とし、本書では手順の位置づけのみ示します。

1. **OS初期設定(済・手動)**: コンピューター名(monitor-win-01相当)、timezone(Asia/Tokyo)、ローカルAdministratorの既定名からの変更、PowerShell 7.4系の追加導入、Windows Updateの設定を行います。系統Aはローカルアカウント運用、系統Bは既存ADドメインへの参加が前提です(ADドメイン自体の構築は対象外)。
2. **Firewall設定(済・手動)**: Windows Defender FirewallをDefault Inbound Blockで確認し、WinRM(5986/tcp、管理元CIDR限定)、IIS(80/443/tcp、内部/管理ネットワークのみ)、windows_exporter(9182/tcp、中央Prometheus hostのIPのみ)を個別に許可します。RDP(3389/tcp)は既定Disableのままとします。WinRM HTTPSリスナー用証明書もこの段階で作成・バインドします。
3. **IIS導入(済・手動)**: `Web-Common-Http`、`Web-Mgmt-Console`を含むWeb-Server機能を有効化し、検証用サイトとhealth用エンドポイントを構成します。
4. **windows_exporter導入(済・手動)**: GitHub Releasesの署名付きMSIをダウンロードし、公開SHA256とのハッシュ一致(WUT-03)を確認したうえでインストールします。バージョンは実機決定時に固定するため現時点では`NOT SET`です。`--collectors.enabled`にcpu, cs, logical_disk, net, os, service, system, iisを指定し、サービスが起動することを確認します(既定LocalSystem、最小権限化はWST-03で残存課題として記録)。
5. **ログ収集(未実装・将来)**: Grafana Alloy for Windowsの導入設計のみで、コード・手順は未整備です。Windows Event Log/IISログをLokiへpushする経路は、Lokiのpush APIをloopback以外から安全に受け付けるための認証・network設計が無いため、現時点では実施しません(FR-05、WIT-06、`BLOCKED`)。
6. **バックアップ設定(済・手動)**: Windows Server Backup機能を導入し、Task Schedulerへ毎日03:30(Asia/Tokyo)実行のタスクを登録します。保持世代は14日です。詳細は本書「バックアップ・ロールバック」を参照してください。
7. **中央監視統合(フェーズ2・残り2点の解消まで`BLOCKED`)**: `app_node_exporter_targets`へのWindowsホスト1行追加とcentral host側での`site.yml`再適用は「済(自動)」で今すぐ実行できます。Prometheusコンテナから同じDockerホスト外の実machine(windows_exporter、既定9182/tcp)への到達は、Prometheusサービスのみを`internal`ではない`remote-targets` bridge network(`compose.yaml`)へ追加接続する形で実装済みです。あわせてblackbox probe対象(FR-04)も`prometheus.yml.j2`の`app_blackbox_probe_targets`変数で汎用化済みで、IISのhealthエンドポイント等をnode_exporter targetsと同じ「1行追加」の形でprobe対象へ加えられます。ただし対象ホストmonitor-win-01自体がまだ構築されておらず、実機windows_exporter/IISへのscrape/probe成功実績はまだ無いため、WIT-03・WIT-05は`NOT RUN`のままです。また、Windowsを既存job名`linux-node`に混ぜること自体が名前と実態の不一致を生む点は残存課題のままです。Alloy for Windows導入(FR-05)は未実装であり、この1点が解消するまでWIT-06(ログ集約)は`BLOCKED`のままです。
8. **動作確認**: フェーズ1はWIT-01, WIT-02, WIT-04, WIT-08, WIT-09, WIT-10、WST-01〜WST-06、WNW-01〜WNW-09を実施します。フェーズ2はWIT-03, WIT-05, WIT-06, WIT-07, WIT-11を実施しますが、WIT-06のみ上記7に記載のAlloy for Windows未導入により`BLOCKED`です。WIT-03・WIT-05・WIT-07・WIT-11はコード側の制約が解消済みのため、対象ホスト構築後は`NOT RUN`から実施できます。判定基準は[試験仕様書・結果票](06-test-specification.md)を正本とします。

## アクセス制御

WinRM/IIS/windows_exporterのFirewallルールは、許可送信元を管理元CIDRまたは中央Prometheus hostのIPに限定します。既定はDefault Inbound Blockであり、明示的に許可した通信のみを通します。Firewallプロファイルは系統A(ワークグループ)ではPublic(検証用途に応じてPrivateへ変更可)、系統B(ADドメイン参加)ではDomainです。SELinuxに相当する追加の強制アクセス制御機構は既定では使用しません(該当なし)。

| 経路 | 公開範囲 | 認証 |
| --- | --- | --- |
| WinRM(HTTPS) | 管理元CIDR限定 | 証明書 または Kerberos/Negotiate(Basic無効) |
| RDP | 既定Disable。一時許可時のみ管理元CIDR | Windowsログオン資格情報 + NLA必須 |
| IIS | 内部/管理ネットワークのみ | 検証用は匿名 or Windows認証(用途に応じて設計) |
| windows_exporter | 中央Prometheus hostのIPのみ | 認証なし、ネットワーク制限のみ(Linuxのnode-exporterと同じ思想) |
| 中央Prometheus/Grafana/Alertmanager/Loki | 既存Linux版設計のまま変更なし | [../build-package/02-detailed-design.md](../build-package/02-detailed-design.md)参照 |

## ログ・監視設計

現時点ではWindows Event Log/IISログは中央Lokiへ送られていません(Grafana Alloy for Windows未導入のため、FR-05はフェーズ2、`BLOCKED`)。導入後の設計方針はLinux版を踏襲します。

- 固定値だけをLokiラベルにし、IP、URL、ユーザーIDは本文へ残します。
- アラートにはseverity、summary、description、runbook URLを持たせます(中央Alertmanager側、変更なし)。
- アラート通知先の秘密値は中央側の既存の仕組み(`compose.slack.yaml.example`とローカルsecret)のまま注入し、Windows側で新たな秘密値の注入経路は追加しません。

アラート確認時の切り分け順「メトリクス → 直近変更 → ログ → プロセス」はLinux版と共通ですが、Windows側はログ集約(フェーズ2)が未実装のため、フェーズ1時点では次の代替手順で一次切り分けを行います。

- メトリクス: windows_exporterのメトリクスを`curl.exe http://localhost:9182/metrics`でローカルから直接確認します(中央Prometheusが未到達のため、フェーズ2実装までは実機ログイン/WinRM経由の直接確認に限定されます)。
- 直近変更: [変更・ロールバック計画](08-change-rollback-plan.md)の記録を確認します。
- ログ: `Get-WinEvent`またはイベントビューアーでWindows Event Logを直接参照し、IISログは既定パス(`C:\inetpub\logs\LogFiles`)をWinRM/RDP経由で直接参照します。Lokiでの横断検索は未対応です。
- プロセス: `Get-Process`、`Get-Service`で確認します。

一次切り分けの記録様式は[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)を共用します。

## バックアップ・ロールバック

- Windows Server Backup機能(`wbadmin`)を導入し、IISサイトの内容・設定(`web.config`等)、Firewallルールのエクスポート(`netsh advfirewall export`)、windows_exporterのサービス定義をバックアップ対象とします。
- スケジュールは毎日03:30(Asia/Tokyo)、Task Schedulerに登録します。保持世代は14日(Linux版の`backup_retention_days`と同じ値)です。
- 復元試験(WIT-09)は別ボリューム/別ホストへ復元し、内容が一致することを確認する試験です。バックアップの日次取得設定そのものとは別に管理し、現時点でWIT-09は`NOT RUN`です([検証証跡台帳](../evidence/README.md)参照)。
- Windows対応Ansible roleが無いため、構成変更のロールバックは優先順位順に次の手段を使います。
  1. VM/ハイパーバイザーのスナップショット復元(Hyper-Vの`Checkpoint-VM`/`Restore-VMCheckpoint`、VMware等)を最優先の手段とします。取得タイミングは変更直前です。
  2. スナップショットが無い場合は、変更前に取得したFirewallルールのエクスポート(`netsh advfirewall export`)、レジストリの該当キーのエクスポート、IIS設定のエクスポート(`appcmd add backup`)を個別に戻します。
  3. データ破損時はWindows Server Backupからの復元(上記バックアップ設計を参照)を使用します。
- Go/No-Go条件、実施結果記録の様式は[変更・ロールバック計画](08-change-rollback-plan.md)にLinux版[08-change-rollback-plan.md](../build-package/08-change-rollback-plan.md)と同じ構造で定義します。
- D-1相当のサービス停止復旧演習(WIT-08)と、上記ロールバック手段の実施結果(スナップショット復元/個別エクスポート復元/Windows Server Backup復元)は別試験として扱い、それぞれ日付付きのevidenceへ記録するまで`NOT RUN`です。
