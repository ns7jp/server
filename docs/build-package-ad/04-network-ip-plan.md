# ネットワーク設計・IPアドレス表

> 💡 **初めて読む方へ**: この文書はどのIP・ポートに、誰が、どこから接続できるかを決めた文書です。案件パック全体の地図は[初心者ガイド](beginner-guide.md#04-ネットワーク設計ipアドレス表)を参照してください。

## 1. 本体構成

`ad-dc01`はディレクトリ(NTDS)、DNS、認証(Kerberos)、グループポリシー配布(SYSVOL/NETLOGON共有)を1台で兼ねます。[Linux版](../build-package/04-network-ip-plan.md)・[Windows版](../build-package-windows/04-network-ip-plan.md)の管理UIが「管理元CIDRまたはloopbackだけに絞る」設計だったのに対し、AD DS自体のポートは性質が異なります。ドメインに参加する予定のすべてのホストから到達できる必要があるため、「管理元CIDR」より広い「内部ネットワークCIDR」という区分を新たに設けます。この違いを理解することが、本パックで最初に押さえるべきネットワーク設計上のポイントです。

| Zone | CIDR / interface | 主な通信 | 制御 |
| --- | --- | --- | --- |
| 管理端末 | 組織で割り当て(例示: `192.0.2.40`) | WinRM(HTTPS)、一時RDP | 管理元CIDR限定 |
| 内部ネットワーク(将来のドメインメンバー) | 環境で割り当て | DNS、Kerberos、LDAP、SMB(SYSVOL/NETLOGON)、動的RPC | 内部ネットワークCIDR限定。本パックでは実際に参加するホストが無いため、範囲の設計のみ |
| `ad-dc01` | 環境で割り当て(例示: `192.0.2.50/24`) | 上記すべての受信、外部NTP・windows_exporter scrapeの送信 | Windows Defender Firewall、Default Inbound Block |
| loopback | `127.0.0.1/8` | 自ホストでのDNS参照、windows_exporterのローカル確認 | ローカルのみ |

## 2. 「管理元CIDR」と「内部ネットワークCIDR」の違い

| 区分 | 対象ポート | 想定する接続元 | 例示 |
| --- | --- | --- | --- |
| 管理元CIDR | `5986/tcp`(WinRM)、`3389/tcp`(RDP、既定Disable) | 運用担当者が使う管理端末のみ、少数 | `192.0.2.40/32` |
| 内部ネットワークCIDR | `53`、`88`、`123`、`135`、`389`、`445`、`464`、`636`、`3268`、`3269`、`49152-65535` | 将来ドメインに参加するすべてのサーバー・クライアント | 環境ごとに決定(`NOT SET`) |
| 中央Prometheus hostのIP | `9182/tcp`(windows_exporter) | 中央監視host(`monitor-01`)のみ | [Linux版パラメータシート](../build-package/03-parameter-sheet.md)参照 |

管理元CIDRを内部ネットワークCIDRとして誤って広く設定すると、WinRM/RDPが不要に多くのホストへ公開されます。逆に内部ネットワークCIDRを管理元CIDRのように狭く設定すると、正当なドメインメンバーがログオンやポリシー適用に失敗します。この2つを混同しないことが、AD DSのFirewall設計で最初につまずきやすい点です。

## 3. Windows Defender Firewallの自動生成ルール

Windows Defender Firewallは、AD DS役割を`Install-ADDSForest`で有効化すると、次のルールグループを自動的に作成します。手動で個々のポートルールを1つずつ作る必要はなく、作業の中心は「自動生成されたルールグループのスコープ(許可送信元)を、内部ネットワークCIDRへ正しく絞ること」です。

| ルールグループ(英語版 / 日本語版の表示名) | 主なポート |
| --- | --- |
| Active Directory Domain Services / 同じ | LDAP(389)、LDAPS(636)、Global Catalog(3268/3269)、RPC(135、動的RPC) |
| DNS Service / DNS サービス | DNS(53) |
| Kerberos Key Distribution Center / Kerberos キー配布センター | Kerberos(88)、Kerberosパスワード変更(464) |
| File Replication / ファイル レプリケーション、DFS レプリケーション | SMB(445)、RPC |
| (本パック独自)`WinRM-HTTPS-MgmtOnly` | WinRM(HTTPS 5986)。既定の`Windows Remote Management`/`Windows リモート管理`グループはHTTP 5985用で使わず、[構築手順書](05-build-procedure.md)3節で専用ルールを作る |

ルールグループの`DisplayGroup`はOSの表示言語で決まり、`Get-NetFirewallRule -DisplayGroup`に他言語の名前を渡すと`ObjectNotFound`になります。手順書・検証手順はこの表を前提に、実機で`Get-NetFirewallRule | Select-Object -ExpandProperty DisplayGroup -Unique`を実行して名前を確認してから進めます(2026-09-01の日本語版実機で確認)。

自動生成ルールの既定プロファイルはDomain/Private/Publicで有効ですが、DCは昇格直後、ネットワークカテゴリがNLA(Network Location Awareness)によって正しく`Domain`と認識されるまで一時的に`Public`扱いになることがあります。[構築手順書](05-build-procedure.md)ではこの点を踏まえ、昇格直後にネットワークカテゴリを確認する手順を含めます。

上表のLDAPS(636)・Global Catalog LDAPS(3269)は、Firewallの許可範囲としては`Install-ADDSForest`実行時に自動生成されます。実際に待受するかどうかは、`Cert:\LocalMachine\My`にDCのFQDNをSubjectに持つサーバー認証用証明書があるかで決まります。AD CS(証明書サービス)は本パックの対象外ですが、[構築手順書](05-build-procedure.md)3節でWinRM HTTPS用に作る自己署名証明書がこの条件を満たすため、実機では636・3269も待受しました(2026-09-01確認)。理由の詳細は[パラメータシート](03-parameter-sheet.md)「公開ポート」節を参照してください。

## 4. 実環境で確認する項目

実行順、期待結果、採録方法は[ネットワーク実機検証手順](09-network-validation-procedure.md)を正本とします。

- `Get-NetIPAddress`でinterfaceとCIDRを確認
- `Get-NetRoute`でdefault gatewayと経路を確認
- `Get-NetTCPConnection -State Listen`で待受addressとportを確認
- `Resolve-DnsName`でAレコード・SRVレコード(`_ldap._tcp.dc._msdcs.corp.example.test`等)の名前解決を確認
- `Test-NetConnection`でLDAP(389)・Kerberos(88)・DNS(53)・WinRM(5986)への到達性を確認
- `pktmon`で必要時だけpacketを確認(ヘッダのみ、認証情報を含む本文は採録しない)
- Windows Defender Firewallの許可範囲(自動生成ルールグループのスコープ)がこの文書の設計と一致することを確認

`ad-dc01`単体では、実際にドメインへ参加するホストが無いため、内部ネットワークCIDRからの実接続(認証・GPO適用・SYSVOL参照)そのものはこの構築案件の範囲では確認できません。[基本設計書](01-basic-design.md)2.4節に記す「monitor-win-01のドメイン参加」のような発展構成を実施して初めて、内部ネットワークCIDR設計の実効性を確認できます。この境界を、埋まったことにしないでください。

独立した引き渡し対象host/管理端末の結果は、[結果票テンプレート](../evidence/templates/network-host-validation-ad.md)から日付付きevidenceを作成するまで`NOT RUN`です。
