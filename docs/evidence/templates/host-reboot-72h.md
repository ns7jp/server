# 永続ホスト再起動・72時間確認 記録テンプレート

このテンプレートを `docs/evidence/YYYY-MM-DD-host-reboot-72h.md` へコピーし、
**同じ永続Ubuntuホスト**を再起動直後、24時間後、72時間後に確認した実出力を記録します。
GitHub-hosted runner、同一セッション内のservice restart、予定だけの記入は代替になりません。

## 1. 実施情報

| 項目 | 記録 |
| --- | --- |
| 全体状態 | `NOT RUN` |
| 対象環境 / host | `NOT RUN` |
| 管理端末 | `NOT RUN` |
| commit SHA / revision marker | `NOT RUN` |
| OS / kernel | `NOT RUN` |
| 再起動前確認（JST） | `NOT RUN` |
| 再起動指示（JST） | `NOT RUN` |
| boot完了時刻 | `NOT RUN` |
| +24h確認（JST） | `NOT RUN` |
| +72h確認（JST） | `NOT RUN` |
| raw log / screenshot | `NOT RUN` |

公開証跡ではhost名、IP、ユーザー名、秘密値をマスクします。対象hostを再起動してよい
保守時間、接続復旧手段、判断者が決まるまで実行しません。

## 2. 事前条件

- [ ] 対象host、管理端末、適用commitを相互確認した
- [ ] consoleまたは別経路で復旧でき、SSHだけに依存していない
- [ ] `systemctl --failed`、Compose、主要endpoint、backupの事前状態が正常
- [ ] 進行中のbackup、変更作業、利用者trafficがない
- [ ] 再起動許可時刻、停止許容時間、エスカレーション先を記録した
- [ ] 24時間後・72時間後にも同じhostを確認できる

## 3. 各checkpointの確認

次の表は、出力を確認してから `PASS / FAIL / BLOCKED / NOT RUN` を記入します。

| Check | 再起動前 | 直後 | +24h | +72h | 期待値 |
| --- | --- | --- | --- | --- | --- |
| `uptime -s` / boot ID | NOT RUN | NOT RUN | NOT RUN | NOT RUN | 直後にbootが更新され、以後同一 |
| Docker / SSH active | NOT RUN | NOT RUN | NOT RUN | NOT RUN | active |
| `systemctl --failed` | NOT RUN | NOT RUN | NOT RUN | NOT RUN | failed unitなし |
| revision marker | NOT RUN | NOT RUN | NOT RUN | NOT RUN | 適用SHAと一致 |
| Compose全service | NOT RUN | NOT RUN | NOT RUN | NOT RUN | 必須serviceがrunning/healthy |
| `/healthz` / 認証 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | 200、未認証は401 |
| Prometheus target | NOT RUN | NOT RUN | NOT RUN | NOT RUN | `up{job="linux-node"}=1` |
| Grafana / Loki / Alertmanager | NOT RUN | NOT RUN | NOT RUN | NOT RUN | ready/healthy |
| backup timer / 最新archive | NOT RUN | NOT RUN | NOT RUN | NOT RUN | timer active、期限内backup |
| disk / memory /重大log | NOT RUN | NOT RUN | NOT RUN | NOT RUN | 閾値内、新規重大errorなし |

checkpointごとに、少なくとも次を時刻付きraw logへ保存します。

```bash
date --iso-8601=seconds
uptime -s
cat /proc/sys/kernel/random/boot_id
sudo systemctl is-active docker ssh
sudo systemctl --failed --no-pager
sudo cat /opt/server-monitor/.server-monitor-deploy-revision
sudo bash /opt/server-monitor/scripts/ops/daily-check.sh \
  --project-dir /opt/server-monitor
sudo systemctl status server-monitor-backup.timer --no-pager
sudo journalctl --since '-30 minutes' -p warning --no-pager
```

## 4. 時系列

| JST時刻 | 操作 / 観測 | 結果 | 証跡 |
| --- | --- | --- | --- |
| `NOT RUN` | 再起動前baseline | NOT RUN | — |
| `NOT RUN` | `sudo systemctl reboot` | NOT RUN | — |
| `NOT RUN` | 直後check | NOT RUN | — |
| `NOT RUN` | +24h check | NOT RUN | — |
| `NOT RUN` | +72h check | NOT RUN | — |

## 5. 終了判定

- [ ] 直後、+24h、+72hの全必須checkが `PASS`
- [ ] 同一host・同一boot・同一revisionを時刻付きで追跡できる
- [ ] 自動起動、監視、ログ、backupに継続異常がない
- [ ] FAIL/BLOCKEDと対応Issueを隠さず記録した
- [ ] 秘密値、公開IP、個人情報を公開証跡から除いた

一つでも未確認なら全体状態を `PASS` にしません。
