# 検証証跡台帳

このディレクトリは、設計資料や構成コードが存在することと、実環境で確認した結果を
混同しないための台帳である。実行していない検証を成功実績として記載しない。

## 現在の証跡状態

| 対象 | リポジトリで確認できる成果物 | 実行証跡 |
| --- | --- | --- |
| アプリ/API の認証・マスキング | `tests/`、`python-check.yml` | CI 実行結果を PR で確認 |
| Compose / Prometheus / Loki / Alloy 設定 | `compose.yaml`、`deploy/`、`python-check.yml` | Linux Docker ホストでの起動記録は未収録 |
| Ansible roles | `ansible/`、`ansible-check.yml` | 構文検証あり。フル `molecule test` は `ansible-integration.yml` の実行結果を採録する |
| Terraform AWS 構成 | `terraform/`、`terraform-check.yml` | `terraform plan/apply/destroy` と Cost Explorer 実測は未収録 |
| SLO / 復旧演習 | `docs/slo.md`、`docs/drills/`、`scripts/drills/` | D-1 / D-2 の実測ログは未収録 |
| 外部 probe / 中央 telemetry | `docs/external-probe-central-telemetry.md` | 外部 probe と中央保存先の実測は未収録 |
| 変更管理 | `.github/pull_request_template.md`、`.github/ISSUE_TEMPLATE/`、`docs/change-management.md` | PR ごとに検証・ロールバック・証跡リンクを残す |

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
| Molecule フル実行 | `docs/evidence/YYYY-MM-DD-molecule.md` |
| Grafana / Loki / Alertmanager ローカル採録 | `docs/evidence/YYYY-MM-DD-local-observability.md` |
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

まずは [ローカル証跡採録ガイド](local-evidence-quickstart.md) に沿って、無料で完結する
Grafana dashboard、Loki / Alloy ログ検索、Alertmanager 通知、D-1 復旧演習を採録する。
動画化する場合は [2〜3 分デモ収録ガイド](../demo-capture-guide.md) を使う。

外部 probe と中央 telemetry の設計は
[外部 probe / 中央 telemetry 設計](../external-probe-central-telemetry.md) にまとめる。

現時点で空の欄があるのは未検証を意味する。実測値は、実際に実行した PR でのみ追加する。
