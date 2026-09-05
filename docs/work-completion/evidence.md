# 根拠と検証の記録

作成日・読取確認日：2026-09-05（日本時間）  
[入口](README.md)／[設計書](design.md)

## 1. 根拠の扱い

公開リポジトリの文書・コード・結果メタデータを読み、本設計への接続を判断した。既存システムの再構築や復旧は実行していない。設計上の仮値と架空例は、実測結果として扱わない。過去の作業方針も参考にしたが、対象リポジトリと主要な接続先は今回読み直した。

通常のGitHubページの取得では古い紹介文が返ったため、読取用GitHub APIでmainを確認し、コミット固定の文書・コードを参照した。確認時の対象は次のとおり。

- リポジトリ：[ns7jp/server](https://github.com/ns7jp/server)
- コミット：[44c52e733826b9b5239918c05010b8b68b60346c](https://github.com/ns7jp/server/commit/44c52e733826b9b5239918c05010b8b68b60346c)
- コミット時刻：2026-09-05 00:47:45 UTC
- 関連するマージ：[PR #155](https://github.com/ns7jp/server/pull/155)

これは確認時点のスナップショットであり、将来のmainを保証しない。

## 2. 既存資産への接続表

| 資料 | 今回確認して利用した内容 | 設計への接続 |
|---|---|---|
| [初心者ガイド](https://github.com/ns7jp/server/blob/44c52e733826b9b5239918c05010b8b68b60346c/docs/beginner-learning-guide.md) | app／nginx、応答と認証、停止・再開、説明 | 初回実習の範囲と終了条件 |
| [実習記録テンプレート](https://github.com/ns7jp/server/blob/44c52e733826b9b5239918c05010b8b68b60346c/docs/evidence/templates/beginner-practice-record.md) | 期待値・実出力・判定の分離 | 証跡カード |
| [学習経路](https://github.com/ns7jp/server/blob/44c52e733826b9b5239918c05010b8b68b60346c/docs/learning-path.md) | 段階の完了条件 | 1回の終了と全習得の区別 |
| [設計判断](https://github.com/ns7jp/server/blob/44c52e733826b9b5239918c05010b8b68b60346c/docs/design-decisions.md) | 理由・代替・欠点・見直し条件 | 技術への固執を再検討条件へ置換 |
| [切り分け記録](https://github.com/ns7jp/server/blob/44c52e733826b9b5239918c05010b8b68b60346c/docs/evidence/templates/troubleshooting-worklog.md) | 仮説・根拠・棄却条件・結果・解釈 | 反復を止めて仮説を更新 |
| [SLO文書](https://github.com/ns7jp/server/blob/44c52e733826b9b5239918c05010b8b68b60346c/docs/slo.md)と[ルール](https://github.com/ns7jp/server/blob/44c52e733826b9b5239918c05010b8b68b60346c/deploy/prometheus/slo-rules.yml) | 文書の変更停止条件と通知条件が別 | 接続前に判定条件と測定仕様を確認 |
| [変更・rollback票](https://github.com/ns7jp/server/blob/44c52e733826b9b5239918c05010b8b68b60346c/docs/build-package/08-change-rollback-plan.md) | 版・バックアップ・判断期限・開始終了条件 | 投入時間より事前の戻す条件を優先 |
| [変更管理](https://github.com/ns7jp/server/blob/44c52e733826b9b5239918c05010b8b68b60346c/docs/change-management.md)・[PRテンプレート](https://github.com/ns7jp/server/blob/44c52e733826b9b5239918c05010b8b68b60346c/.github/pull_request_template.md)・[Change request](https://github.com/ns7jp/server/blob/44c52e733826b9b5239918c05010b8b68b60346c/.github/ISSUE_TEMPLATE/change-request.yml) | 目的・範囲・検証・rollback・証跡 | 既存Change IDを使い重複台帳を避ける |
| [Full-stack E2E](https://github.com/ns7jp/server/blob/44c52e733826b9b5239918c05010b8b68b60346c/.github/workflows/full-stack-e2e.yml)と[証跡台帳](https://github.com/ns7jp/server/blob/44c52e733826b9b5239918c05010b8b68b60346c/docs/evidence/README.md) | 版・環境・結果・artifact、保存期間30日 | 証跡の適用範囲・期限を管理 |
| [日次点検](https://github.com/ns7jp/server/blob/44c52e733826b9b5239918c05010b8b68b60346c/scripts/ops/daily-check.sh)と[受入確認](https://github.com/ns7jp/server/blob/44c52e733826b9b5239918c05010b8b68b60346c/scripts/ops/acceptance-check.sh) | 対象サービスとSKIPの扱いの違い | 終了コード0だけを完了根拠にしない |

### 接続前の未確定事項

SLO文書には可用性99.5%／30日窓と、エラーバジェット80%超消費時の変更停止が記載されている。一方でコードの消尽通知は `>=1` であり、同じ閾値を表すものではない。レイテンシの表現と測定定義、計画停止の扱いも、自動化への接続前に一致を確認する必要がある。今回、SLOの実データ・30日間の達成・計画停止の実処理は確認していない。

branch APIでは確認時点のmainに `protected:false` と必須チェック設定なしが返った。リポジトリや組織の全ルールセットについての包括的な監査は未実施。したがって、現在のテンプレートにチェック欄があることだけでは、マージを止める強制ゲートが有効だとは判断しない。

## 3. 現行コミットのCIメタデータ

同じSHAのworkflow runs取得では次の3件が確認できた。いずれも取得時の結果メタデータは `completed / success`。

| Workflow | 実行の参照 |
|---|---|
| Python check／push | [run 33934138705](https://github.com/ns7jp/server/actions/runs/33934138705) |
| Security scan／push | [run 33934138684](https://github.com/ns7jp/server/actions/runs/33934138684) |
| Backup verify／schedule | [run 33954191018](https://github.com/ns7jp/server/actions/runs/33954191018) |

同SHAの取得結果は3件で、Full-stack E2Eの実行結果は含まれていなかった。E2E workflowには変更パスによる起動条件がある。文書変更後のSHAで全構築・復旧を再実測したとは主張しない。ジョブログ、artifact本体、永続ホスト、本人の実習実施は今回未確認。

## 4. 設計原則の参考資料

| 一次資料 | 利用した考え方 | 本設計で独自に決めたこと |
|---|---|---|
| [Google SRE：Eliminating Toil](https://sre.google/sre-book/eliminating-toil/) | 反復する運用作業を改善対象として整理 | 60秒カードと週次10分。Googleの時間配分を個人に適用しない |
| [Google SRE：Error Budget Policy](https://sre.google/workbook/error-budget-policy/) | 信頼性の指標で変更の優先を切り替える | 作業の終了判定とSLOを区別する構造 |
| [Google SRE：Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/) | 意味のある通知と低い雑音、常時目視への依存を減らす | 個人の見直し通知と障害通知を別に扱う |
| [GitHub Docs：Control concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency) | workflow／jobの同時実行を制御できる | PRの古い検査停止を導入候補にし、デプロイとは分けて評価 |

行動変容についての臨床的・心理学的な有効性は検証していない。本キットの45分・2回・60秒・2週間は設計上の初期案であり、出典の研究結果に基づく保証値ではない。

## 5. 作成時のローカル判定コードの検証

実行日：2026-09-05  
実行環境：Windows／PowerShell、Node.js v24.19.0  
対象：[gate.mjs](automation/gate.mjs)、[gate.test.mjs](automation/gate.test.mjs)

実行コマンド（automationディレクトリ）：

```powershell
node --test .\gate.test.mjs
```

結果：**42 tests / 42 pass / 0 fail / 0 skipped、終了コード0**。作成担当の検証後、統合担当も同じテストを実行して確認した。CLIの実起動と3つの架空JSONによる分岐もテストに含む。

| 架空入力 | 確認できた出力 |
|---|---|
| ready-lab.json | READY_TO_CLOSE |
| repeat-lab.json | CHANGE_APPROACH |
| incident.json | COORDINATE |

主な検証対象は、重大リスクの優先、欠測・不正入力、空ゲート、未実施・失敗、古い版、NAの根拠、予算の境界、反復の境界、新事実による終了保留、入力の不要な転載防止。全出力の `assessment_only=true`、`approval=NOT_GRANTED`、`service_action=NONE` を確認した。

このテストで確認したのはローカル判定の挙動である。架空の証跡参照を実測済みの記録に置き換えない。

文書・配布内容は10ファイルを対象に確認した。Markdown 5件、JSON 3件を読み、ローカルリンク19件の参照先が存在し、JSON構文・コードフェンスの対応・文字化けの置換文字に問題がないことを確認した。これは構造確認であり、全外部リンクの到達、図の描画、利用者の読みやすさの試用までは含まない。独立した読み取りレビューでは、品質判定の集約方法と安全に保留する条件を補足した。

## 6. リポジトリへの導入範囲

2026-09-05 に、作成済みの10ファイルを `docs/work-completion/` へ配置し、文書名を英語のファイル名に整理した。README・初心者ガイド・変更管理に入口を追加し、Node.js 24で判定テストを実行する `Work completion check` workflowを追加した。判定ロジックと架空入力は作成時のものを維持する。

このworkflowは読み取り権限でテストするだけで、作業の完了承認、マージ、サーバー操作、外部通知は行わない。実際のCI結果は対象PRのheadに対応するChecksを確認する。上記の既存CI3件は導入前コミットの履歴であり、今回のPRのCI結果ではない。

## 7. 未実施の範囲

- この文書は導入用PRに含む。マージの有無はGitHubのPR状態を参照。公開サイト更新は対象外。
- ルールセットや必須チェック設定、作業タイマー、外部通知、作業記録の定期収集。判定テストのCIとは区別する。
- 実サーバーへの構築、変更、停止、復旧、SLO実測。
- 証跡参照先の存在・内容・真実性の自動照合。
- 利用者本人によるテンプレート試用、学習理解、引継ぎ受領。
- 重複確認時間や管理負担が減少したかの運用測定。

設計の受入と運用効果の受入は分ける。本人の行動変化は、試行して記録がそろうまで「未測定」とする。
