# 作業結果・引き渡し報告書

> 💡 **初めて読む方へ**: この文書は案件の結果を依頼者へ報告するための文書です。予定と実績の差、トラブル、残課題をまとめます。原本は空欄のまま保存し、実施結果は日付付きのevidenceへコピーして記録します。

## 1. 案件概要

| 項目 | 値 |
| --- | --- |
| 案件ID | `SM-ANS-001` |
| 案件名 | Ansible自動化基盤構築案件パック |
| 対象ホスト | `NOT SET` |
| 報告日 | `NOT SET` |
| 報告者 | `NOT SET` |

## 2. 計画対実績

| 項目 | 計画（設計値） | 実績 | 差異 |
| --- | --- | --- | --- |
| 対象OS | Ubuntu Server 24.04 LTS | `NOT SET` | — |
| 適用方式 | `ansible/playbooks/foundation.yml` | `NOT SET` | — |
| 初回適用 | `failed=0` | `NOT SET` | — |
| 2回目適用 | `changed=0` | `NOT SET` | — |
| 所要時間 | `NOT SET`（初回参考値なし） | `NOT SET` | — |

## 3. 試験集計

| 分類 | 件数 | PASS | FAIL | BLOCKED | NOT RUN |
| --- | --- | --- | --- | --- | --- |
| AFUT（単体・構成） | 5 | `NOT SET` | `NOT SET` | `NOT SET` | `NOT SET` |
| AFIT（構築・結合） | 7 | `NOT SET` | `NOT SET` | `NOT SET` | `NOT SET` |
| AFST（セキュリティ） | 7 | `NOT SET` | `NOT SET` | `NOT SET` | `NOT SET` |
| AFNW（ネットワーク実機検証） | 6 | `NOT SET` | `NOT SET` | `NOT SET` | `NOT SET` |

集計の元になる個別結果は[試験仕様書・結果票](06-test-specification.md)と[ネットワーク実機検証手順](09-network-validation-procedure.md)を参照してください。件数は本書と個別結果票とで一致させます。

## 4. 設計との差異

| 項目 | 設計値 | 実績値 | 差異の理由 |
| --- | --- | --- | --- |
| `NOT SET` | — | — | — |

## 5. 障害・トラブル

| 発生日 | 内容 | 原因 | 対応 | 再発防止 |
| --- | --- | --- | --- | --- |
| `NOT SET` | — | — | — | — |

## 6. 残存リスク

| リスク | 影響 | 対応方針 |
| --- | --- | --- |
| AlmaLinux/Rocky 9実機ホストでの構築が未実施 | RHEL系での動作保証がMoleculeのコンテナ検証にとどまる | フェーズ2としてVM用意後に着手（[05-build-procedure.md 手順9](05-build-procedure.md#9-フェーズ2-almalinuxrocky-9への適用)） |
| `foundation.yml`合成後のCI自動検証が無い | role単体は検証されるが、組み合わせた際の実コンテナ収束は手動確認に依存 | `ansible-integration.yml`への追加を検討（[07-handover-checklist.md](07-handover-checklist.md#未解決事項)） |
| この検証環境でのansible-lint/構文検証が未実施 | 実行環境のネットワーク制約による | GitHub Actions側の実行結果で代替確認する |

## 7. 完了判定

| 判定 | 状態 |
| --- | --- |
| フェーズ1（Ubuntu）完了 | `NOT SET` |
| フェーズ2（RHEL系）完了 | `NOT SET`（着手前） |
| 引き渡し完了 | `NOT SET` |

計画と実績が一致し、必須試験がすべて`PASS`し、残存リスクを引き渡し先が了承した時点で完了と判定します。
