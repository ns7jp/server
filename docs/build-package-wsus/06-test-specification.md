# 試験仕様書・結果票

[要件定義書](00-requirements.md)の受け入れ条件を、再実行できるコマンドと期待結果へ展開した原本です。試験ID体系(単体・設定確認`SUT`/構築・結合試験`SIT`/セキュリティ試験`SST`/ネットワーク実機検証`SNW`。接頭辞`S`は[Windows版](../build-package-windows/06-test-specification.md)の`W`、[AD版](../build-package-ad/06-test-specification.md)の`A`、[Zabbix版](../build-package-zabbix/06-test-specification.md)の`Z`と衝突しない末尾"SUS"由来の選択)の正本は本書とし、他の文書([ネットワーク実機検証手順](09-network-validation-procedure.md)含む)は本書のIDを参照するだけに留めます。

> ## この文書の読み方(先に読んでください)
>
> **下の表がすべて`NOT RUN`なのは、まだ何も試していないからです。** [Windows版パック](../build-package-windows/06-test-specification.md)と同じく、`wsus-01`に相当する検証用ホストがまだ構築されていない段階の**空白の原本**であり、結果を書き込んでも上書きせず常に`NOT RUN`のまま保存します。実施結果は日付付きの証跡ファイル(例: `docs/evidence/YYYY-MM-DD-wsus-build-validation.md`)へコピーして記録し、命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせます。依存案件の[AD版パック](../build-package-ad/README.md)は実機評価済みの体裁ですが、本パックは踏襲せず「作成済みだが未実施」の状態を保ちます。
>
> ### SIT-09(フェーズ2)はBLOCKEDが前提です
>
> **SIT-09**は、[要件定義書](00-requirements.md)の次の未実装3点が解消するまで`BLOCKED`になることが設計時点で分かっています。[Windows版](../build-package-windows/00-requirements.md)・[AD版](../build-package-ad/00-requirements.md)と同一の理由付けです。
>
> 1. Windows対応Ansible role(`common_windows`等)が`ansible/roles`に無い
> 2. 中央監視hostのDockerホストと`wsus-01`の実ネットワーク接続、およびwindows_exporter(9182/tcp)のFirewall許可先(Dockerホストの実IP)が未検証(Prometheusは`host-access`ネットワーク経由でNAT egress自体は持つが、実接続とFirewall許可先の確定が無い)
> 3. Windows Event Log / IISログを既存Lokiへ送る経路(Grafana Alloy for Windows等)が無い
>
> `BLOCKED`は失敗ではなく前提条件と解除条件を記録した状態ですが、本書は実行していない空白の原本なので結果欄はなお`NOT RUN`とし、実際に`BLOCKED`と確定した時点で証跡へ記入します。ネットワーク実機検証(SNW-01〜09)の記入様式は[WSUS版ネットワーク結果票テンプレート](../evidence/templates/network-host-validation-wsus.md)です。

## 記録情報

| 項目 | 値 |
| --- | --- |
| 実施日時 / 実施者 / 環境 | `NOT RUN` |
| ホストのビルド番号(`winver`または`OsBuildNumber`) | `NOT SET` |
| ドメイン参加状態(`Get-ADComputer wsus-01`のDN) | `NOT SET` |
| WSUSロールのバージョン / コンテンツストア空き容量 | `NOT SET` |
| windows_exporterバージョン / SHA256 | `NOT SET` |
| PowerShellバージョン(組込5.1 / 追加導入7.4系) | `NOT SET` |

結果は`PASS / FAIL / BLOCKED / NOT RUN`のいずれかとし、初期値の`NOT RUN`は成功実績ではありません。

| 判定 | 意味 |
| --- | --- |
| `PASS` | 期待結果を実出力で確認し証跡への参照がある |
| `FAIL` | 実行したが一致しない |
| `BLOCKED` | 前提不足で実行できず理由と解除条件がある |
| `NOT RUN` | 未実行、成功実績として数えない |

設計値と実績値は必ず分けて記録し、未実施の実績値は`NOT SET`/`NOT RUN`を使い、安易に`PASS`へ書き換えません。

## 単体・設定確認

`wsus-01`実機が無くても、コマンドの妥当性やインストーラ入手までは先行して確認できます。実機の有無を理由に着手を遅らせないでください。

| ID | 確認対象 | 主コマンド | 期待結果 | 結果 | 証跡位置 |
| --- | --- | --- | --- | --- | --- |
| SUT-01 | ドメイン参加確認 | `Get-ADComputer wsus-01 -Properties DistinguishedName` | DNが`Servers`OU配下(既定`Computers`コンテナではない) | NOT RUN | — |
| SUT-02 | WSUS機能インストール確認 | `Get-WindowsFeature UpdateServices` | `Installed`(本体機能とWID接続用サブ機能を含む) | NOT RUN | — |
| SUT-03 | WSUSサービス起動確認 | `Get-Service WsusService` | `Running`。`wsusutil postinstall`実行済みでコンソールが正常起動 | NOT RUN | — |
| SUT-04 | windows_exporterのSHA256検証 | `Get-FileHash <msi> -Algorithm SHA256` | GitHub Releases公開値と一致(現時点`NOT SET`) | NOT RUN | — |
| SUT-05 | PowerShell 7.4系導入確認 | `$PSVersionTable`、`pwsh -v` | 組込5.1・追加導入7.4系とも想定どおり | NOT RUN | — |

SUT-04・05はフェーズ1全体の前提条件確認として扱います。

## 構築・結合試験

| ID | 確認対象 | 主コマンド | 期待結果 | 結果 | 証跡位置 |
| --- | --- | --- | --- | --- | --- |
| SIT-01 | 初回構築成功 | ドメイン参加→WSUSロール導入→`wsusutil postinstall CONTENT_DIR=D:\WSUS\WSUSContent`→`WsusPool`チューニング | エラーなく完了、コンソール正常起動、コンテンツストアがDドライブに配置 | NOT RUN | — |
| SIT-02 | 2回目実行での冪等性 | SIT-01の手順を再実行 | ロール再作成・GPOリンク重複・Firewallルール重複等が発生しない | NOT RUN | — |
| SIT-03 | Microsoft Update初回同期成功 | 構成ウィザードで言語(英語/日本語)・製品(Windows Server 2022、Windows 11)・分類(Critical/Security/Updates/Update Rollups)を設定し同期実行 | エラーなく完了しメタデータ取得。所要時間は計測記録し具体値は断定しない | NOT RUN | — |
| SIT-04 | GPO適用とwsus-01自己登録 | `gpupdate /force`後`gpresult /r /scope computer`と`Get-WinEvent -LogName "Microsoft-Windows-GroupPolicy/Operational"`、WSUSコンソールの`Servers`グループを確認 | `WSUS-Client-Policy`がエラーなく適用され`wsus-01`が`Servers`グループへ自己登録 | NOT RUN | — |
| SIT-05 | 承認済み更新のダウンロード・インストール | WSUSコンソールでCritical/Security分類を手動承認後、対象host側で検出・ダウンロード・インストール | 承認分のみ適用。準拠状況はWSUSコンソールのレポート機能(表示用ランタイム追加が必要な場合あり)で確認 | NOT RUN | — |
| SIT-06 | 自動承認ルールの動作確認 | 「Critical and Security Updates - Pilot Auto-Approve」を手動実行 | 分類Critical/Security、製品Windows Server 2022、対象`Pilot`の更新のみ自動承認。他は手動承認 | NOT RUN | — |
| SIT-07 | クリーンアップウィザードの正常終了 | `Invoke-WsusServerCleanup`を手動実行、またはタスクスケジューラ登録(毎週日曜03:00 Asia/Tokyo)を確認 | エラーなく終了し不要なメタデータ・コンテンツが削除 | NOT RUN | — |
| SIT-08 | SUSDB・コンテンツストアのバックアップ・リストア | (1)SUSDB(WID名前付きパイプ経由またはWindows Server Backupでシステム状態取得)(2)コンテンツストア全体(3)IISのWSUS管理サイト構成、を取得し別ボリューム/別ホストへ復元 | 3点とも復元後に内容一致 | NOT RUN | — |
| SIT-09 | 中央監視統合(フェーズ2) | 中央PrometheusのTargets画面を確認 | `up{job="linux-node", host="wsus-01"}=1`(**BLOCKED前提**: 上記未実装3点の解消まで実行不能) | NOT RUN | — |

## セキュリティ試験

| ID | 確認対象 | 主コマンド | 期待結果 | 結果 | 証跡位置 |
| --- | --- | --- | --- | --- | --- |
| SST-01 | Firewall既定Blockと許可経路の最小化 | `Get-NetFirewallProfile`、`Get-NetFirewallRule \| Where Enabled` | 既定Default Inbound Block。許可はWinRM(5986、管理元CIDR)、WSUSコンテンツ(8530、内部ネットワークCIDR)、windows_exporter(9182、中央Prometheus host IP)のみ | NOT RUN | — |
| SST-02 | WinRM HTTPS必須・Basic認証無効 | `winrm enumerate winrm/config/listener`、`Get-Item WSMan:\localhost\Service\Auth\Basic` | listenerはHTTPSのみ、Basic認証`false` | NOT RUN | — |
| SST-03 | RDP既定Disable | `Get-NetFirewallRule -DisplayGroup "リモート デスクトップ"` | 既定Disable | NOT RUN | — |
| SST-04 | WSUS管理サイトの内部ネットワークCIDR限定公開 | 内部ネットワークCIDR外から`http://wsus-01.corp.example.test:8530`へ接続試行、該当ルールの`RemoteAddress`確認 | CIDR外からは到達不可、許可範囲が設計と一致 | NOT RUN | — |
| SST-05 | ローカルAdministrator・サービスアカウントの権限最小化 | `Get-LocalUser Administrator`、`Get-LocalGroupMember "WSUS Administrators"`、WsusServiceの`StartName` | Administrator名変更済み、`WSUS Administrators`メンバー最小限、サービスアカウントが設計値と一致 | NOT RUN | — |
| SST-06 | 監査ログの有効化確認 | `auditpol /get /category:*`、`Get-WinEvent`(Security、グループポリシー操作ログ) | 該当サブカテゴリが成功/失敗とも監査対象 | NOT RUN | — |

## ネットワーク実機検証

[Windows版](../build-package-windows/06-test-specification.md)の`WNW-01〜09`、[AD版](../build-package-ad/06-test-specification.md)の`ANW-01〜09`に対応するIDです。詳細手順は[ネットワーク実機検証手順](09-network-validation-procedure.md)を正本とし、記入様式は[WSUS版ネットワーク結果票テンプレート](../evidence/templates/network-host-validation-wsus.md)です。

| ID | 確認対象 | 主コマンド | 期待結果 | 結果 | 証跡位置 |
| --- | --- | --- | --- | --- | --- |
| SNW-01 | interface / IP / CIDR | `Get-NetAdapter`、`Get-NetIPAddress` | `192.0.2.52/24`とOS実装が一致 | NOT RUN | — |
| SNW-02 | route / gateway | `Get-NetRoute`、`Test-NetConnection -TraceRoute` | 既定gatewayへの経路が設計どおり | NOT RUN | — |
| SNW-03 | DNS(`corp.example.test`ゾーン) | `Resolve-DnsName` | `wsus-01.corp.example.test`のAレコード等が想定どおり解決 | NOT RUN | — |
| SNW-04 | ICMP | `Test-Connection`(管理端末⇔対象、対象⇔ADドメインコントローラー) | 設計どおりの到達性。遮断方針の場合はTCP/HTTP試験を優先 | NOT RUN | — |
| SNW-05 | 待受port | `Get-NetTCPConnection -State Listen` | `5986`/`8530`/`9182`が待受、`3389`は既定Disableで非待受 | NOT RUN | — |
| SNW-06 | TCP / HTTP | `Invoke-WebRequest`(WSUS管理サイト、windows_exporterの`/metrics`) | WSUS管理サイトは内部ネットワークCIDR内から到達、exporterは中央Prometheus host以外拒否。`WsusPool`のアイドルタイムアウト0・キュー長2000・メモリ制限0も`Get-IISAppPool`で確認 | NOT RUN | — |
| SNW-07 | packet capture | `pktmon`(Windows組込) | ヘッダのみ採録、本文非採録で想定パケットを確認 | NOT RUN | — |
| SNW-08 | Windows Defender Firewall | `Get-NetFirewallProfile`、`Get-NetFirewallRule` | プロファイル`Domain`と許可ルールが設計と一致 | NOT RUN | — |
| SNW-09 | end-to-end | 管理元CIDR外からのWinRM接続、内部ネットワークCIDR外からのWSUSコンテンツ接続を試行 | いずれも拒否。WinRM HTTPSは通信自体が暗号化されるため、Linux版SSHトンネル相当の追加トンネルは不要という非対称性を確認 | NOT RUN | — |

## 終了判定

- フェーズ1必須ID: `SUT-01`〜`05`、`SIT-01`〜`08`、`SST-01`〜`06`、`SNW-01`〜`09`。フェーズ2必須ID: `SIT-09`(未実装3点の解消後に必須化)。
- フェーズ1必須IDに`FAIL`・`BLOCKED`・`NOT RUN`が1件でも残る場合、フェーズ1(ホスト単体構築)は完了としません。
- `SIT-09`は未実装3点(Windows対応Ansible role、Dockerホストと`wsus-01`の実ネットワーク接続・windows_exporterのFirewall許可先の確定、Windows向けログ集約経路)が解消するまで`BLOCKED`が前提であり、このこと自体はフェーズ1の完了判定に影響しません。解消後も`NOT RUN`のままならフェーズ2(中央監視統合)は完了としません。
- 構築案件全体の完了は、フェーズ1必須試験がすべて`PASS`し、かつフェーズ2が未実装3点の解消条件とともに`BLOCKED`として明記された状態を指します。両方が揃って初めて[作業結果・引き渡し報告書](11-work-result-report.md)へ記載できます。
- 結果はこの原本を直接上書きせず、日付付きの証跡ファイルへコピーして保存します。命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせます。
