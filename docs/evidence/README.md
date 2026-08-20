# 検証証跡台帳

このディレクトリは、設計資料や構成コードが存在することと、実環境で確認した結果を
混同しないための台帳である。実行していない検証を成功実績として記載しない。

## 要約（2026-08-19 時点）

**Ansible ロールの適用・冪等性、監視スタック全体の Linux 上での起動、D-1 復旧演習、
二セグメント障害ラボについて、実測証跡がある。**
一方、Alertmanager から Slack への実配信、D-2 復旧演習、AWS 適用、`site.yml` を通した新規構築（IT-01/02）は未採録。

| 区分 | 状態 |
| --- | --- |
| CI による自動検証 | ✅ 継続的に実行中（構文・設定整合・依存脆弱性・秘密値混入・バックアップスクリプト） |
| Ansible ロールの適用・冪等性・検証 | ✅ **4 ロール完走**（[2026-08-17](2026-08-17-molecule.md)、Ubuntu 22.04 コンテナ） |
| 監視スタック全体の起動（Grafana / Loki） | ✅ [2026-08-18](2026-08-18-local-observability.md)（Alertmanager 通知配信は未採録） |
| D-1 復旧演習の実測 | ✅ [2026-08-19](../drills/logs/2026-08-19-D-1.md)（RTO 13 秒） ／ D-2 は未採録 |
| 二セグメント障害ラボの実測 | ✅ [2026-08-19](2026-08-19-network-drill.md)（障害注入→切り分け→復旧、PASS） |
| AWS `apply` / `destroy` と実費 | ❌ 未採録 |
| [試験仕様書](../build-package/06-test-specification.md)の結合・セキュリティ試験 | ⚠ [2026-08-19時点の結果票](2026-08-19-build-validation.md): 11/21 PASS、残り NOT RUN |

> **この証跡が示す範囲を広げて解釈しない。** 確認できたのは「ロールが適用でき、冪等で、期待した状態になる」
> こと、「監視スタックが Linux 上で実際に起動し、Grafana / Loki が実データを表示する」こと、
> 「D-1（プロセスダウン）の復旧を実測した」ことである。実 VM での挙動、複数ホスト間の疎通、
> D-2（ホスト障害）の復旧、Slack への実際の通知配信、AWS 適用は含まない。

次に採るべき証跡は [ローカル証跡採録ガイド](local-evidence-quickstart.md)（Linux + Docker、WSL2 可・1 晩・0 円）。

## 現在の証跡状態

| 対象 | リポジトリで確認できる成果物 | 実行証跡 |
| --- | --- | --- |
| アプリ/API の認証・マスキング | `tests/`、`python-check.yml` | CI 実行結果を PR で確認。[2026-08-19: 4 workflow の直近成功ログを台帳化](2026-08-19-ci-baseline.md) |
| ローカル Python / 成果物検査 | `tests/` | [2026-08-11: 14 tests PASS](2026-08-11-local-code-validation.md) |
| Compose / Prometheus / Loki / Alloy 設定 | `compose.yaml`、`deploy/`、`python-check.yml` | [2026-08-18: Linux(WSL2)上での起動・Grafana実画面・Lokiログ検索を採録](2026-08-18-local-observability.md) |
| Ansible roles | `ansible/`、`ansible-check.yml` | 構文・lint 検証に加え、[2026-08-17: 4 ロールの `molecule test` 完走](2026-08-17-molecule.md)（create → converge → idempotence → verify）。[実行手順](molecule-via-github-actions.md) |
| Terraform AWS 構成 | `terraform/`、`terraform-check.yml` | `terraform plan/apply/destroy` と Cost Explorer 実測は未収録 |
| SLO / 復旧演習 | `docs/slo.md`、`docs/drills/`、`scripts/drills/` | [2026-08-19: D-1 `app` プロセスダウン、RTO 13 秒で復旧](../drills/logs/2026-08-19-D-1.md)。D-2 は未収録 |
| 外部 probe / 中央 telemetry | `docs/roadmap/external-probe-central-telemetry.md` | 外部 probe と中央保存先の実測は未収録 |
| 変更管理 | `.github/pull_request_template.md`、`.github/ISSUE_TEMPLATE/`、`docs/change-management.md` | PR ごとに検証・ロールバック・証跡リンクを残す |
| 構築工程成果物 | `docs/build-package/` | 設計・構築・試験様式を整備。実機結果は各検証ログへ記録 |
| 二セグメント障害ラボ | `labs/network-troubleshooting/` | [2026-08-19: 障害注入→切り分け→復旧を実測、PASS](2026-08-19-network-drill.md) |

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
| スクリーンショット | `docs/evidence/screenshots/<kind>_<commit>_<yyyymmdd>.png` |

## 採録テンプレート

| 用途 | テンプレート |
| --- | --- |
| ローカル Grafana / Loki / Alertmanager | [templates/local-observability.md](templates/local-observability.md) |
| AWS 短時間検証 | [templates/aws-validation.md](templates/aws-validation.md) |
| Molecule フル実行 | [templates/molecule.md](templates/molecule.md) |
| D-1 プロセスダウン | [../drills/logs/TEMPLATE-D-1-process-down.md](../drills/logs/TEMPLATE-D-1-process-down.md) |
| D-2 ホスト障害復旧 | [../drills/logs/TEMPLATE-D-2-host-failure.md](../drills/logs/TEMPLATE-D-2-host-failure.md) |

## 採録手順

**必要な環境が軽い順**に進める。

1. **[Molecule を GitHub Actions で実行する](molecule-via-github-actions.md)** — ブラウザのみ・15 分。
   手元に Linux も Docker も要らない。現時点で最も着手コストが低い実行証跡。
2. **既存 CI の成功ログを本台帳へ記録する** — ブラウザのみ・30 分。
   `Backup verify` は毎日自動実行されて成功が蓄積しており（[2026-08-19 時点で 102 回](2026-08-19-ci-baseline.md)）、
   その実績が本台帳に反映されていないことがある。**新しく実行するのではなく、既にある結果を拾う作業**。
3. **[ローカル証跡採録ガイド](local-evidence-quickstart.md)** — Linux + Docker（WSL2 可）・1 晩。
   Grafana dashboard、Loki / Alloy ログ検索、Alertmanager 通知、D-1 復旧演習を採録する。
4. 動画化する場合は [2〜3 分デモ収録ガイド](../demo-capture-guide.md) を使う。

> 1 と 2 は CI による機械検証であり、**実機の実測証跡の代わりにはならない**。
> CI で担保できるのは構文・設定の整合・依存の脆弱性までで、
> 起動・疎通・復旧時間は 3 以降でしか確認できない。台帳にもこの区別を明記する。

外部 probe と中央 telemetry の設計は
[外部 probe / 中央 telemetry 設計](../roadmap/external-probe-central-telemetry.md) にまとめる。

現時点で空の欄があるのは未検証を意味する。実測値は、実際に実行した PR でのみ追加する。
