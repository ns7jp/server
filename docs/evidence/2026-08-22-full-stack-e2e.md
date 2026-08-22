# Full-stack Ansible E2E 実測 — 2026-08-22

使い捨ての GitHub-hosted Ubuntu runner に `site.yml` を一括適用し、冪等性、
containersの稼働、認証、通知経路、障害復旧、backup / restore、network / UFWを
一つのrunで確認した記録です。初回feature runは10 containers、Docker API proxy追加後の
PR #75再検証は11 containersです。artifactの保存期限後も判断根拠が残るよう、判定表を本書にも転記します。

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

## main merge後の再検証

上記run 32563104045はfeature branchのcommit
`f4ea31993d6d5e3b8478789f8f0d008ed5f44961`に対する一次証跡です。PR #74をmergeした後、
`main`のmerge commit `43d36ee674f090108153b09451e825e3383494c1`（event=`push`）でも、
次の5 workflowが同日に`completed / success`となったことをGitHub Actionsで確認しました。

| workflow | main再検証run | 結果 |
| --- | --- | --- |
| Ansible check | [32566169563](https://github.com/ns7jp/server-monitor/actions/runs/32566169563) | **success** |
| Full-stack Ansible E2E | [32566169574](https://github.com/ns7jp/server-monitor/actions/runs/32566169574) | **success**（23 ID gate） |
| Security scan | [32566169577](https://github.com/ns7jp/server-monitor/actions/runs/32566169577) | **success** |
| Backup verify | [32566169582](https://github.com/ns7jp/server-monitor/actions/runs/32566169582) | **success**（任意のAWS snapshot age jobは設定なしのためskip） |
| Python check | [32566169583](https://github.com/ns7jp/server-monitor/actions/runs/32566169583) | **success** |

これはfeature runと同じ変更がmainへmergeされた状態の再検証です。feature runの実行環境、
artifact digest、個別判定値をmain runの値へ読み替えず、上の表はworkflow statusと対象SHAを
示す追補として扱います。また、commit `43d36ee...`より後の変更を検証した証跡でもありません。
AWS jobのskipをAWS実環境のPASSとして扱いません。

## PR #75 hardening後の再検証

Docker API proxy、`directory` modeのcontroller側immutable source配備、path・symlink・型検証などを追加した
PR #75のruntime変更最終commit `7622a9da974f694ae75e0173135923701be9e5a5`に対し、
pull request eventで再検証しました。

このrunは`inventory/ci.yml`から`directory` modeを使ったため、tracked archive / syncのruntimeを
示します。実hostで使う`git` modeのremote fetchから配備までのruntimeは`NOT RUN`であり、
inventory解決値と静的検査の結果をこのrunへ読み替えません。

| 項目 | 値 |
| --- | --- |
| 結果 | **23/23 ID PASS** |
| 実施時刻 | 2026-08-22 21:14〜21:17 JST（12:14〜12:17 UTC） |
| Actions run | [Full-stack Ansible E2E run 32572409469 / attempt 1](https://github.com/ns7jp/server-monitor/actions/runs/32572409469) |
| event / branch | `pull_request` / `codex/final-server-hardening-20260822` |
| source / GitHub SHA | `7622a9da974f694ae75e0173135923701be9e5a5`（runtime変更最終commit） |
| Ansible初回適用 | `changed=30 / failed=0` |
| Ansible2回目適用 | `changed=0 / failed=0` |
| runtime | core 10 services + E2E webhook sink、計11 containers |
| artifact | `full-stack-e2e-32572409469-1` / ID `9475706910` / 26,500 bytes |
| artifact digest | `sha256:11e3523cbf7a547c2762900b0d7d88006867e11d371d3c6283d6155eb3543900` |
| artifact保存期限 | 2026-09-21 12:17:40 UTC（30日） |

このrunでは従来の23 ID gateをすべてPASSし、追加したDocker API proxyについても、
read APIの成功、POST拒否、proxyが取得した固有Nginx logのAlloy経由Loki到達を確認しました。
D-1は1秒で復旧し、3 archivesのchecksum検証と別名3 volumesへのrestoreも成功しました。

同じcommitに対する5 workflowはすべて`completed / success`です。

| workflow | PR #75再検証run | 結果 |
| --- | --- | --- |
| Ansible check | [32572409470](https://github.com/ns7jp/server-monitor/actions/runs/32572409470) | **success** |
| Full-stack Ansible E2E | [32572409469](https://github.com/ns7jp/server-monitor/actions/runs/32572409469) | **success**（23/23 ID PASS） |
| Security scan | [32572409480](https://github.com/ns7jp/server-monitor/actions/runs/32572409480) | **success** |
| Backup verify | [32572409434](https://github.com/ns7jp/server-monitor/actions/runs/32572409434) | **success** |
| Python check | [32572409487](https://github.com/ns7jp/server-monitor/actions/runs/32572409487) | **success** |

PR上の先行runでは、実環境でのみ表面化した2点を検出して修正しました。

1. run [32571650745](https://github.com/ns7jp/server-monitor/actions/runs/32571650745)で、
   `ansible.builtin.assert`に対するtask-level `vars`のindent不整合を検出し、task直下へ修正した。
2. run [32571890175](https://github.com/ns7jp/server-monitor/actions/runs/32571890175)で、
   `become_user: monitor`が作成する`/opt/server-monitor/.ansible/tmp`をsource同期が削除し、
   2回目適用が`changed=1`になることを検出した。OpenSSL実行を`runuser`へ変更し、
   controller側sourceと配備先の収束を維持した。

この追補はruntime変更最終commitの実測です。後続の証跡文書だけを更新するcommitへruntimeの
PASSを読み替えず、実装が変わった場合は新しいFull-stack E2Eで再検証します。

## 判定結果（feature run 32563104045）

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

## 復旧・restoreの測定値（feature run 32563104045）

- D-1: `2026-08-22T08:48:13Z`にapp processを停止し、1秒で復旧。
  `RestartCount`は`0 -> 1`、RTO目標300秒以内で`PASS`。
- demo stepでも別途D-1を実行し、1秒で復旧、`RestartCount`は`1 -> 2`。
- backup: `prometheus_data.tgz` / `grafana_data.tgz` / `loki_data.tgz`の
  `sha256sum --check`がすべて`OK`。
- restore: 既存volumeを上書きせず、別project名の3 volumesへ復元し、投入したmarkerが一致。

## 保存された一次資料（feature run 32563104045）

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
- 構成commit / 設定を前版へ戻すrollback rehearsal（D-1 / volume restoreとは別）
- 長期稼働、host再起動後の永続性、production traffic
- 実管理端末、組織DNS、別hostを含むproduction相当のnetwork検証
- 公開サイト上で再生できる連続操作動画（`demo.cast`は期限付きartifact内のterminal記録）

したがって、本書のPASSは「使い捨てGitHub-hosted runner内で自動実測した範囲」に限定します。
