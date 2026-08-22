# Full-stack Ansible E2E 実測 — 2026-08-22

使い捨ての GitHub-hosted Ubuntu runner に `site.yml` を一括適用し、冪等性、
10 containers の稼働、認証、通知経路、障害復旧、backup / restore、network / UFWを
一つのrunで確認した記録です。artifactの保存期限後も判断根拠が残るよう、判定表を本書にも転記します。

## 実行情報

| 項目 | 値 |
| --- | --- |
| 結果 | **PASS** |
| 実施時刻 | 2026-08-22 17:45〜17:49 JST（08:45〜08:49 UTC） |
| Actions run | [Full-stack Ansible E2E run 32563104045 / attempt 1](https://github.com/ns7jp/server-monitor/actions/runs/32563104045) |
| event / branch | `push` / `codex/full-stack-e2e-20260822` |
| source / GitHub SHA | `f4ea31993d6d5e3b8478789f8f0d008ed5f44961`（両者一致） |
| artifact | `full-stack-e2e-32563104045-1` / ID `9473385349` / 21,023 bytes |
| artifact digest | `sha256:9c2c658cae23d1afa233f65637b616838f43d1e1507dec1cd76b0f8efaec013d` |
| artifact保存期限 | 2026-09-21 08:49:17 UTC（30日） |
| runner | image `ubuntu24-20260816.277.1` / Ubuntu 24.04.4 LTS / kernel `6.17.0-1022-azure` |
| tools | Python 3.12.14 / ansible-core 2.18.19 / Docker 28.0.4 / Compose v5.5.0 |
| Docker事前有無 | `docker_preinstalled=yes` |

Dockerはrunner imageに事前導入済みでした。このrunはDocker roleの設定収束とサービス再起動を
確認していますが、Docker未導入の最小OSからのpackage導入実績とは表現しません。

## 判定結果

artifactの`summary.md` / `results.tsv`では、対象23 IDがすべて`PASS`でした。

| ID | 結果 | 実測した内容 |
| --- | --- | --- |
| `ENV` | **PASS** | commit、OS、Ansible、Dockerの事前有無と適用後versionを採録 |
| `IT-01` | **PASS** | `site.yml`新規一括適用、`failed=0` |
| `IT-02` | **PASS** | 2回目の`site.yml`が`changed=0 / failed=0` |
| `STACK` | **PASS** | core 9 services + E2E webhook sink、計10 containersがrunning |
| `IT-03` | **PASS** | Prometheus APIで`up{job="linux-node"}=1` |
| `IT-04` | **PASS** | UIは認証なし401 / Basic認証あり200 |
| `IT-05` | **PASS** | metricsはtokenなし401 / Bearer tokenあり200、metric本文も確認 |
| `IT-08-local` | **PASS** | Alertmanagerからローカルwebhookへ`FIRING / RESOLVED`を配送 |
| `IT-09` | **PASS** | app processを`kill -9`後、自動再起動してhealthz復旧 |
| `IT-10` | **PASS** | 3 archivesのSHA256検証、別名3 volumesへ復元、marker一致 |
| `NW-01` | **PASS** | interface / IP / CIDR |
| `NW-02` | **PASS** | default route / gateway / route selection |
| `NW-03` | **PASS** | NSS resolverによる外部FQDN名前解決 |
| `NW-04` | **PASS** | loopback ICMP、packet loss 0% |
| `NW-05` | **PASS** | 管理5 ports + E2E sinkが`127.0.0.1`だけでlisten |
| `NW-06` | **PASS** | host loopback HTTP=200、別Docker namespaceからhost:8080へ直接到達不可 |
| `NW-07` | **PASS** | loopbackのTCP/8080 headerを`tcpdump`で2 packets採録 |
| `NW-08` | **PASS** | UFW active / incoming deny / SSH limit / 管理port allowなし |
| `NW-09` | **PASS** | 別namespaceからSSH tunnel経由でloopback HTTP=200 |
| `IT-12` | **PASS** | ephemeral VMと別Docker namespaceで`NW-01〜09`を完走 |
| `ST-01` | **PASS** | 管理portのwildcard bindなし |
| `ST-02` | **PASS** | running app containerの`Config.User=monitor` |
| `ST-04` | **PASS** | UFW policyとrulesを実ホスト出力で確認 |

`IT-08-local`はローカルwebhook sinkの検査名です。Slackへの実配信を示す`IT-08`へは
読み替えません。

## 復旧・restoreの測定値

- D-1: `2026-08-22T08:48:13Z`にapp processを停止し、1秒で復旧。
  `RestartCount`は`0 -> 1`、RTO目標300秒以内で`PASS`。
- demo stepでも別途D-1を実行し、1秒で復旧、`RestartCount`は`1 -> 2`。
- backup: `prometheus_data.tgz` / `grafana_data.tgz` / `loki_data.tgz`の
  `sha256sum --check`がすべて`OK`。
- restore: 既存volumeを上書きせず、別project名の3 volumesへ復元し、投入したmarkerが一致。

## 保存された一次資料

| ファイル | 判定に使った内容 |
| --- | --- |
| `summary.md` / `results.tsv` | PASS判定表と検証境界 |
| `ansible-first.log` / `ansible-second.log` | 新規適用と2回目`changed=0` |
| `compose-ps.txt` | 10 containersの状態とloopback port mapping |
| `network-*.txt` | interface / route / DNS / listen / tcpdump / UFW |
| `alert-webhook-events.json` | synthetic alertのFIRING / RESOLVED受信 |
| `d1-process-down.log` | 障害発生時刻、復旧時刻、RTO、restart count |
| `backup-restore.log` | 3 archivesのchecksumと別volumeへの復元 |
| `environment-*.txt` / `workflow-context.txt` | SHA、runner、OS、tool versions |
| `demo.cast` | 成功後stackで収録した実terminal session（3,243 bytes） |
| `demo-command-success.txt` | demo command完了時刻 `2026-08-22T08:49:17Z` |

`demo.cast`のSHA256は
`eee87a2edf2babf3cb92a57c90567ec32ba683f5ebf1db2ac83eeb0043863f79`です。
credential、token、webhook secretはartifactへ記録していません。

## 失敗からの修正記録

1. `internal: true`のnetworkだけに接続した公開対象serviceでは、native Linux host側の
   port forwardingが成立しなかった。内部通信用networkを維持し、公開対象だけを
   `host-access` bridgeにも接続して、`ports`は引き続き`127.0.0.1`へ限定した。
2. `synchronize`がcontroller側のowner/group/permsを再適用しないようにし、2回目の
   `site.yml`を`changed=0`へ収束させた。
3. CI専用backup設定をhost varsへ移し、`group_vars/monitor`の通常環境向け既定値より
   確実に優先させた。

途中run [32562858347](https://github.com/ns7jp/server-monitor/actions/runs/32562858347)では
`IT-02 changed=0`、runtime、通知、D-1まで進んだ後、backup保存先の変数優先順位不整合を検出しました。
その修正後のrun 32563104045で全項目が成功しています。

## この証跡に含まれないもの

- AlertmanagerからSlackへの実配信
- AWS `terraform apply / destroy`、Security Group / NACL、実費
- D-2（host障害からの復旧）
- 長期稼働、host再起動後の永続性、production traffic
- 実管理端末、組織DNS、別hostを含むproduction相当のnetwork検証
- 公開サイト上で再生できる連続操作動画（`demo.cast`は期限付きartifact内のterminal記録）

したがって、本書のPASSは「使い捨てGitHub-hosted runner内で自動実測した範囲」に限定します。
