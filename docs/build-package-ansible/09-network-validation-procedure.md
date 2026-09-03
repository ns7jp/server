# ネットワーク実機検証手順

> 💡 **初めて読む方へ**: この手順は実機のネットワークが設計どおりに動いているかを、名前解決→経路→待受→通信→firewallの順に確認するものです。他の案件パックと違い、本パックが確認する公開ポートはSSHの1つだけです。理由は[04-network-ip-plan.md](04-network-ip-plan.md#1-本体構成)を参照してください。

## 実施情報

| 項目 | 値 |
| --- | --- |
| 実施日 | `NOT SET` |
| 対象ホスト | `NOT SET` |
| 管理端末 | `NOT SET` |
| 適用commit SHA | `NOT SET` |

## AFNW-01 IP・interface確認

```bash
ip -br addr
```

期待結果: 対象interfaceのIPv4アドレスが、inventoryに設定した値と一致する。

## AFNW-02 経路確認

```bash
ip route
```

期待結果: default gatewayが設計値と一致し、管理端末への経路が存在する。

## AFNW-03 待受確認

```bash
ss -lntup
```

期待結果: `22/tcp`（SSH）以外の着信listenが無い。Docker導入後もこの結果が変わらないこと（[04-network-ip-plan.md](04-network-ip-plan.md#2-docker導入と公開ポートの関係)）を確認する。

## AFNW-04 SSH到達性

```bash
ssh -o BatchMode=yes -o PasswordAuthentication=no <admin_user>@<target_ip> echo ok
```

期待結果: `ok`が返る（鍵認証のみで到達できる）。`BatchMode=yes`はpasswordプロンプトが出た場合に即座に失敗させるオプションで、「鍵が無いと入れない」ことを機械的に確認するために使う。

## AFNW-05 firewall許可範囲

```bash
# Ubuntu
sudo ufw status verbose

# AlmaLinux / Rocky 9
sudo firewall-cmd --list-all
```

期待結果: 許可されている着信は`22/tcp`のみ。UFWは`LIMIT`（rate limit）であること、firewalldはrich ruleで`limit value="4/m"`が設定されていることを確認する。

## AFNW-06（任意）rate limitの発火確認

```bash
for i in $(seq 1 10); do ssh -o BatchMode=yes -o ConnectTimeout=2 <admin_user>@<target_ip> true; done
```

期待結果: 短時間に繰り返すと、途中から接続が拒否または遅延する（rate limitが機能している）。この試験は対象ホストへの負荷を伴うため、検証用ホストに限定して実施する。

## 障害時の切り分け順

| 順序 | 確認内容 | コマンド |
| --- | --- | --- |
| 1 | 名前解決・IP | `ip -br addr`、`getent hosts` |
| 2 | 経路 | `ip route`、`traceroute` |
| 3 | 待受 | `ss -lntup`（対象ホスト側） |
| 4 | 通信 | `ssh -v`（詳細ログでhandshakeの失敗箇所を特定） |
| 5 | firewall | `ufw status verbose` / `firewall-cmd --list-all` |

独立した引き渡し対象host/管理端末の結果は、日付付きevidenceを作成するまで`NOT RUN`です。
