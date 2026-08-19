# 既存 CI の成功ログ 証跡 — 2026-08-19

新しく何かを実行した記録ではなく、**すでに継続的に実行されている CI の、直近の成功結果を拾って記録**したもの（[証跡採録チェックリスト](https://github.com/ns7jp/ns7jp/blob/main/docs/evidence-capture-checklist.md) 優先 2）。

## 対象 commit

`cc7e478`（`main`、PR #61 マージ後）

## 直近の成功実行

| ワークフロー | 内容 | 結果 | commit | 実行日時（UTC） | 実行 URL |
| --- | --- | --- | --- | --- | --- |
| Python check | `pytest`、lint 等 | ✅ success | `cc7e478` | 2026-08-19T07:25:57Z | [run](https://github.com/ns7jp/server-monitor/actions/runs/32227795483) |
| Terraform check | `fmt` / `validate` / `tfsec` / `checkov` | ✅ success | `6f31f930` | 2026-08-19T06:32:46Z | [run](https://github.com/ns7jp/server-monitor/actions/runs/32223863869) |
| Security scan | Trivy（脆弱性・secret・misconfig） | ✅ success | `cc7e478` | 2026-08-19T07:25:56Z | [run](https://github.com/ns7jp/server-monitor/actions/runs/32227795460) |
| Backup verify | バックアップアーカイブの smoke test | ✅ success | `8e3f659` | 2026-08-18T09:16:22Z | [run](https://github.com/ns7jp/server-monitor/actions/runs/32120720528) |

## Backup verify の累計実行回数（訂正）

`docs/evidence-capture-checklist.md`（ns7jp/ns7jp 側）に「累計 400 回超」という記載があったが、
GitHub Actions API で実際に数えたところ **`Backup verify` の総実行回数は 102 回**だった
（2026-08-19 時点、`workflow_runs.total_count`）。400 回超という記載は事実と異なっていたため、
本ファイルで正しい数値に訂正し、参照元も修正する。

`Backup verify` は毎日 04:00 UTC に自動実行される scheduled workflow であり、102 回という回数自体は
2026-05 頃からの運用期間と整合する。**回数が少なかったから価値が低いという意味ではない**。継続的に
自動実行され、失敗なく積み上がっているという事実自体が、「自動化された検証を継続的に回している」
ことの証拠である。

## この証跡が示す範囲

CI が担保するのは構文・設定の整合性・既知の脆弱性・secret 混入の有無までであり、**実機での起動・疎通・
復旧時間は含まない**。この境界は [Molecule フル実行記録](2026-08-17-molecule.md)・[ローカル可観測性証跡](2026-08-18-local-observability.md)・[D-1 演習記録](../drills/logs/2026-08-19-D-1.md) が別途担っている。

## 関連

- [検証証跡台帳](README.md)
- [証跡採録チェックリスト](https://github.com/ns7jp/ns7jp/blob/main/docs/evidence-capture-checklist.md)（ns7jp/ns7jp、優先 2 の由来）
