# ローカル証跡採録ガイド

設計を「動かした証拠」に変えるための最短手順。Linux + Docker のローカル環境で、
Grafana、Loki、Alertmanager、D-1 復旧演習の証跡を採録する。

> **先に済ませられるものがある**: Linux 環境の用意が障壁になっている場合、
> [Molecule を GitHub Actions で実行する](molecule-via-github-actions.md) は
> **ブラウザだけで 15 分**で採録できる。本ガイドに着手する前に、そちらを先に消化してよい。
>
> なお本ガイドの手順は **WSL2 上の Ubuntu でも実行できる**。専用マシンや VM の新規構築は必須ではない。
> Grafana / Loki / D-1 の採録は [2026-08-18](2026-08-18-local-observability.md) ／ [2026-08-19](../drills/logs/2026-08-19-D-1.md) に完了済み。
> `docs/screenshot.png` も Linux(WSL2) 上の実行画面へ差し替え済み。未採録なのは Alertmanager → Slack の実配信と D-2 のみ。

---

## 0. 事前準備

```bash
git rev-parse --short HEAD
docker --version
docker compose version
date '+%Y-%m-%d %H:%M:%S %Z'
```

上記の出力を、採録メモの冒頭に残す。秘密値、公開 IP、個人名、webhook URL は
スクリーンショットにもログにも残さない。

---

## 1. 起動証跡

```bash
cp .env.example .env
openssl rand -base64 32 > deploy/secrets/dashboard_password.txt
openssl rand -base64 32 > deploy/secrets/metrics_token.txt
openssl rand -base64 32 > deploy/secrets/grafana_admin_password.txt
# 600 にすると、コンテナ内で別 UID(例: Grafana は 472)で読むコンテナが
# Permission denied で起動できない(実機で確認済み)。644 にする。
chmod 644 deploy/secrets/*.txt
docker compose up -d --build
docker compose ps
curl -i http://127.0.0.1:8080/healthz
```

残すもの：

- `docker compose ps` の結果
- `/healthz` の `200` 応答
- Grafana の Home または dashboard 画面

---

## 2. Grafana dashboard

1. `http://127.0.0.1:3000/` にログインする。
2. `Server Monitor` と `Server Monitor SLO` dashboard を開く。
3. 時刻範囲、対象 commit、JST の実行日時が分かるメモと一緒にスクリーンショットを保存する。

保存例：

```text
docs/evidence/screenshots/grafana-server-monitor_<commit>_YYYYMMDD.png
docs/evidence/screenshots/grafana-slo_<commit>_YYYYMMDD.png
```

---

## 3. Loki / Alloy ログ検索

Grafana Explore で Loki を選び、次のようなクエリを実行する。

```logql
{job="containers"} |= "server-monitor"
{service="nginx"} |= "GET"
```

残すもの：

- クエリ文字列
- 結果行
- 対象時刻範囲
- Alloy / Loki が起動している `docker compose ps`

---

## 4. Alertmanager 通知

Slack webhook を使う場合は `compose.slack.yaml.example` を重ねる。webhook URL は
スクリーンショットに写さない。

```bash
docker compose -f compose.yaml -f compose.slack.yaml.example up -d alertmanager prometheus
```

残すもの：

- FIRING 通知
- RESOLVED 通知
- 通知到達までの時間
- 対応したランブック URL

---

## 5. D-1 プロセス停止演習

```bash
./scripts/drills/d1-process-down.sh
```

記録先：

```text
docs/drills/logs/YYYY-MM-DD-D-1.md
```

テンプレートは [D-1 ログテンプレート](../drills/logs/TEMPLATE-D-1-process-down.md) を使う。
検知時刻、復旧時刻、RTO、改善点を実測で埋める。

---

## 6. PR への添付

証跡を追加する PR では、次を本文に貼る。

| 項目 | 内容 |
| --- | --- |
| 対象 commit | `git rev-parse --short HEAD` |
| 実行日時 | JST |
| 環境 | OS、Docker、Compose |
| 結果 | PASS / FAIL、所要時間 |
| 証跡 | スクリーンショット、ログ、`docs/evidence/`、`docs/drills/logs/` |
| マスキング | 秘密値、公開 IP、AWS account ID、個人名、webhook URL を確認 |

---

## 片付け

```bash
docker compose down
```

volume を削除する場合は、証跡に必要なデータを保存してから実行する。

```bash
docker compose down -v
```
