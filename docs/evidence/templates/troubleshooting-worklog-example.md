# トラブルシュート一次記録 — 2026-08-19 / D-1演習2回目のFAIL（記入例）

> これは[トラブルシューティング一次記録テンプレート](troubleshooting-worklog.md)の記入例です。
> [D-1演習の実際の証跡](../../drills/logs/2026-08-19-D-1.md)を題材に、テンプレートの
> 「仮説 → 根拠 → 反証条件 → コマンド → 結果 → 解釈 →決定」という調査サイクルの書き方を
> 具体的に示します。空欄からいきなり書き始めるのが難しい場合は、この記入例の分量・粒度を
> 参考にしてください。

## 記録ルール

- 観測した事実と推測を別の欄へ書く。
- コマンドは省略せず、実際に実行した順序と時刻で残す。
- 期待と違う出力や失敗した仮説も削除しない。
- 出力を要約した場合は raw log の位置を示す。
- 未実行の欄は `NOT RUN`、確認できない欄は理由付き `UNKNOWN` とする。
- 秘密値、cookie、token、個人情報、公開 IP は貼らない。

## 1. 基本情報

| 項目 | 値 |
| --- | --- |
| 状態 | 復旧済み |
| 発生 / 検知日時 | 2026-08-19 14:45 JST頃 |
| 調査開始 / 復旧日時 | 2026-08-19 14:45 JST 開始 / 15:20 JST 復旧確認 |
| 環境 / host | ローカル Linux（WSL2 Ubuntu 24.04）+ Docker Compose |
| commit SHA / 直近変更 | `5dfc67d`（[PR #56](https://github.com/ns7jp/server-monitor/pull/56)適用直後） |
| 作業者 | 演習実施者（1名） |
| 関連 alert / Issue / runbook | [D-1-process-down.md](../../drills/D-1-process-down.md)、[docs/runbooks/service-down.md](../../runbooks/service-down.md) |
| raw log | `docker compose logs --tail=200 nginx app`（この記入例では要約のみ。実際の演習では保存する） |

## 2. 最初に見えた事実

```text
D-1演習スクリプト（./scripts/drills/d1-process-down.sh）を2回目に実行したところ、
appコンテナをkillした後、/healthzがタイムアウトまで200を返さずFAILした。
1回目の失敗（docker compose kill方式）を直したはずなのに、また復旧しなかった。
```

影響範囲と、影響していないと確認できた範囲:

```text
影響: appコンテナが復旧しても、nginx経由の/healthzが応答しない。
影響していない: PrometheusやGrafanaなど他コンポーネントは無関係に動作していた（未確認、憶測）。
```

## 3. 調査サイクル

仮説が変わるたびにこの節を複製します。

### Cycle 1 — 2026-08-19 14:50:00 JST

**Hypothesis（仮説）**

```text
DockerまたはWSL2側の不安定な挙動により、修正した「ホスト側PIDへの直接kill」方式が
正しく動いていないのではないか。
```

**Basis（そう考えた根拠）**

```text
1回目の失敗原因（docker compose killが自動復旧を無効化する）は既にPR #56で修正済みのはず。
それでも同じ症状（復旧しない）が再発したため、環境側の不安定さを最初に疑った。
```

**Falsification（何が出れば仮説を棄却するか）**

```text
docker eventsやdocker inspectで、コンテナの再起動自体は正常に行われている（RestartCountが
増えている）のに、上位のnginx側だけが異常な場合は、Docker/WSL2の不安定さではなく、
別の層（アプリ設定側）の問題である可能性が高いと判断する。
```

**Commands（実際に実行したコマンド）**

```bash
docker events --since 10m
docker inspect server-monitor-lab-app-1 --format 'restartCount={{.RestartCount}} startedAt={{.State.StartedAt}}'
docker compose logs --tail=100 nginx
```

**Result（実出力と exit code）**

```text
docker eventsでは app コンテナのkill→restartイベントが記録されており、
RestartCountも増加していた（appコンテナ自体の自動復旧は成功していた）。
一方nginxのログには "host not found in upstream \"app\"" というエラーが
繰り返し出力されていた。exit codeは記録し忘れ（この点は演習の反省点）。
```

**Interpretation（出力から確実に言えること）**

```text
appコンテナ自体は正常に自動復旧している。復旧しないのはnginx側がappの名前解決に
失敗し続けているためであり、Docker/WSL2の不安定さという最初の仮説は支持されない。
```

**Decision（採用 / 棄却 / 保留と、次の一手）**

```text
仮説1を棄却。nginxのupstream名前解決がなぜ失敗し続けるのかを次のCycleで調べる。
```

### Cycle 2 — 2026-08-19 15:00:00 JST

**Hypothesis（仮説）**

```text
nginxはupstreamの名前解決を起動時の1回しか行わないため、app起動前にnginxが
先に（または再）起動すると、appが後から復旧してもnginxは解決に失敗したままに
なっているのではないか。
```

**Basis（そう考えた根拠）**

```text
nginx（特にopen-source版）のデフォルト設定では、upstreamのDNS解決はworker起動時の
1回のみで、動的な再解決には`resolver`ディレクティブ等の追加設定が必要という一般的な
知識があった。
```

**Falsification（何が出れば仮説を棄却するか）**

```text
nginxコンテナだけを明示的に再起動して名前解決をやり直させても/healthzが回復しない
場合は、この仮説は棄却される。
```

**Commands（実際に実行したコマンド）**

```bash
docker compose restart nginx
sleep 3
curl -fsS http://127.0.0.1:8080/healthz
```

**Result（実出力と exit code）**

```text
docker compose restart nginx 実行後、curlは200を返した（exit code 0）。
```

**Interpretation（出力から確実に言えること）**

```text
nginxを再起動しただけで復旧したことから、appの復旧自体は既に完了していたが、
nginxが古い（失敗した）名前解決結果を保持し続けていたことが原因だったと判断できる。
```

**Decision（採用 / 棄却 / 保留と、次の一手）**

```text
仮説2を採用。恒久対応（resolverディレクティブによる動的解決、または現状を制約として
明記するか）は別途検討課題としてIssue化し、この演習自体は復旧確認まで完了とする。
```

## 4. 原因と復旧

| 項目 | 記録 |
| --- | --- |
| 直接原因 | nginxがappコンテナ復旧後もupstreamの古い名前解決結果を保持し、接続に失敗し続けていた |
| 寄与要因 | nginxのupstream名前解決は起動時の1回のみで、動的な再解決の設定（resolver等）が無かった |
| 根本原因 | appが停止していたタイミングでnginx側の名前解決が失敗し、その状態のままキャッシュされた |
| 復旧操作 | `docker compose restart nginx` |
| ロールバック有無 | なし（設定変更ではなくコンテナ再起動のみ） |
| 復旧確認コマンド | `curl -fsS http://127.0.0.1:8080/healthz` |
| RTO / データ影響 | 演習全体としてのRTOはD-1証跡（[2026-08-19-D-1.md](../../drills/logs/2026-08-19-D-1.md)）に別途記録。データ影響なし |

## 5. 検証

```bash
curl -fsS http://127.0.0.1:8080/healthz
docker compose ps
```

```text
実出力: /healthzが200を返し、docker compose psで全サービスがhealthyだった。
判定: PASS
```

## 6. Learning（自分が理解したこと）

- 最初の仮説が当たった / 外れた理由: 外れた。DockerやWSL2という「低レイヤーの不安定さ」を
  先に疑ったが、実際はアプリケーション層（nginxの名前解決キャッシュ）の既知の挙動だった。
- 判断に最も役立ったコマンドと出力: `docker events`でappコンテナ自体は正常復旧していると
  確認できたこと。これで疑う範囲をnginx側に絞れた。
- 以前の理解と変わった点: 「コンテナが復旧した」ことと「依存先から見える状態が復旧した」
  ことは別物だと再認識した。
- 次回はどの順番で調べるか: 低レイヤー（Docker/OS）を疑う前に、まず「症状が出ている
  コンポーネント自身のログ」を確認する。今回もnginxログを先に見ていればもっと早く
  切り分けられた。
- 監視、設計、runbook へ反映すること: nginxのupstream解決失敗パターンをrunbookの
  「よくある原因」に追記する候補として記録した。

## 7. AI・外部情報の利用開示

| 項目 | 記録 |
| --- | --- |
| 使用した AI / 資料 | nginxの`resolver`ディレクティブに関する一般的な技術知識（過去の学習による） |
| 受けた提案 | なし（この記入例では外部ツールへの質問は行っていない） |
| 自分で確認したコマンドと結果 | `docker events`、`docker inspect`、`docker compose logs`、`docker compose restart nginx`、`curl`の実行と出力をすべて上記に記録済み |
| 採用した理由 | 実際にnginx再起動だけで復旧したことをコマンドで確認できたため |
| 採用しなかった提案と理由 | 該当なし |
| 最終判断を自分の言葉で説明 | appの自動復旧自体は正しく動いていたが、nginxが古い名前解決結果を保持し続けたことが復旧の見かけ上の遅れの原因だった |

## 8. 再発防止

| Action | 種別 | 担当 | 期限 | Issue / PR | 状態 |
| --- | --- | --- | --- | --- | --- |
| nginxのupstream解決失敗時の切り分け手順をrunbookへ追記する | runbook | 演習実施者 | 次回演習まで | NOT SET | OPEN |
| resolverディレクティブによる動的解決の要否を検討する | code | 演習実施者 | NOT SET | NOT SET | OPEN |
