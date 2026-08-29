# 引き渡し対象ホストの立ち上げと受け入れ試験

> 💡 **初めて読む方へ**: この文書は「まだ確認していない項目」を、1台の実サーバーで一気に埋めるための手順書です。案件パック全体の地図は[初心者ガイド](beginner-guide.md#10-立ち上げと受け入れ試験)を参照してください。

これまでの実測はすべて **使い捨て CI runner** か **WSL2** の上だった。
そのため次の項目がまとめて `NOT RUN` のまま残っている。

- ホスト再起動後の永続性
- 24 時間 / 72 時間の連続稼働
- Alertmanager → Slack の実配信
- 実 DNS / 実 TLS 証明書
- インターネット越しの UFW / firewalld
- 30 日窓の SLO 達成率

**これらは 1 台の恒久ホストを用意すると大半が一度に埋まる。**
逆に、恒久ホストが無い限りどれも埋まらない。この文書はその 1 台を
「用意してから証跡が出るまで」を最短で通すための手順。

## 0. 何を用意するか

| 選択肢 | 目安費用 | 向き |
| --- | --- | --- |
| 国内 VPS（さくら / ConoHa / Xserver 等） | 月 500〜1,000 円 | **推奨。** 実 IP と実 DNS が付き、インターネット越しの firewall 検証ができる |
| 自宅 PC の VirtualBox / Hyper-V VM | 0 円 | 再起動・長期稼働は確認できるが、**実 IP / 実 DNS / インターネット越しの firewall は確認できない** |
| クラウド無料枠 | 0〜数百円 | 期限と課金に注意。Budgets を先に設定する |

最小構成の目安は 1 vCPU / メモリ 2GB / ディスク 20GB。
監視スタック 10 コンテナが動くので、メモリ 1GB では足りない。

OS は **Ubuntu 24.04 LTS** または **AlmaLinux 9 / Rocky Linux 9**。
どちらでも同じ `site.yml` が通る（[対応 OS](../../README.md#対応-os)）。
**国内案件は RHEL 系が多いので、余裕があれば AlmaLinux を選ぶと
未実測の穴を 1 つ多く埋められる。**

## 1. 立ち上げ前に決めておくこと

作業を始める前に、次を書き出しておく。あとから思い出せない。

| 項目 | 記入 |
| --- | --- |
| 対象ホスト（用途・OS・スペック） | |
| 管理元 IP / CIDR（自宅回線など） | |
| SSH 公開鍵 | |
| 再起動してよい時間帯 | |
| 接続不能になったときの復旧手段（コンソール） | |
| 停止許容時間 | |

**SSH だけに依存しない。** VPS のコンソール（シリアル / VNC）に
入れることを、firewall を触る前に必ず確認する。

## 2. 構築

[構築手順書](05-build-procedure.md) をそのまま実行する。
inventory に対象ホストの IP と、`git rev-parse HEAD` で得た 40 桁の
commit SHA を設定する。

```bash
cd ansible
cp inventory/staging.local.yml.example inventory/staging.local.yml
$EDITOR inventory/staging.local.yml     # 対象 IP / SSH user / commit SHA
# 秘密値は 05-build-procedure.md の手順で Vault に入れる

ansible-playbook -i inventory/staging.local.yml playbooks/site.yml --check --diff
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml
# 2 回目。changed=0 になることを確認する（IT-02）
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml
```

### 管理元 CIDR で SSH を絞る

リポジトリ既定の UFW は SSH を `limit`（レート制限）で開けるだけで、
**送信元は絞っていない**。実ホストではここを案件変数で絞る。

```yaml
# inventory/staging.local.yml
server_monitor_ssh_source_cidr: "203.0.113.10/32"   # 管理元のみ
```

RHEL 系なら firewalld の rich rule に、Debian 系なら UFW ルールに反映される。
**絞る前にコンソールで入れることを確認しておく。**

## 3. 受け入れ試験（1 コマンド）

対象ホスト上で実行すると、[試験仕様書](06-test-specification.md) の
試験 ID に対応した**記入済みの結果票**が生成される。

```bash
sudo /opt/server-monitor/scripts/ops/acceptance-check.sh
# -> docs/evidence/<日付>-host-acceptance.md
```

判定は script が期待値と実測値を比較した結果で、**手で PASS を書く余地がない**。
FAIL が 1 件でもあれば終了コードが 0 にならない。
host 名と IP は既定でマスクされる（公開証跡用）。

`SKIP` は「確認していない」であって「問題なし」ではない。
何が SKIP になったかを結果票で必ず読む。

## 4. 再起動後の永続性（IT / PS の残り）

**これが CI runner では絶対に確認できない項目。**

```bash
sudo /opt/server-monitor/scripts/ops/acceptance-check.sh --mode baseline
sudo systemctl reboot

# 再接続後
sudo /opt/server-monitor/scripts/ops/acceptance-check.sh --mode after-reboot
# -> docs/evidence/<日付>-host-reboot.md
```

`after-reboot` は boot ID を baseline と比較する。
**boot ID が変わっていなければ「そもそも再起動していない」と判定して FAIL にする。**
再起動したつもりで実は再起動していない、という誤った証跡を防ぐため。

## 5. 24 時間 / 72 時間の連続稼働

切断に耐える形で起動する。SSH が切れると止まる形では 24 時間もたない。

```bash
sudo systemd-run --unit=server-monitor-soak --collect \
  /opt/server-monitor/scripts/ops/acceptance-check.sh --mode soak --hours 24

# 経過を見る
journalctl -u server-monitor-soak -f
# -> docs/evidence/<日付>-host-soak-24h.md
```

サンプリング中に `healthz` が 200 でなかった回数と、意図しない再起動の
回数を数える。72 時間なら `--hours 72`。

## 6. 証跡の採録

生成されたファイルを**自分で読んでから**コミットする。

- [ ] FAIL の項目について、原因を理解している（理解できないまま採録しない）
- [ ] SKIP の項目が「未確認」であることを本文に残している
- [ ] host 名 / IP / 秘密値が出ていない（`--no-mask` を使っていない）
- [ ] [検証証跡台帳](../evidence/README.md) の該当行を `NOT RUN` から更新した
- [ ] [作業結果・引き渡し報告書](11-work-result-report.md)を日付付き evidence へ複製し、結果票の件数、差異、残存リスク、受領判定を記入した
- [ ] 06 の**原本は `NOT RUN` のまま**（上書きしない）

## 7. この手順で埋まらないもの

| 項目 | 追加で必要なもの |
| --- | --- |
| Alertmanager → Slack 実配信 | Slack webhook URL と `compose.slack.yaml` |
| 実 TLS 証明書 | 独自ドメインと Let's Encrypt（`nginx_letsencrypt_enabled: true`） |
| 組織 DNS / 上流 firewall | 実際の組織ネットワーク |
| D-2（別ホストへの復元） | 2 台目のホスト |
| AWS `apply` / 実費 | AWS アカウントと Budgets 設定 |
| 物理層（L1） | スイッチ、ケーブル、VLAN 対応機器 |

**1 台では埋まらないものを、埋まったことにしない。**
