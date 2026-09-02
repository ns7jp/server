# Linux サーバー構築案件パック

**一言でいうと**: Ubuntu Server の検証用 VM 1 台に監視のしくみを構築し、引き渡すまでの書類一式です。

このディレクトリは `server-monitor` を一つの小規模サーバー構築案件と見立て、設計から引き渡しまでの成果物を工程順にまとめたものです。「案件パック」とは、1 つの構築案件で実際に作る書類をひとまとめにしたものを指します。

案件は「何を作るか決める → 設計する → 作る → 試験する → 報告して渡す」の順に進みます。工程ごとに書類が分かれるため、文書は 00 から 11 までの 12 個あります。番号順に読めば、そのまま案件の流れをたどれます。

本文書にある「予定値」と、実機で取得した「結果」は分けて管理します。予定と結果を混ぜないことが、この案件パックの基本方針です。

| 案件 ID | 対象 | 現在の引き渡し判定 |
| --- | --- | --- |
| `SM-LAB-001` | Ubuntu Server 24.04 LTS の検証用 VM 1 台 | **`NOT READY`** — 引き渡し対象ホストが未指定で、対象ホストの必須試験が `NOT RUN` |

```mermaid
flowchart LR
    R["要件 ID 00"] --> D["基本・詳細設計 01-04"]
    D --> B["構築・変更 05 / 08 / 10"]
    B --> T["試験 ID 06 / 09"]
    T --> E["日付付き実測証跡 docs/evidence"]
    E --> W["作業結果報告 11"]
    W --> H["引き渡し判定 07"]
```

次の 3 つは、それぞれ別の状態です。ひとまとめにしないでください。

- 文書が「作成済み」であること
- 使い捨て runner（実行のたびに作って捨てる一時的な実行環境）で `PASS` したこと
- 特定の引き渡し対象ホストで受け入れが完了したこと

最終判定は [作業結果・引き渡し報告書](11-work-result-report.md)と[引き渡しチェックリスト](07-handover-checklist.md)を使います。

### 初心者の方はまずこちら

`NFR`（非機能要件。速さ・止まりにくさ・安全性など、機能以外の要求）、`Gate`（次の工程へ
進んでよいかを判断する関門）、案件 ID のような言葉が初見の場合は、12 文書を読み始める前に
[案件パック 初心者ガイド](beginner-guide.md)で、案件パックとは何か、各文書の役割、
読む順とかかる時間の目安を確認してください。

## 最短レビュー順

1. [要件定義書](00-requirements.md) — 何を作り、何を作らないか。どうなれば合格かを決める（要件 ID と受け入れ条件を定義）
2. [基本設計書](01-basic-design.md) — 全体の構成と、非機能（NFR）の設計方針
3. [パラメータシート](03-parameter-sheet.md) — 実際に入力する設定値の一覧（OS・SSH・FW・Docker・監視）
4. [構築手順書](05-build-procedure.md) — Ubuntu 1 台を Ansible で組み立てる手順
5. [試験仕様書・結果票](06-test-specification.md) — 何を確かめれば合格かと、実測結果を書き込む用紙
6. [ネットワーク実機検証手順](09-network-validation-procedure.md) — 実機で通信できるかの確認（ping / DNS / route / listen / HTTP / packet / FW）
7. [作業結果・引き渡し報告書](11-work-result-report.md) — 計画対実績（予定と実際の比較）、試験の集計、差異、残存リスク（残ったままの危険）、完了判定
8. [検証証跡台帳](../evidence/README.md) — 実測済み・未実測の境界（どこまで実機で確かめ、どこからが未確認か）

## 成果物一覧

| 工程 | 成果物 | 状態 |
| --- | --- | --- |
| 要件定義 | [00-requirements.md](00-requirements.md) | 作成済み |
| 要件・基本設計 | [01-basic-design.md](01-basic-design.md) | 作成済み |
| 詳細設計 | [02-detailed-design.md](02-detailed-design.md) | 作成済み |
| パラメータ設計 | [03-parameter-sheet.md](03-parameter-sheet.md) | 作成済み |
| ネットワーク設計 | [04-network-ip-plan.md](04-network-ip-plan.md) | 作成済み |
| 構築 | [05-build-procedure.md](05-build-procedure.md) | 手順作成済み・実機結果は証跡台帳で管理 |
| 試験 | [06-test-specification.md](06-test-specification.md) | 仕様作成済み・未実施欄は `NOT RUN` |
| 引き渡し | [07-handover-checklist.md](07-handover-checklist.md) | 作成済み |
| 変更・復旧 | [08-change-rollback-plan.md](08-change-rollback-plan.md) | 計画・記録様式作成済み。使い捨てrunnerのGit rollbackは[2026-08-23にPASS](../evidence/2026-08-23-change-CI-GIT-ROLLBACK.md)、引き渡し対象hostでは`NOT RUN` |
| ネットワーク実機検証 | [09-network-validation-procedure.md](09-network-validation-procedure.md) | ephemeral runnerは[2026-08-22にPASS](../evidence/2026-08-22-full-stack-e2e.md)。独立した引き渡し対象host/管理端末は`NOT RUN` |
| 立ち上げ・受け入れ | [10-host-bringup-and-acceptance.md](10-host-bringup-and-acceptance.md) | 恒久ホストを用意してから証跡が出るまでの最短手順。`acceptance-check.sh` で結果票を自動生成する |
| 作業結果報告 | [11-work-result-report.md](11-work-result-report.md) | 原本作成済み。対象ホストごとの実績は日付付き evidence へ複製して記録 |
| ネットワーク結果票 | [実機検証テンプレート](../evidence/templates/network-host-validation.md) | テンプレート作成済み |
| 一次切り分け記録 | [トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md) | テンプレート作成済み |

## 工程ゲート

| Gate | 完了条件 | 現在の状態 |
| --- | --- | --- |
| G0 要件確定 | 要件 ID、対象、対象外、受け入れ条件が合意済み | 文書作成済み。実案件での承認は `NOT SET` |
| G1 設計確定 | 基本・詳細・パラメータ・ネットワーク設計のレビュー完了 | 文書作成済み。実案件での承認は `NOT SET` |
| G2 構築完了 | 対象ホストへの初回適用が成功し、実績値と差異を記録 | ephemeral runner は既存証跡あり。引き渡し対象ホストは `NOT RUN` |
| G3 試験完了 | 対象ホストの必須 ID がすべて `PASS` | `NOT READY` |
| G4 作業完了 | 作業結果報告書に実績、障害、差異、残存リスクを記録 | 原本のみ。実案件報告は `NOT SET` |
| G5 引き渡し | 受領者、日時、秘密値受け渡し、未解決事項を記録 | `NOT READY` |

この作業ツリーで実行できた Windows 静的・単体検証と、実行できなかった Linux runtime の境界は [2026-08-27 の日付付き証跡](../evidence/2026-08-27-local-static-validation.md)に記録しています。

## 検証環境

基準環境は Ubuntu Server 24.04 LTS の単一ホストです。構成コードは Ubuntu 22.04 LTS にも対応しますが、両バージョンでの実測を意味しません。AWS 構成は別の発展構成であり、実際の `apply / destroy` が記録されるまでは設計・コード実装済みとして扱います。

二セグメントDockerラボとephemeral runner E2Eの実測はありますが、独立した引き渡し対象VM・
管理端末・組織DNSを確認した証拠ではありません。その対象host側は日付付きの
[ネットワーク結果票](../evidence/templates/network-host-validation.md)が保存されるまで`NOT RUN`とします。

## 完了の定義

次をすべて満たした時点で「構築・試験完了」とします。

- `ansible/playbooks/site.yml` が `failed=0` で終了する
- 2 回目の適用が `changed=0` になる
- [試験仕様書](06-test-specification.md)の必須項目がすべて `PASS`
- Grafana、Loki、Alertmanager、D-1 復旧演習の証跡が commit SHA 付きで保存される
- 未解決事項、秘密値の受け渡し方法、ロールバック方法が引き渡し記録に残る
- 実ホストの名前解決、経路、待受、HTTP 疎通、UFW を確認し、実行出力を保存する
- [作業結果・引き渡し報告書](11-work-result-report.md)の計画対実績、試験集計、差異、残存リスク、受領判定を記入する

