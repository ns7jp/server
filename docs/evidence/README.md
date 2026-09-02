# 検証証跡台帳

このディレクトリは、設計資料や構成コードが存在することと、実環境で確認した結果を
混同しないための台帳である。実行していない検証を成功実績として記載しない。

## 要約（2026-08-27 更新）

2026-08-27、現行 `main` の `b97ccbc30b6c57cbf13bc283bdf0ffbbb4313083` を基点とする
作業ツリーで、[Windows ローカル静的・単体検証](2026-08-27-local-static-validation.md)を実施しました。
pytest、Python compile、tracked shell script 15 本の構文、dashboard JSON 2 件、YAML 100 件、
追跡 secret file の境界を確認しています。この作業ツリーは文書・test追加を含む **dirty tree** であり、
Linux / Docker / Ansible / Terraform runtime は `NOT RUN` です。過去の E2E を現行差分の実測へ読み替えません。

**Ansibleロール単体だけでなく、`site.yml`によるhost全体の新規構築・冪等性、
監視stack、認証、network/UFW、D-1、backup restore、使い捨てrunner上のGit-mode
構成commitロールバックまで実測証跡があります。**
[2026-08-22 Full-stack E2E](2026-08-22-full-stack-e2e.md)では、使い捨てUbuntu 24.04 runner上で
23 IDをすべてPASSとして採録しました（[Actions run 32563104045](https://github.com/ns7jp/server/actions/runs/32563104045)）。
PR #74のmain merge commit `43d36ee674f090108153b09451e825e3383494c1`でも5 workflowを再確認し、
さらにPR #75のruntime変更最終commit `7622a9da974f694ae75e0173135923701be9e5a5`では、
[Full-stack E2E run 32572409469](https://github.com/ns7jp/server/actions/runs/32572409469)を
含む5 workflowがすべてsuccessとなりました。後者ではDocker API proxyのGET成功・POST拒否・
Loki log到達、`directory` modeのtracked archive / sync、初回適用`changed=30 / failed=0`、2回目
`changed=0 / failed=0`まで実測しています。PR #75時点では`git` modeのremote fetchから配備までが
`NOT RUN`でしたが、2026-08-23の[run 32611251044](https://github.com/ns7jp/server/actions/runs/32611251044)で
候補SHAの配備から旧SHAへのrollbackを実測しました。commitごとの区別・境界は
[2026-08-22 E2E証跡](2026-08-22-full-stack-e2e.md#pr-75-hardening後の再検証)と
[Git-mode rollback証跡](2026-08-23-change-CI-GIT-ROLLBACK.md)に記録しています。

> **履歴（2026-08-21時点）:** 当時はAnsible各ロール、WSL2上の監視stack、D-1、
> 二セグメント障害ラボまでが実測済みで、`site.yml`一括構築（IT-01/02）、runner内
> network/UFW（IT-12）、backup restoreは未採録でした。この履歴を示す
> [2026-08-19結果票](2026-08-19-build-validation.md)は後から上書きしていません。

AlertmanagerからSlackへの実配信、D-2、AWS適用、永続hostの再起動・24h / 72h確認、
実管理端末・組織DNS・cloud firewallを含むproduction相当のnetwork検証は、現在も
`NOT RUN`です。

**AlmaLinux / Rocky 9 対応（role と Molecule scenario）、B-1〜B-4 の構築演習
（LVM、3 層構成、DB 復元、L2 / L3）を追加しました。**
B-1〜B-4 は 2026-08-24 に実行し、証跡を採録済みです（下表）。
ただし**実行環境は AI 支援セッションの作業環境**で、B-1 は qemu 上の Ubuntu 24.04
ゲスト、B-2 / B-3 は Docker コンテナ、B-4 は network namespace です。
**独立した物理／VPS ホストや、本人の手元 WSL2 での再実行証跡ではありません。**
各証跡ファイルの「実施環境」欄に、採録時の `uname` をそのまま残しています。

**監視サーバー1台がN台をscrapeする実演（IT-13）と、`storage-guard-test.sh`
安全装置negative test（ST-06）の実行証跡を追加しました。**
どちらも2026-08-25、`full-stack-e2e`のephemeral VM（GitHub-hosted runner、
device-mapperあり）上で実測しています
（[run 32816412328](https://github.com/ns7jp/server/actions/runs/32816412328)、
main `774d71c`）。IDは`06-test-specification.md`の公式番号体系とは別に、
`run-full-stack.sh`内で完結する固有IDです。

CI が検査しているのは構文と静的テストまでです（`python-check.yml` の `bash -n` と
pytest、`backup-verify.yml` の shellcheck 3 本）。**`labs/` と `scripts/labs/` には
shellcheck が掛かっておらず、安全装置の実行テストと B-1〜B-4 は CI では走りません。**

AlmaLinux 実機への `site.yml` 適用は `NOT RUN` です。

**Molecule `el9` シナリオは 2026-08-25 に実行証跡を採録しました**
（[run #14](https://github.com/ns7jp/server/actions/runs/32811100007)、
main `5480662`、common / docker role の el9 scenario ともに成功）。
初回実行（[run #9](https://github.com/ns7jp/server/actions/runs/32809471372)）
は 3 件の実欠陥に阻まれて失敗し、1 件ずつ実行して直しました。
[欠陥台帳](defects-found.md) に追加しています。実機の AlmaLinux / Rocky 9
ホストへの適用ではなく、コンテナ（`geerlingguy/docker-rockylinux9-ansible`）上の
検証です。

| 区分 | 状態 |
| --- | --- |
| 現行作業ツリーのローカル静的・単体検証 | ✅ [2026-08-27](2026-08-27-local-static-validation.md)：pytest 149件、compile、shell 15本、JSON 2件、YAML 100件、secret追跡境界をWindowsで確認。基点は`b97ccbc` + 未コミット差分。Linux runtimeは**NOT RUN** |
| CI による自動検証 | ✅ 継続的に実行中（構文・設定整合・依存脆弱性・秘密値混入・バックアップスクリプト） |
| 現行mainのMolecule / Backup再検証 | ✅ [2026-08-23](2026-08-23-current-main-ci-refresh.md)：4 roleとbackup archive smokeを`59aa88e`で再実行。AWS jobは設定なしでskip |
| Full-stack E2E | ✅ [2026-08-22](2026-08-22-full-stack-e2e.md)：新規構築、2回目`changed=0`、11 containers、認証、Docker API proxy、local通知、network/UFW、D-1、3-volume restoreを23/23 PASS |
| Ansible ロールの適用・冪等性・検証 | ✅ **4 ロール完走**（[2026-08-17](2026-08-17-molecule.md)、Ubuntu 22.04 コンテナ） |
| 監視スタック全体の起動（Grafana / Loki） | ✅ [2026-08-18](2026-08-18-local-observability.md)。local webhook通知は[2026-08-22 E2E](2026-08-22-full-stack-e2e.md)、Slack実配信は**NOT RUN** |
| D-1 復旧演習の実測 | ✅ [2026-08-19](../drills/logs/2026-08-19-D-1.md) RTO 13秒 / [2026-08-22 E2E](2026-08-22-full-stack-e2e.md) RTO 1秒。D-2は**NOT RUN** |
| 二セグメント障害ラボの実測 | ✅ [2026-08-19](2026-08-19-network-drill.md)（障害注入→切り分け→復旧、PASS） |
| ネットワーク切り分けの一次メモ | ✅ [2026-08-21](2026-08-21-network-firstlook.md)：公開port不成立を切り分け。2026-08-22に内部segmentを維持した`host-access`構成へ修正し、E2Eでloopback bind / namespace遮断 / SSH tunnelを確認 |
| ephemeral VM の network / UFW | ✅ [2026-08-22](2026-08-22-full-stack-e2e.md)：`NW-01〜09` / `IT-12` / `ST-01,04` PASS |
| 監視サーバー1台がN台をscrapeする実演 | ✅ [2026-08-25](https://github.com/ns7jp/server/actions/runs/32816412328)：`full-stack-e2e` の ephemeral VM 上で、2台目の node_exporter を実行時に internal network へ attach し、Prometheus が名前解決だけで `up=1` に切り替わることを `run-full-stack.sh` 内 ID `IT-13` として実測（main `774d71c`） |
| 独立した管理端末・対象hostでの network / UFW | ❌ **NOT RUN**（[手順](../build-package/09-network-validation-procedure.md)と[結果票テンプレート](templates/network-host-validation.md)のみ） |
| AD DC（`ad-dc01`）の構築・試験 AUT-01〜04 / AIT-01〜08,10,11 / AST-01〜08 | ✅ [2026-09-01〜02](2026-09-01-ad-build-validation.md)：フォレスト作成、OU/パスワードポリシー、System Stateバックアップ、ADごみ箱復元、サービス停止復旧(RTO 0.9秒)、再実行安全性、LDAP署名/SMBv1/監査/特権グループ/Firewall を実機で **22/22 PASS**。AIT-09(中央Prometheus scrape)は**BLOCKED**。AUT-01で手順書のコードブロック1件の構文誤りを発見し修正 |
| AD DC（`ad-dc01`）の作業結果・引き渡し報告 | ✅ [2026-09-02 SM-AD-001](2026-09-02-work-result-SM-AD-001.md)：計画対実績、試験集計 31/31 PASS + 1 BLOCKED、設計差異10項目、障害10件(LAB-01〜10)、残存リスク、引き渡し物、受領判定。ラボ範囲の引き渡しで、組織環境向けではない |
| AD DC（`ad-dc01`）の実機ネットワーク検証 ANW-01〜09 | ✅ [2026-09-01〜02](2026-09-01-network-host-validation-ad.md)：手元Hyper-V上のWindows Server 2022評価版VMと、ホストPCを管理端末として **9/9 PASS**。手順書の誤り4件（OU名衝突、pktmon構文、Firewallグループ名のロケール依存、`DefaultInboundAction`の表示）を実機で発見し同じPRで修正。LDAPS(636/3269)が設計と異なり待受した原因も特定。組織DNS・実ドメインメンバー・中央Prometheusからのscrapeは**NOT RUN** |
| AlmaLinux / Rocky 9 の Molecule `el9` シナリオ | ✅ [2026-08-25](https://github.com/ns7jp/server/actions/runs/32811100007)：common / docker 両 role の el9 scenario が成功。コンテナ上の検証で、実機ホストへの適用ではない |
| AlmaLinux / Rocky 9 実機への `site.yml` 適用 | ❌ **NOT RUN**（role は el9 コンテナで検証済み） |
| B-1 ディスク設計・LVM 拡張演習 | ✅ [2026-08-24](../drills/logs/2026-08-24-B-1.md)：**5 PASS / 0 FAIL**。初回適用・冪等性・ENOSPC 再現・PV 追加による online 拡張（220M→457M、mount 維持）を実測。安全装置テスト（`storage-guard-test.sh`、7 ケース）は[2026-08-25](https://github.com/ns7jp/server/actions/runs/32816412328)、`full-stack-e2e` の ephemeral VM（device-mapper あり）で `run-full-stack.sh` 内 ID `ST-06` として実行し PASS。証跡本体（`storage-guard-test.log` / `*-B-1-guard.md`）は当該 run の artifact に含まれる |
| B-2 3 層構成の障害切り分け演習 | ✅ [2026-08-24](../drills/logs/2026-08-24-B-2.md)：実コンテナ（Docker 29.3.1）で **9 PASS / 0 FAIL**。層分離の遮断、DB 停止・AP 停止・経路断の切り分けを実測 |
| B-3 DB バックアップ・復元演習 | ✅ [2026-08-24](../drills/logs/2026-08-24-B-3.md)：実 PostgreSQL 16 で **7 PASS / 0 FAIL**。RTO **0.149 秒** / RPO **2.344 秒**、内容ハッシュ一致まで実測 |
| B-4 L2 / L3 切り分け演習 | ✅ [2026-08-24](../drills/logs/2026-08-24-B-4.md)：**6 PASS / 0 FAIL / 3 SKIP-ENV**。静的ルート・戻り経路の欠落・`ip_forward` を実測。VLAN 部はこの kernel が `CONFIG_VLAN_8021Q` 無効のため未検証 |
| AWS `apply` / `destroy` と実費 | ❌ **NOT RUN** |
| 構成commit / 設定rollback rehearsal | ✅ [2026-08-23](2026-08-23-change-CI-GIT-ROLLBACK.md)：使い捨てUbuntu runnerでcandidate `84e1492`からmain `59aa88e`へGit-mode rollbackを実測。永続hostでは**NOT RUN** |
| 永続hostの再起動・24h / 72h確認 | ❌ **NOT RUN**（[`acceptance-check.sh`](../../scripts/ops/acceptance-check.sh) の `--mode after-reboot` / `--mode soak` で自動採録できる状態。手順は[10 立ち上げと受け入れ試験](../build-package/10-host-bringup-and-acceptance.md)） |
| 引き渡し対象hostの受け入れ試験 | ❌ **NOT RUN**（[`acceptance-check.sh`](../../scripts/ops/acceptance-check.sh) が試験IDに対応した結果票を生成する。対象host 1台があれば実行できる） |
| [試験仕様書](../build-package/06-test-specification.md)の2026-08-19結果 | ⚠ **日付付き履歴**: [11/21 PASS、残り NOT RUN](2026-08-19-build-validation.md)。現在のcoverageは下表で別管理 |

> **この証跡が示す範囲を広げて解釈しない。** 2026-08-22 E2Eと2026-08-23 Git-mode
> rollbackはGitHub-hosted runner内の自動実測です。独立した管理端末、複数host、組織DNS、
> D-2、Slack実配信、AWS適用、永続hostの再起動・24h / 72h確認の代替にはしません。

### 実機で B-1 を実行して見つかった欠陥（2026-08-24）

B-1 は device-mapper を持つ kernel が要る。この作業環境の kernel は
`CONFIG_BLK_DEV_DM` を持たないため、qemu で Ubuntu 24.04
（kernel 6.8.0-138-generic）を起動して実行した。**2 件の欠陥が出た。**
どちらも CI・`ansible-lint`・molecule・構文検査のいずれも捕まえていない。

| 欠陥 | 内容 |
| --- | --- |
| 対象 OS の既定 Ansible で play ごと失敗する | `meta: end_role` は ansible-core **2.18 以降**にしかない。Ubuntu 24.04 LTS が同梱するのは **2.16.3** で、`invalid meta action requested: end_role` になる。CI は pip で入れた 2.21.3 を使っていたため通っていた |
| 冪等でなかった | 1 回目の適用は完全に成功する（`ok=15 changed=5 failed=0`）。2 回目は **このロール自身が作った LV** を安全装置が子デバイスとして検出し、拒否する。`site.yml` を 2 回流せない |

2 件目は「子がいるなら通す」では安全装置の意味が無くなるため、`pvs` で
その PV が属する VG を読み、**宣言している VG のときだけ許す**形に直した。
partition や他人の VG の LV が載っているディスクは従来どおり拒否する。

修正後、同じ環境で **5 PASS / 0 FAIL** で完走し、冪等性の試験も
`changed=0` で通っている。

### B-4 を Docker の network から network namespace へ組み替えた（2026-08-24 実測）

当初は Docker の bridge network を 3 つ並べていたが、実行を試みて**成立しない**ことが分かった。

| 欠陥 | 内容 |
| --- | --- |
| 起動できない | router に各セグメントの `.1` を要求していたが、Docker は既定で bridge 自身へ `.1` を割り当てる。`Address already in use` になる。**この演習は一度も起動できていなかった** |
| 転送が落ちる | Docker は endpoint ごとに `iptables -t raw -A PREROUTING -d <IP> ! -i <その bridge> -j DROP` を入れる。別セグメントから router 宛に来たパケットは **FORWARD へ届く前に落ちる** |
| `ip_forward` を切り替えられない | コンテナ内の `/proc/sys` が read-only |

2 番目は切り分けの過程を実測で押さえた。host-a は送出しているのに router のキャプチャは 0 パケット、同一キャプチャ内で `.1` 宛だけは届く、iptables FORWARD の counter は `.1` 宛 4 pkts に対し別セグメント宛 **0 pkts**。該当 DROP を一時的に迂回すると疎通し、戻すと再び不通になった（規則は元に戻した）。環境固有の設定ではなく **Docker 自身の挙動**である。

そこで **bridge・veth・network namespace を自分で組む**形（[`labs/routing/topology.sh`](../../labs/routing/topology.sh)）へ変えた。Docker のネットワーク機能を一切使わないので上の 3 点はいずれも当てはまらず、「ネットワークを自分で組む」という演習の目的にも合う。必要な権限は privileged なコンテナ 1 台へ閉じてあり、後始末は `down` で済み、host 側には何も残らない。

VLAN 部（`B4-L2-02`〜`04`）だけは、この環境の kernel が `CONFIG_VLAN_8021Q is not set` でビルドされているため実行できない。モジュール読み込みでは解決しない kernel 設定レベルの制約なので、`SKIP-ENV`（未検証）として記録している。

### B-1 〜 B-4 について、何がどこまで確認できているか

2 つの別々の問いがあります。混ぜて読むと実態より広く見えます。

| 問い | 状態 |
| --- | --- |
| 演習の script 自体が、期待どおりの判定を出すか | **確認した** |
| 演習を実行し、その結果を証跡として持っているか | **持っている**（2026-08-24、上表） |
| その実行が、独立した物理／VPS ホスト上のものか | **違う**（AI 支援セッションの作業環境） |
| その実行が、本人の手元（WSL2）で再現されているか | **していない**（再実行を予定） |

1 つ目は、`docker` を差し替えたスタブに置き換えて script をそのまま通しで
実行し、**正常系だけでなく「壊れている」入力でも FAIL が出ること**まで
確かめています。演習が空振りで PASS しないことの検査です。

3 つ目・4 つ目が、この演習群の現在の限界です。証跡の「実施環境」欄
（B-2 / B-3 / B-4 は `Linux 6.18.44-fc-v21`）がそれを示しています。

これは実機の実行の代わりにはなりません。**スタブの応答は「実際の nginx /
PostgreSQL がこう返すはず」という想定**であり、確認できたのは script の
制御フローと判定ロジックまでです。

それでもこの検証には意味がありました。走らせて初めて次の欠陥が見つかり、
[#83](https://github.com/ns7jp/server/pull/83) 〜
[#86](https://github.com/ns7jp/server/pull/86) で修正しています。
`shellcheck` と構文チェックはいずれも通っていました。

| 見つかったもの | 影響 |
| --- | --- |
| 層分離の判定が `set -e` に巻き込まれる | **遮断できているときにだけ**演習が中断し、証跡が 1 行も残らない |
| `set +e` でも ERR trap が実行される | 完走しているのに「演習が途中で終了した」と出る |
| 実測欄が判定と無関係の固定文字列 | 「適用完了」なのに `FAIL` という行が証跡に残る |
| RTO / RPO を秒粒度で引き算 | 実測値が「0 秒」になり、測っていないのか壊れているのか読めない |
| 未検証を `FAIL` と表示 | 証跡は `SKIP-ENV` なのに、実行した人は「落ちた」と読む |
| `docker version` の 2 行出力 | 証跡の表がその行で崩れる |

## 試験IDと現在の証跡の対応

[試験仕様書](../build-package/06-test-specification.md)は未指定の引き渡し対象host向け原本なので、
初期値`NOT RUN`を上書きしません。次は、別の日付付き証跡がどの受入条件を確認したかの索引です。

| 試験ID | 現在の証跡 | 境界 |
| --- | --- | --- |
| UT-01、UT-06、ST-03 | [2026-08-27 Windowsローカル検証](2026-08-27-local-static-validation.md) | `b97ccbc`を基点とするdirty treeのPython / 成果物 / tracked secret検査。Linux runtimeやimmutable commitのCIではない |
| UT-01〜04、ST-03、ST-05 | [PR #75の5 workflow](2026-08-22-full-stack-e2e.md#pr-75-hardening後の再検証) | Python / Compose / monitoring config / Ansible / securityのCI。runtime試験の代替ではない |
| UT-05 | [2026-08-19 Terraform check](2026-08-19-ci-baseline.md) | 当時commitの`fmt / validate / static scan`。AWS applyではなく、PR #75 commitの再検証でもない |
| IT-01〜05、IT-09〜10、ST-01〜02、ST-04 | [2026-08-22 PR #75 E2E](2026-08-22-full-stack-e2e.md#pr-75-hardening後の再検証) | disposable Ubuntu runner内で実測 |
| IT-06 | [2026-08-18 WSL2実画面](2026-08-18-local-observability.md) | PR #75 E2EはGrafana API healthまで。PR #75上の対話UI再採録ではない |
| IT-07 | [PR #75 E2EのDocker log→Alloy→Loki gate](2026-08-22-full-stack-e2e.md#pr-75-hardening後の再検証) | `STACK` ID内で固有Nginx logのLogQL取得を実測。独立した`IT-07`結果IDではない |
| IT-08 | [2026-08-22 `IT-08-local`](2026-08-22-full-stack-e2e.md#判定結果feature-run-32563104045) | local webhookのFIRING / RESOLVEDのみ。Slack実配信は`NOT RUN` |
| IT-11 | [2026-08-19二セグメント障害ラボ](2026-08-19-network-drill.md) | Docker lab内の障害注入・切り分け・復旧 |
| IT-12 | [2026-08-22 `NW-01〜09`](2026-08-22-full-stack-e2e.md#判定結果feature-run-32563104045) | runner + 別Docker namespace。独立した引き渡し対象host / 管理端末は`NOT RUN` |

repository内で完結する構成commit / 設定rollback rehearsalは採録済みです。外部環境が
用意できた後は、Slack実配信、独立した対象host / 管理端末のnetwork検証、AWS短時間
`apply / destroy`、D-2、永続hostの再起動・24h / 72h確認をそれぞれ別証跡として採録します。

## 現在の証跡状態

| 対象 | リポジトリで確認できる成果物 | 実行証跡 |
| --- | --- | --- |
| アプリ/API の認証・マスキング | `tests/`、`python-check.yml` | CI 実行結果を PR で確認。[2026-08-19: 4 workflow の直近成功ログを台帳化](2026-08-19-ci-baseline.md) |
| ローカル Python / 成果物検査 | `tests/` | [2026-08-27: 149 tests PASS + 静的検査](2026-08-27-local-static-validation.md)。[2026-08-11: 14 tests PASS](2026-08-11-local-code-validation.md)は履歴 |
| Compose / Prometheus / Loki / Alloy 設定 | `compose.yaml`、`deploy/`、`python-check.yml` | [2026-08-18: Linux(WSL2)上での起動・Grafana実画面・Lokiログ検索を採録](2026-08-18-local-observability.md) |
| Ansible roles | `ansible/`、`ansible-check.yml` | 構文・lint 検証に加え、[2026-08-17: 4 ロールの `molecule test` 完走](2026-08-17-molecule.md)（create → converge → idempotence → verify）。[実行手順](molecule-via-github-actions.md) |
| Ansible full site E2E | `full-stack-e2e.yml`、`scripts/e2e/run-full-stack.sh` | [2026-08-22実測](2026-08-22-full-stack-e2e.md) / [実行・証跡採録手順](../e2e-validation.md) |
| Terraform AWS 構成 | `terraform/`、`terraform-check.yml` | `terraform plan/apply/destroy` と Cost Explorer 実測は**NOT RUN** |
| SLO / 復旧演習 | `docs/slo.md`、`docs/drills/`、`scripts/drills/` | D-1は[2026-08-19: RTO 13秒](../drills/logs/2026-08-19-D-1.md) / [2026-08-22 E2E: RTO 1秒](2026-08-22-full-stack-e2e.md)。D-2は**NOT RUN** |
| 外部 probe / 中央 telemetry | `docs/roadmap/external-probe-central-telemetry.md` | 外部 probe と中央保存先の実測は未収録 |
| 変更管理 | `.github/pull_request_template.md`、`.github/ISSUE_TEMPLATE/`、`docs/change-management.md` | PR ごとに検証・ロールバック・証跡リンクを残す |
| 構成commit / 設定rollback | `docs/build-package/08-change-rollback-plan.md`、`scripts/e2e/run-git-rollback-rehearsal.sh` | [2026-08-23 CI実測](2026-08-23-change-CI-GIT-ROLLBACK.md)は使い捨てrunnerで**PASS**。永続hostでは**NOT RUN**。D-1 / volume restoreの証跡を読み替えない |
| 構築工程成果物 | `docs/build-package/` | 設計・構築・試験様式を整備。実機結果は各検証ログへ記録 |
| 二セグメント障害ラボ | `labs/network-troubleshooting/` | [2026-08-19: 障害注入→切り分け→復旧を実測、PASS](2026-08-19-network-drill.md) |
| 独立した対象host/管理端末の NIC / DNS / route / listen / HTTP / packet / UFW | `docs/build-package/09-network-validation-procedure.md` | **NOT RUN**。ephemeral runner内のPASSは[別証跡](2026-08-22-full-stack-e2e.md)として区別 |

## 記録ルール

実行した検証は次の情報を残し、秘密値、アカウント ID、公開 IP はマスクする。

| 項目 | 必須内容 |
| --- | --- |
| 日時 | JST の実行日時 |
| 対象 | commit SHA、環境名、使用ツールのバージョン |
| コマンド | 再現できる実行コマンド |
| 結果 | PASS / FAIL、所要時間、主要ログまたはスクリーンショット |
| 費用 | AWS を使った場合のみ Cost Explorer の期間と実費 |
| 後続対応 | 見つかった課題の Issue / PR リンク |

## 予定する記録ファイル

| 検証 | 記録先 |
| --- | --- |
| D-1 プロセスダウン | `docs/drills/logs/YYYY-MM-DD-D-1.md` |
| D-2 AWS 復元 | `docs/drills/logs/YYYY-MM-DD-D-2.md` |
| AWS 短時間 apply/destroy | `docs/evidence/YYYY-MM-DD-aws-validation.md` |
| Grafana / Loki / Alertmanager ローカル採録 | `docs/evidence/YYYY-MM-DD-local-observability.md` |
| Alertmanager → Slack 実配信 | `docs/evidence/YYYY-MM-DD-slack-delivery.md` |
| Linux 新規構築・試験 | `docs/evidence/YYYY-MM-DD-build-validation.md` |
| ローカル静的・単体検証 | `docs/evidence/YYYY-MM-DD-local-static-validation.md` |
| 作業結果・引き渡し報告 | `docs/evidence/YYYY-MM-DD-work-result-<change-id>.md` |
| 永続host再起動・24h / 72h確認 | `docs/evidence/YYYY-MM-DD-host-reboot-72h.md` |
| 二セグメント通信障害 | `docs/evidence/YYYY-MM-DD-network-drill.md` |
| Linux 実ホスト network / UFW | `docs/evidence/YYYY-MM-DD-network-host-validation.md` |
| AD DC 実ホスト network / Firewall | `docs/evidence/YYYY-MM-DD-network-host-validation-ad.md` |
| 構成commit / 設定rollback rehearsal | `docs/evidence/YYYY-MM-DD-change-<ID>.md` |
| 仮説検証を含む一次切り分け | `docs/evidence/YYYY-MM-DD-troubleshooting-<slug>.md` |
| スクリーンショット | `docs/evidence/screenshots/<kind>_<commit>_<yyyymmdd>.png` |

## 採録テンプレート

| 用途 | テンプレート |
| --- | --- |
| ローカル Grafana / Loki / Alertmanager | [templates/local-observability.md](templates/local-observability.md) |
| Alertmanager → Slack 実配信 | [templates/slack-delivery.md](templates/slack-delivery.md) |
| 永続host再起動・24h / 72h確認 | [templates/host-reboot-72h.md](templates/host-reboot-72h.md) |
| AWS 短時間検証 | [templates/aws-validation.md](templates/aws-validation.md) |
| Molecule フル実行 | [templates/molecule.md](templates/molecule.md) |
| Linux 実ホスト network / UFW | [templates/network-host-validation.md](templates/network-host-validation.md) |
| AD DC 実ホスト network / Firewall | [templates/network-host-validation-ad.md](templates/network-host-validation-ad.md)（[記入済み例: 2026-09-01](2026-09-01-network-host-validation-ad.md)） |
| 仮説 → コマンド → 結果 → 学び | [templates/troubleshooting-worklog.md](templates/troubleshooting-worklog.md)（[記入例](templates/troubleshooting-worklog-example.md)あり） |
| 作業結果・引き渡し報告 | [../build-package/11-work-result-report.md](../build-package/11-work-result-report.md) |
| D-1 プロセスダウン | [../drills/logs/TEMPLATE-D-1-process-down.md](../drills/logs/TEMPLATE-D-1-process-down.md) |
| D-2 ホスト障害復旧 | [../drills/logs/TEMPLATE-D-2-host-failure.md](../drills/logs/TEMPLATE-D-2-host-failure.md) |

## 採録手順

**必要な環境が軽い順**に進める。

1. **[Full-stack Ansible E2Eを実行する](../e2e-validation.md)** — ブラウザのみ・使い捨てUbuntu runner。
   新規構築、冪等性、runtime/network、D-1、restoreを一つのartifactへまとめる。
2. **[Molecule を GitHub Actions で実行する](molecule-via-github-actions.md)** — ブラウザのみ・15 分。
   手元に Linux も Docker も要らない。現時点で最も着手コストが低い実行証跡。
3. **既存 CI の成功ログを本台帳へ記録する** — ブラウザのみ・30 分。
   `Backup verify` は毎日自動実行されて成功が蓄積しており（[2026-08-19 時点で 102 回](2026-08-19-ci-baseline.md)）、
   その実績が本台帳に反映されていないことがある。**新しく実行するのではなく、既にある結果を拾う作業**。
4. **[ローカル証跡採録ガイド](local-evidence-quickstart.md)** — Linux + Docker（WSL2 可）・1 晩。
   Grafana dashboard、Loki / Alloy ログ検索、Alertmanager 通知、D-1 復旧演習を採録する。
5. 動画化する場合は [2〜3 分デモ収録ガイド](../demo-capture-guide.md) を使う。

> 1 は使い捨てhost上で起動・疎通・復旧時間まで測る自動実測ですが、GitHub-hosted
> runner内に範囲を限定した証跡です。長期稼働host、実管理端末、組織DNS、cloud firewallの
> 代替にはしません。2 と 3 は構文・設定整合などのCI記録、4 は手元Linux環境の実測です。
> 台帳には実行環境と対象commitを併記します。

外部 probe と中央 telemetry の設計は
[外部 probe / 中央 telemetry 設計](../roadmap/external-probe-central-telemetry.md) にまとめる。

現時点で空の欄があるのは未検証を意味する。実測値は、実際に実行した PR でのみ追加する。
