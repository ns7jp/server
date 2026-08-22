# 新規 Ubuntu ホストの一気通貫 E2E 検証

## 目的

個別 role のテストだけでなく、使い捨て Ubuntu 24.04 GitHub-hosted runnerへ
`site.yml` を通して構築し、冪等性、runtime、network、障害復旧、backup restore を
一つの run で確認します。

runner imageにはDockerなど一部toolが事前導入されています。`environment-before-site.txt`に
Dockerの事前有無を、`environment-after-site.txt`に適用後versionを残します。そのため、
Actions runはDocker roleの収束と設定を検証しますが「Docker未導入の最小OSからinstallした」
証跡とは表現しません。Docker未導入hostでは下記の手動実行で同じscriptを使用できます。

[Full-stack Ansible E2E](../.github/workflows/full-stack-e2e.yml) は、次を順に実行します。

1. `site.yml` を新しい GitHub-hosted runner へ適用し、exit 0 を確認する
2. 同じ `site.yml` を再適用し、play recap の `changed=0 / failed=0` を確認する
3. core 9 services、health/readiness、Prometheus target、UI/metrics 認証を確認する
4. synthetic alert を Alertmanager へ送り、ローカル webhook sink の
   `FIRING / RESOLVED` 受信を確認する
5. app process を予期しない形で終了し、自動再起動と RTO を計測する
6. 3 volumes を一時停止中にbackupし、SHA256を検査して別名 volumesへ復元する
7. NIC、route、DNS、ICMP、listen、tcpdump、UFWを採録し、別Docker namespaceから
   管理portへ直接届かず、SSH tunnel経由なら届くことを確認する
8. raw logと判定表をActions artifactとして30日保存し、E2E成功後は実terminal castも追加する

## 検証済みrun

| 実施日 | commit | 結果 | Actions / artifact | 日付付き証跡 |
| --- | --- | --- | --- | --- |
| 2026-08-22 | `f4ea31993d6d5e3b8478789f8f0d008ed5f44961` | **23/23 ID PASS** | [run 32563104045](https://github.com/ns7jp/server-monitor/actions/runs/32563104045) / `full-stack-e2e-32563104045-1` | [環境・判定表・境界](evidence/2026-08-22-full-stack-e2e.md) |

artifactは2026-09-21に期限切れとなるため、判定表、version、RTO、restore結果、
terminal castのhashを日付付き証跡にも転記しています。

## 実行方法

GitHub の `Actions` → `Full-stack Ansible E2E` → `Run workflow` を実行します。
main で対象ファイルが変わった場合と、毎月1日にも自動実行されます。

成功・失敗にかかわらず、run の `Artifacts` から
`full-stack-e2e-<run id>-<attempt>` を取得します。重要なファイルは次のとおりです。

| ファイル | 意味 |
| --- | --- |
| `summary.md` | 各IDの `PASS / FAIL / NOT RUN` と検証範囲 |
| `results.tsv` | 機械可読な判定表 |
| `ansible-first.log` | 新規一括適用のraw log |
| `ansible-second.log` | 2回目の冪等性判定元 |
| `network-*.txt` | NIC / route / DNS / listen / packet / UFW |
| `alert-webhook-events.json` | secretを含まないローカル通知受信結果 |
| `d1-process-down.log` | 障害注入とRTO |
| `backup-restore.log` | checksum検証と別volume復元 |
| `demo.cast` | E2E成功後のstackでdemo stepも成功した場合に生成する実terminal cast |

`summary.md` はスクリプト開始時に全項目を `NOT RUN` で初期化し、対応コマンドが
成功した項目だけを `PASS` にします。workflowやスクリプトが存在するだけでは
実績として数えません。

## ローカルの使い捨てVMで実行する

Ubuntu 22.04 / 24.04 の専用VMで、Ansibleとcollectionを準備して実行します。

```bash
python3 -m pip install 'ansible>=11,<12'
ansible-galaxy collection install -r ansible/requirements.yml
bash scripts/e2e/run-full-stack.sh \
  --confirm-disposable-host \
  --evidence-dir "$PWD/.artifacts/full-stack-e2e/manual"
```

このスクリプトは package、sshd、UFW、Docker、systemd、`/opt/server-monitor` を
実際に変更します。普段使うPC、既存server、production hostでは実行しません。

## 証跡の境界

- E2Eの通知先はCI専用ローカルwebhookであり、Slack実配信の証跡ではありません。
- GitHub-hosted runnerは毎回破棄されるため、長期運用、再起動後の永続性、cloud側の
  security group/NACL、実production trafficは対象外です。
- `IT-12` はrunnerと別Docker namespaceを使ったVM内/境界検証です。実際の管理端末、
  組織DNS、security groupを含む検証は
  [network実機検証手順](build-package/09-network-validation-procedure.md)で別途採録します。
- [公開中の証跡リプレイ](https://ns7jp.github.io/demo.html)は保存済みscreen shot/logの再構成です。
  実操作の連続録画とは区別し、後者は実際に収録・公開するまで「未公開」です。

## backup / restore の安全策

backup scriptは対象3 servicesを短時間停止し、失敗時もtrapで再開します。archiveは
一時directoryで作り、`SHA256SUMS`生成後に完成directoryへrenameします。

復元は [restore-volumes.sh](../scripts/ops/restore-volumes.sh) が既存volumeを既定で拒否し、
E2Eでは新しいproject名へ復元してmarkerを照合します。`--force` は停止済みの復旧対象を
明示的に置換するときだけ使用します。
