# 学習記録: Level 3 — 観測経路の確認（Prometheus→Grafana→Loki）

[`docs/learning-path.md`](../learning-path.md) の「共通の学習記録」フォーマットに沿った個人の学習記録です。
`docs/evidence/` 配下の公式な検証証跡とは異なり、案件パックの受け入れ判定には使用しません。

```text
日付 / commit SHA / 実行者: 2026-08-31 / bc7cb01e3dcedd8ec65c7698a95def13cb1745b4（クローン時点のorigin/main）/ usr722
環境（OS、VM/VPS/CI、tool version）: WSL2 Ubuntu 24.04（DESKTOP-19F10FT）、Docker 29.1.3、Docker Compose 2.40.3
レベルと目的: Level 0〜3（前提診断・単体テスト・Docker Compose起動・観測経路の確認）
実行コマンド:
  - ./scripts/learning/check-prerequisites.sh
  - python -m compileall app.py tests && pytest -q
  - docker compose up -d --build / docker compose ps / curl -fsS http://127.0.0.1:8080/healthz
  - Grafana UI (http://127.0.0.1:3000) ダッシュボード確認
  - Prometheus UI (http://127.0.0.1:9090) Status→Targets確認
  - Grafana Explore→Loki→Label browserで`service`ラベル選択→`{service="nginx"}`でShow logs
期待結果 / 実測結果:
  - 前提診断: 全項目PASS
  - pytest: 153 passed、終了コード0
  - Docker Compose: 全10コンテナrunning（app healthy）、/healthzが{"status":"ok"}
  - metrics: Prometheus targetsおよびGrafanaダッシュボードで値を確認
  - logs: Loki Label browserで`service`ラベルを確認し、`{service="nginx"}`でnginxログ18件を取得
判定: PASS（Level 0〜3の完了条件を満たした）
分かったこと:
  - node-exporterはホストの`/`をrslaveマウントで参照するため、WSL2の`mount --make-rshared /`設定が必要。WSL2は再起動のたびにこの設定を失う。
  - Grafanaのadminパスワードは`GF_SECURITY_ADMIN_PASSWORD__FILE`経由で永続ボリューム`grafana_data`にDBが存在しない初回起動時にのみ設定される。秘密値ファイル確定前に一度でも初期化されると、後からファイルを書き換えても反映されない。
  - Lokiのログラベルは`service`（`deploy/alloy/config.alloy`でDocker Composeのservice名から生成）。検索前にLabel browserで実在するラベル・値を確認すると早い。
失敗と仮説:
  - node-exporterが`path / is mounted on / but it is not a shared or slave mount`で起動失敗→WSL2のマウント伝播設定のリセットが原因。`sudo mount --make-rshared /`で解消。
  - Grafanaログインが`invalid password`で失敗→秘密値ファイル確定前にadmin DBが初期化されていたためと推測。`grafana_data`ボリューム削除→`docker compose up -d grafana`で再初期化し解消。
  - Loki検索が最初「No data」→クエリ自体は正しかったが、実在するラベル値を確認せず検索していたため。Label browserを使って解決。
戻し方を実行した結果:
  - `docker compose stop grafana && docker compose rm -f grafana && docker volume rm server-monitor-lab_grafana_data && docker compose up -d grafana` を実行し、正常に再初期化されたことを確認。
次に試すこと: Level 4（Ansibleでの構築・冪等性確認）
AI・外部情報を使った範囲: Claude Codeとの対話で、WSL2環境構築・WSL2のmount propagation問題・Grafana admin password初期化の仕組み・Lokiラベルの調査方法について助言を受けた。実際のコマンド実行・画面操作・結果確認は本人が実施。
```
