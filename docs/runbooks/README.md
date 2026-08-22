# 運用ランブック索引

異常を検知した後に「何を確認し、どの条件で復旧・エスカレーションするか」をまとめた索引です。
runbookが存在すること自体は障害対応の実測証跡ではありません。実行時は
[一次切り分け記録テンプレート](../evidence/templates/troubleshooting-worklog.md)へ時刻・仮説・コマンド・出力を残します。

## 共通の実行前提

- 既定の配備先は`/opt/server-monitor`です。inventoryで変更した場合は実際の
  `server_monitor_install_dir`へ読み替えます。
- Composeコマンドは対象を取り違えないよう、先に`cd /opt/server-monitor`を実行します。
- application用`monitor`ユーザーはDocker groupに所属しません。Docker操作は承認済みsudo権限を持つ
  運用ユーザーから`sudo docker ...`で実行し、秘密値をshell historyや作業ログへ出しません。
- `ps` / `logs` / `stats` / `inspect`はread-only確認です。`restart` / `up` / `prune` / 設定変更は
  影響範囲とrollback条件を記録してから実行します。
- 構成を恒久的に収束させる操作はAnsibleの再適用を正本とします。緊急時にComposeで再作成する場合は
  `compose.yaml`の後へ`compose.ansible.yaml`を重ね、Slackを有効化した環境だけ
  `compose.slack.yaml.example`をその前に追加します。

```bash
cd /opt/server-monitor
sudo scripts/ops/daily-check.sh

# 恒久設定を再適用する場合（controller側）
cd ansible
ansible-playbook -i inventory/staging.local.yml playbooks/deploy.yml
```

## 症状別ランブック

| 症状 / alert | ランブック | 主な判断 |
| --- | --- | --- |
| app / Nginx停止、SLO burn | [service-down.md](service-down.md) | app、認証、upstream、host障害の切り分け |
| `/healthz` p95超過 | [latency-spike.md](latency-spike.md) | app / Nginx / CPU / memory / I/Oのどこが遅いか |
| filesystem 85%超過 | [disk-full.md](disk-full.md) | log、image、backup、metrics volumeの増加元 |
| memory 90%超過 | [memory-pressure.md](memory-pressure.md) | container別使用量、OOM、host process |
| Alertmanager / blackbox停止 | [alertmanager-down.md](alertmanager-down.md) | 通知経路・SLI計測自体の欠損 |

host停止から別hostへ戻すD-2は[設計・手順のみ](../roadmap/D-2-host-failure.md)で、実測は`NOT RUN`です。
D-1は[日付付き証跡](../drills/logs/2026-08-19-D-1.md)がありますが、個々のrunbookを
引き渡し対象hostで実施した証跡には読み替えません。

## 復旧完了とエスカレーション

復旧完了は「processが起動した」だけでなく、対象endpoint / Prometheus target / alert resolvedを
確認して判定します。次のいずれかなら、変更を重ねず状況を記録して上位担当へエスカレーションします。

- 原因と影響範囲を説明できない
- 操作がRTOを超える、またはデータ削除・秘密値変更・host再起動を要する
- 同じ異常が再発する
- rollback条件に到達した、または手順と実環境が一致しない
