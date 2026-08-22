# 検証証跡台帳

このディレクトリは、設計資料や構成コードが存在することと、実環境で確認した結果を
混同しないための台帳である。実行していない検証を成功実績として記載しない。

## 要約（2026-08-22 更新）

**Ansibleロール単体だけでなく、`site.yml`によるhost全体の新規構築・冪等性、
監視stack、認証、network/UFW、D-1、backup restoreまで実測証跡があります。**
[2026-08-22 Full-stack E2E](2026-08-22-full-stack-e2e.md)では、使い捨てUbuntu 24.04 runner上で
23 IDをすべてPASSとして採録しました（[Actions run 32563104045](https://github.com/ns7jp/server-monitor/actions/runs/32563104045)）。

> **履歴（2026-08-21時点）:** 当時はAnsible各ロール、WSL2上の監視stack、D-1、
> 二セグメント障害ラボまでが実測済みで、`site.yml`一括構築（IT-01/02）、runner内
> network/UFW（IT-12）、backup restoreは未採録でした。この履歴を示す
> [2026-08-19結果票](2026-08-19-build-validation.md)は後から上書きしていません。

AlertmanagerからSlackへの実配信、D-2、AWS適用、長期稼働host、実管理端末・組織DNS・
cloud firewallを含むproduction相当のnetwork検証は、現在も未採録です。

| 区分 | 状態 |
| --- | --- |
| CI による自動検証 | ✅ 継続的に実行中（構文・設定整合・依存脆弱性・秘密値混入・バックアップスクリプト） |
| Full-stack E2E | ✅ [2026-08-22](2026-08-22-full-stack-e2e.md)：新規構築、`changed=0`、10 containers、認証、local通知、network/UFW、D-1、3-volume restoreをPASS |
| Ansible ロールの適用・冪等性・検証 | ✅ **4 ロール完走**（[2026-08-17](2026-08-17-molecule.md)、Ubuntu 22.04 コンテナ） |
| 監視スタック全体の起動（Grafana / Loki） | ✅ [2026-08-18](2026-08-18-local-observability.md)。local webhook通知は[2026-08-22 E2E](2026-08-22-full-stack-e2e.md)、Slack実配信は未採録 |
| D-1 復旧演習の実測 | ✅ [2026-08-19](../drills/logs/2026-08-19-D-1.md) RTO 13秒 / [2026-08-22 E2E](2026-08-22-full-stack-e2e.md) RTO 1秒。D-2は未採録 |
| 二セグメント障害ラボの実測 | ✅ [2026-08-19](2026-08-19-network-drill.md)（障害注入→切り分け→復旧、PASS） |
| ネットワーク切り分けの一次メモ | ✅ [2026-08-21](2026-08-21-network-firstlook.md)：公開port不成立を切り分け。2026-08-22に内部segmentを維持した`host-access`構成へ修正し、E2Eでloopback bind / namespace遮断 / SSH tunnelを確認 |
| ephemeral VM の network / UFW | ✅ [2026-08-22](2026-08-22-full-stack-e2e.md)：`NW-01〜09` / `IT-12` / `ST-01,04` PASS |
| 独立した管理端末・対象hostでの network / UFW | ❌ **NOT RUN**（[手順](../build-package/09-network-validation-procedure.md)と[結果票テンプレート](templates/network-host-validation.md)のみ） |
| AWS `apply` / `destroy` と実費 | ❌ 未採録 |
| [試験仕様書](../build-package/06-test-specification.md)の結合・セキュリティ試験 | ⚠ [2026-08-19時点の結果票](2026-08-19-build-validation.md): 11/21 PASS、残り NOT RUN |

> **この証跡が示す範囲を広げて解釈しない。** 2026-08-22 E2EはGitHub-hosted runnerと
> 別Docker namespace内の自動実測です。独立した管理端末、複数host、組織DNS、
> D-2、Slack実配信、AWS適用、長期運用の代替にはしません。

次に採るべき証跡は、Slack実配信、独立した対象host/管理端末のnetwork検証、AWS短時間
`apply / destroy`、D-2のいずれかです。

## 現在の証跡状態

| 対象 | リポジトリで確認できる成果物 | 実行証跡 |
| --- | --- | --- |
| アプリ/API の認証・マスキング | `tests/`、`python-check.yml` | CI 実行結果を PR で確認。[2026-08-19: 4 workflow の直近成功ログを台帳化](2026-08-19-ci-baseline.md) |
| ローカル Python / 成果物検査 | `tests/` | [2026-08-11: 14 tests PASS](2026-08-11-local-code-validation.md) |
| Compose / Prometheus / Loki / Alloy 設定 | `compose.yaml`、`deploy/`、`python-check.yml` | [2026-08-18: Linux(WSL2)上での起動・Grafana実画面・Lokiログ検索を採録](2026-08-18-local-observability.md) |
| Ansible roles | `ansible/`、`ansible-check.yml` | 構文・lint 検証に加え、[2026-08-17: 4 ロールの `molecule test` 完走](2026-08-17-molecule.md)（create → converge → idempotence → verify）。[実行手順](molecule-via-github-actions.md) |
| Ansible full site E2E | `full-stack-e2e.yml`、`scripts/e2e/run-full-stack.sh` | [2026-08-22実測](2026-08-22-full-stack-e2e.md) / [実行・証跡採録手順](../e2e-validation.md) |
| Terraform AWS 構成 | `terraform/`、`terraform-check.yml` | `terraform plan/apply/destroy` と Cost Explorer 実測は未収録 |
| SLO / 復旧演習 | `docs/slo.md`、`docs/drills/`、`scripts/drills/` | D-1は[2026-08-19: RTO 13秒](../drills/logs/2026-08-19-D-1.md) / [2026-08-22 E2E: RTO 1秒](2026-08-22-full-stack-e2e.md)。D-2は未収録 |
| 外部 probe / 中央 telemetry | `docs/roadmap/external-probe-central-telemetry.md` | 外部 probe と中央保存先の実測は未収録 |
| 変更管理 | `.github/pull_request_template.md`、`.github/ISSUE_TEMPLATE/`、`docs/change-management.md` | PR ごとに検証・ロールバック・証跡リンクを残す |
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
| Linux 新規構築・試験 | `docs/evidence/YYYY-MM-DD-build-validation.md` |
| 二セグメント通信障害 | `docs/evidence/YYYY-MM-DD-network-drill.md` |
| Linux 実ホスト network / UFW | `docs/evidence/YYYY-MM-DD-network-host-validation.md` |
| 仮説検証を含む一次切り分け | `docs/evidence/YYYY-MM-DD-troubleshooting-<slug>.md` |
| スクリーンショット | `docs/evidence/screenshots/<kind>_<commit>_<yyyymmdd>.png` |

## 採録テンプレート

| 用途 | テンプレート |
| --- | --- |
| ローカル Grafana / Loki / Alertmanager | [templates/local-observability.md](templates/local-observability.md) |
| AWS 短時間検証 | [templates/aws-validation.md](templates/aws-validation.md) |
| Molecule フル実行 | [templates/molecule.md](templates/molecule.md) |
| Linux 実ホスト network / UFW | [templates/network-host-validation.md](templates/network-host-validation.md) |
| 仮説 → コマンド → 結果 → 学び | [templates/troubleshooting-worklog.md](templates/troubleshooting-worklog.md) |
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
