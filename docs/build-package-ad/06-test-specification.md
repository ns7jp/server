# 試験仕様書・結果票

[要件定義書](00-requirements.md)の受け入れ条件を、再実行できるコマンドと期待結果へ展開した原本です。試験ID体系(AUT / AIT / AST / ANW)の正本は本書とし、他の文書(特に[ネットワーク実機検証手順](09-network-validation-procedure.md))は本書のIDを参照するだけに留めます。

> ## この文書の読み方(先に読んでください)
>
> **下の表がすべて `NOT RUN` なのは、まだ何も試していないからではありません。**
> [Linux版試験仕様書・結果票](../build-package/06-test-specification.md)・[Windows版試験仕様書・結果票](../build-package-windows/06-test-specification.md)と同じく、これは対象ホストが決まっていない段階の**空白の原本**です。`ad-dc01`に相当する検証用ホストを用意するたびに複製して記入し、原本自体は後から上書きしません。
>
> Linux版には既に実測済みの証跡([検証証跡台帳](../evidence/README.md)参照)へのリンクがありますが、本書(AD版)には**現時点で1件もありません**。本パックはまだ設計・手順書の整備段階であり、`ad-dc01`に相当する実ホストの構築そのものが行われていないためです。したがってAUT / AIT / AST / ANWのいずれのIDについても、結果欄は`NOT RUN`が唯一の正しい値です。これは「Linux版・Windows版より試験項目が緩い」ことを意味せず、単に「この構築案件がまだ実施段階に入っていない」ことを示しています。
>
> ### フェーズ2のIDはBLOCKEDが前提です
>
> フェーズ2(中央監視統合)に属する **AIT-09** は、[要件定義書](00-requirements.md)に記載した次の「未実装」3点が解消するまで、実行しても前提が揃わず`BLOCKED`になることが設計時点で分かっています。
>
> 1. `ansible/roles`配下にWindows対応role(`common_windows`等)が無く、Ansibleでの自動構築ができない
> 2. `compose.yaml`の`monitoring`ネットワークが`internal: true`のため、Prometheusコンテナが同じDockerホスト外にある実machine(`ad-dc01`)のwindows_exporter(既定9182/tcp)へ到達できない
> 3. Windows Event Log / ADディレクトリサービス監査ログを既存Lokiへ送る経路(Grafana Alloy for Windowsの導入、Lokiのpush APIをloopback以外からも安全に受け付けるための認証・network設計)が無い
>
> `BLOCKED`は失敗ではなく、前提条件と解除条件を記録した状態です。ただし本書は実行そのものをしていない空白の原本なので、結果欄はここでもなお`NOT RUN`のままにし、実際に実行して`BLOCKED`と確定した時点で日付付きの証跡へ理由とともに記入します。期待結果欄には、どの未実装点が解除条件になるかをあらかじめ書き添えています。
>
> ### この原本を埋めるには
>
> `ad-dc01`に相当する検証用ホストを1台用意し([立ち上げ環境の選択肢](10-host-bringup-and-acceptance.md)参照)、[構築手順書](05-build-procedure.md)に沿ってフェーズ1を実施したうえで、本書の表と同じ試験IDに対応する結果を記入します。記入した結果はこの原本を直接上書きせず、日付付きの証跡ファイル(例: `docs/evidence/YYYY-MM-DD-ad-build-validation.md`)へコピーして保存します。命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせます。
>
> ネットワーク実機検証(ANW-01〜09)の記入様式は[結果票テンプレート](../evidence/templates/network-host-validation-ad.md)を使います。手順の詳細は[ネットワーク実機検証手順](09-network-validation-procedure.md)を正本とします。

## 記録情報

| 項目 | 値 |
| --- | --- |
| 実施日時 | `NOT RUN` |
| 実施者 | `NOT RUN` |
| 環境 | `NOT RUN` |
| ホストのビルド番号(`winver` または `Get-ComputerInfo` の `OsBuildNumber`) | `NOT SET` |
| windows_exporter バージョン / SHA256 | `NOT SET` |
| PowerShell バージョン(組込5.1 / 追加導入7.4系) | `NOT SET` |

結果は `PASS / FAIL / BLOCKED / NOT RUN` のいずれかを記入します。初期値の `NOT RUN` は成功実績ではありません。

| 判定 | 意味 |
| --- | --- |
| `PASS` | 期待結果を実出力で確認し証跡への参照がある |
| `FAIL` | 実行したが一致しない |
| `BLOCKED` | 前提不足で実行できず理由と解除条件がある |
| `NOT RUN` | 未実行、成功実績として数えない |

設計値と実績値は必ず分けて記録し、未実施の実績値は `NOT SET` / `NOT RUN` / `NOT READY` のいずれかを使います。安易に `PASS` へ書き換えないでください。

## 単体・設定確認

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| AUT-01 | PowerShellスクリプト構文チェック | `Invoke-ScriptAnalyzer`(PSScriptAnalyzer)または構文parse | exit 0 / エラー無し | NOT RUN | — |
| AUT-02 | DSRMパスワード強度の設計確認 | [要件定義書](00-requirements.md)NFR-07相当の強度基準と手順書の記載を突合(値そのものは記載・確認しない) | 強度基準を満たす設計になっている | NOT RUN | — |
| AUT-03 | 文書間整合性レビュー | ドメイン名・NetBIOS名・IP・ポート番号・OU/GPO名が00〜04で一致しているかを目視レビュー | 不一致がない | NOT RUN | — |
| AUT-04 | 成果物リンク | `pytest tests/test_portfolio_artifacts.py -k internal_markdown_links` | README / docsの相対リンクがすべてリポジトリ内で解決 | NOT RUN | — |

## 構築・結合試験

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| AIT-01 | 新規フォレスト作成・初回DC昇格 | `Install-ADDSForest`の実行 | エラーなく完了し自動再起動後にログオンできる | NOT RUN | — |
| AIT-02 | 昇格後必須サービス確認 | `Get-Service NTDS,DNS,Netlogon,Kdc,W32Time` | すべてRunning | NOT RUN | — |
| AIT-03 | AD統合DNSゾーンでの名前解決 | `Resolve-DnsName`でAレコードとSRVレコード(`_ldap._tcp.dc._msdcs.corp.example.test`等)を確認 | 設計どおり解決する | NOT RUN | — |
| AIT-04 | OU/既定ドメインGPOのパスワードポリシー適用確認 | `Get-ADDefaultDomainPasswordPolicy`の確認、ポリシー未満の弱いパスワードでの`New-ADUser`が拒否されることを確認 | 設計値と一致し、弱いパスワードは拒否される | NOT RUN | — |
| AIT-05 | FSMO確認 | `netdom query fsmo` | 5役割すべて`ad-dc01` | NOT RUN | — |
| AIT-06 | System Stateバックアップ取得 | `wbadmin start systemstatebackup` | 正常終了、`wbadmin get versions`に記録される | NOT RUN | — |
| AIT-07 | ADごみ箱によるオブジェクト復元 | 検証用OUまたはユーザーを`Remove-ADObject`で削除し、`Get-ADObject -IncludeDeletedObjects`で検出後`Restore-ADObject`で復元 | 削除前と同じ属性で復元される | NOT RUN | — |
| AIT-08 | サービス停止復旧演習 | NTDSまたはDNSサービスを一時停止し検知・復旧・正常化までの時間を記録 | 復旧しRTOが記録される | NOT RUN | — |
| AIT-09 | host/ADメトリクスscrape(フェーズ2) | 中央PrometheusのTargets画面を確認 | `up{job="linux-node", host="ad-dc01"}=1`。ただし`compose.yaml`の`monitoring` networkが`internal:true`のため現状BLOCKED | NOT RUN | — |
| AIT-10 | 実ホストnetwork | ANW-01からANW-09を実行 | 設計どおり | NOT RUN | — |
| AIT-11 | 再実行安全性 | 既に昇格済みの`ad-dc01`に対して`Install-ADDSForest`相当を誤って再実行する | 既存ドメインを破壊せず、明確なエラーで安全に失敗する | NOT RUN | — |

## セキュリティ試験

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| AST-01 | WinRM listener確認 | `winrm enumerate winrm/config/listener` | HTTPSのみ、Basic無効 | NOT RUN | — |
| AST-02 | RDP状態確認 | `Get-NetFirewallRule -DisplayGroup "リモート デスクトップ"` | 既定Disable | NOT RUN | — |
| AST-03 | パスワードポリシー確認 | `Get-ADDefaultDomainPasswordPolicy` | 設計値(最小長14、複雑性有効、最長90日、履歴24世代、ロックアウト10回/観察10分/ロックアウト10分)と一致 | NOT RUN | — |
| AST-04 | LDAP署名/チャネルバインディング確認 | `HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters`の`LDAPServerIntegrity`と`LdapEnforceChannelBinding`を確認 | いずれも2(必須)に設定されている | NOT RUN | — |
| AST-05 | SMBv1無効確認 | `Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol` | State: Disabled | NOT RUN | — |
| AST-06 | 監査ポリシー確認 | `auditpol /get /subcategory:"ディレクトリ サービスの変更"` | 成功と失敗の両方が監査対象 | NOT RUN | — |
| AST-07 | 特権グループメンバー最小化確認 | `Get-ADGroupMember "Domain Admins"` | 想定外のメンバーがいない | NOT RUN | — |
| AST-08 | Firewall許可範囲確認 | `Get-NetFirewallRule` | Enabled=trueのルールで、AD DS関連グループのスコープが内部ネットワークCIDR、WinRM/windows_exporterのスコープが設計どおり | NOT RUN | — |

## ネットワーク実機検証

[Linux版パック](../build-package/09-network-validation-procedure.md)のNW-01〜09、[Windows版パック](../build-package-windows/06-test-specification.md)のWNW-01〜09に対応するAD版のIDです。詳しい手順は[ネットワーク実機検証手順](09-network-validation-procedure.md)を正本とし、本書はID・操作・期待結果の一覧だけを保持します。

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| ANW-01 | interface / IP / CIDR | `Get-NetAdapter`, `Get-NetIPAddress` | 設計値と一致 | NOT RUN | — |
| ANW-02 | route / gateway | `Get-NetRoute`, `Test-NetConnection -TraceRoute` | 想定gateway/interface/経路 | NOT RUN | — |
| ANW-03 | DNS(通常レコード+SRVレコード) | `Resolve-DnsName`(Aレコード、`_ldap._tcp.dc._msdcs`等のSRVレコード) | 想定レコードと一致 | NOT RUN | — |
| ANW-04 | ICMP | `Test-Connection` | 方針どおりの疎通または遮断 | NOT RUN | — |
| ANW-05 | 待受port | `Get-NetTCPConnection -State Listen` | 53,88,135,389,445,464,636,3268,3269,5986,9182が設計どおり待受、3389は既定Disableで非待受 | NOT RUN | — |
| ANW-06 | TCP/LDAP到達性 | `Test-NetConnection -Port 389/88/53/5986`等 | 内部ネットワークCIDR内は到達、windows_exporterは中央Prometheus host以外から拒否 | NOT RUN | — |
| ANW-07 | packet capture | `pktmon`(ヘッダのみ) | request/responseの経路を説明可能、本文は非採録 | NOT RUN | — |
| ANW-08 | Windows Defender Firewall | `Get-NetFirewallProfile`, `Get-NetFirewallRule` | プロファイル・AD DS自動生成ルールグループのスコープが設計と一致 | NOT RUN | — |
| ANW-09 | end-to-end | 管理元CIDR外からのWinRM接続試行 | 管理元CIDR以外からの接続が拒否される。内部ネットワークCIDRは実際に参加するホストが無いため、範囲設計の妥当性確認にとどまる旨を明記 | NOT RUN | — |

## 終了判定

- フェーズ1必須ID: AUT-01〜04、AIT-01〜08、AIT-10、AIT-11、AST-01〜08、ANW-01〜09(合計31 ID)
- フェーズ2必須ID(未実装3点解消後に必須化): AIT-09
- フェーズ1の必須IDに`FAIL`または`BLOCKED`が1件でもあれば、フェーズ1(ホスト単体構築)は完了としません。
- フェーズ1の必須IDに`NOT RUN`が残る場合も、フェーズ1は完了としません。
- フェーズ2はAIT-09が`BLOCKED`のままであること自体はフェーズ1の完了判定を妨げません。未実装3点(Windows対応Ansible role、`compose.yaml`の`monitoring` networkの外部到達、Windows Event Log / AD監査ログをLokiへ送る経路)が解消するまで`BLOCKED`であることを前提とします。
- 未実装3点の解消後もAIT-09が`NOT RUN`のまま残る場合は、フェーズ2(中央監視統合)は完了としません。
- 構築案件全体の完了は、フェーズ1必須試験がすべて`PASS`し、かつフェーズ2が未実装3点の解消条件とともに`BLOCKED`として明記されている状態を指します。両方が揃って初めて[作業結果・引き渡し報告書](11-work-result-report.md)へ記載できます。
- 結果はこの原本を直接上書きせず、日付付きの証跡ファイルへコピーして保存します。命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせます。
