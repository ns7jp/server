# トラブルシュート一次記録 — YYYY-MM-DD / 事象名

このテンプレートは、完成後に整えた説明ではなく、作業者が実際に考え、確認し、仮説を更新した過程を残すためのものです。`docs/evidence/YYYY-MM-DD-troubleshooting-<slug>.md` へコピーして使います。

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
| 状態 | `NOT RUN` |
| 発生 / 検知日時 | `NOT RUN` |
| 調査開始 / 復旧日時 | `NOT RUN` |
| 環境 / host | `NOT RUN` |
| commit SHA / 直近変更 | `NOT RUN` |
| 作業者 | `NOT RUN` |
| 関連 alert / Issue / runbook | `NOT RUN` |
| raw log | `NOT RUN` |

## 2. 最初に見えた事実

ユーザー影響、alert、HTTP status、error message など、解釈を加える前の情報を書きます。

```text
NOT RUN
```

影響範囲と、影響していないと確認できた範囲:

```text
NOT RUN
```

## 3. 調査サイクル

仮説が変わるたびにこの節を複製します。

### Cycle 1 — YYYY-MM-DD HH:MM:SS JST

**Hypothesis（仮説）**

```text
NOT RUN
```

**Basis（そう考えた根拠）**

```text
NOT RUN
```

**Falsification（何が出れば仮説を棄却するか）**

```text
NOT RUN
```

**Commands（実際に実行したコマンド）**

```bash
# NOT RUN
```

**Result（実出力と exit code）**

```text
NOT RUN
```

**Interpretation（出力から確実に言えること）**

```text
NOT RUN
```

**Decision（採用 / 棄却 / 保留と、次の一手）**

```text
NOT RUN
```

## 4. 原因と復旧

| 項目 | 記録 |
| --- | --- |
| 直接原因 | `UNKNOWN` |
| 寄与要因 | `UNKNOWN` |
| 根本原因 | `UNKNOWN` |
| 復旧操作 | `NOT RUN` |
| ロールバック有無 | `NOT RUN` |
| 復旧確認コマンド | `NOT RUN` |
| RTO / データ影響 | `NOT RUN` |

原因が断定できない場合は `UNKNOWN` のままにし、最も支持される仮説と追加確認を分けて書きます。

## 5. 検証

復旧操作をしたことではなく、利用者視点、service、監視、ログが正常化したことを確認します。

```bash
# 実際に実行したhealth check、query、ログ確認を記録する
# NOT RUN
```

```text
実出力: NOT RUN
判定: NOT RUN
```

## 6. Learning（自分が理解したこと）

- 最初の仮説が当たった / 外れた理由: `NOT RUN`
- 判断に最も役立ったコマンドと出力: `NOT RUN`
- 以前の理解と変わった点: `NOT RUN`
- 次回はどの順番で調べるか: `NOT RUN`
- 監視、設計、runbook へ反映すること: `NOT RUN`

## 7. AI・外部情報の利用開示

AI や記事を使った場合も、提案をそのまま実績にせず、自分が実機で確かめた境界を残します。利用しなければ `利用なし` と記入します。

| 項目 | 記録 |
| --- | --- |
| 使用した AI / 資料 | `NOT SET` |
| 受けた提案 | `NOT SET` |
| 自分で確認したコマンドと結果 | `NOT RUN` |
| 採用した理由 | `NOT SET` |
| 採用しなかった提案と理由 | `NOT SET` |
| 最終判断を自分の言葉で説明 | `NOT SET` |

## 8. 再発防止

| Action | 種別 | 担当 | 期限 | Issue / PR | 状態 |
| --- | --- | --- | --- | --- | --- |
| NOT SET | monitor / code / test / runbook | NOT SET | NOT SET | NOT SET | OPEN |
