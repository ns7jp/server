# 未経験者向け一本道ラーニングパス

> **対象**: Linux サーバー構築を初めて学ぶ人
> **ゴール**: コマンドをコピーするだけでなく、構成、確認方法、失敗時の戻し方を自分の言葉で説明する
> **安全境界**: 破棄できる Linux VM を使い、実行していない結果は必ず `NOT RUN` と記録する

## まずレベルを選ぶ

**Level 0〜4 が入門の必修範囲**です。Level 5 まで終えれば、このポートフォリオの
基本構成を「作る・確認する・直す・説明する」まで一巡できます。Level 6 は興味や応募先に
合わせて一つ選ぶ発展課題であり、最初から全部理解する必要はありません。

| Level | 難易度 | テーマ | 目安 | 完了条件 |
| --- | --- | --- | ---: | --- |
| 0 | 🟢 BEGINNER | Linux / Git / 終了コード | 60分 | `pwd`, `cd`, `git status`, `$?` を説明できる |
| 1 | 🟢 BEGINNER | Flask と単体テスト | 60分 | pytest が成功し、`/healthz` の役割を説明できる |
| 2 | 🟢 BEGINNER | Docker Compose | 120分 | stack を起動・確認・停止し、volume を消さずに戻せる |
| 3 | 🟢 BEGINNER | Prometheus / Grafana / Loki | 120分 | metrics・可視化・logs の経路を構成図で説明できる |
| 4 | 🟢 BEGINNER | Ansible | 半日 | 初回構築と2回目 `changed=0` を証跡へ残せる |
| 5 | 🟡 INTERMEDIATE | 障害対応と復元 | 120分 | D-1を実行し、仮説・原因・復旧・学びを記録できる |
| 6 | 🔴 ADVANCED | LVM / 3層 / L2-L3 / AWS | 1〜2日 | 選んだ1テーマの試験結果と制約を説明できる |

## Level 0 — 道具と現在地を確認する

- **目的**: ディレクトリ、ファイル、Git、終了コードを読めるようにする。
- **前提**: 破棄できる Ubuntu 24.04 VM。業務サーバーや共有端末では実行しない。
- **操作**:

  ```bash
  pwd
  git status --short --branch
  ./scripts/learning/check-prerequisites.sh
  echo "$?"
  ```

- **期待結果**: 診断結果が `PASS / WARN / FAIL` で表示され、FAIL の直し方を読める。
- **確認問題**: 終了コード `0` と `1` の違いは何か。`WARN` を `PASS` と数えてよいか。
- **次へ進む条件**: FAIL を放置せず、理由を学習記録に書いた。

## Level 1 — 最小のアプリを試験する

- **目的**: サーバーアプリと自動テストの関係を知る。
- **前提**: Level 0 完了、Python 3.9以上。
- **操作**: [初心者向け学習ガイド「小さく確認する」](beginner-learning-guide.md#2-小さく確認する)。
- **期待結果**: compile と pytest の終了コードが0になる。
- **なぜ**: `/healthz` は「プロセスが応答可能か」を最小限の情報で返す。CPUなどの
  観測値を返す `/metrics` とは公開範囲と認証が異なる。
- **確認問題**: Pythonテストの成功だけでLinux、Docker、AWSも検証済みと言えるか。
- **次へ進む条件**: テスト件数、日時、commit SHAを記録した。

## Level 2 — Composeで複数サービスを動かす

- **目的**: image、container、network、volumeの関係を知る。
- **前提**: Level 1 完了、診断でDocker daemonとComposeがPASS。
- **操作**: [初心者向け学習ガイド「検証環境で起動する」](beginner-learning-guide.md#3-検証環境で起動する)。
- **期待結果**: `docker compose ps` と `/healthz` が正常で、秘密値がGit追跡されない。
- **なぜ**: secretを用途別に分けると漏えい時の影響範囲を限定できる。管理portを
  `127.0.0.1` にbindするのは、認証設定を誤っても外部へ直接露出させないため。
- **戻し方**: `docker compose down`。`down -v` は永続データを消すため入門では使わない。
- **次へ進む条件**: 起動と停止を一度ずつ行い、状態とログの違いを説明できる。

## Level 3 — 観測経路を説明する

- **目的**: metrics、logs、dashboard、alertの役割を分ける。
- **前提**: Level 2 完了。
- **操作**: [構成図](architecture.md)を開き、Prometheus target、Grafana dashboard、
  Loki logを順に確認する。
- **期待結果**: 「収集元 → 保存先 → 表示先 → 通知先」を紙またはMermaidで再現できる。
- **確認問題**: Grafanaが停止してもPrometheusの時系列は直ちに消えるか。コンテナ内
  `psutil` とhost全体のnode-exporterは何が違うか。
- **次へ進む条件**: metricsとlogsを各1件検索し、スクリーンショットまたはraw出力を保存した。

## Level 4 — Ansibleで同じ状態を再現する

- **目的**: 手作業と構成管理の違い、冪等性を理解する。
- **前提**: Level 3 完了、対象VMのsnapshotまたは再作成方法を用意済み。
- **操作**: [Ansible配備手順](deployment-ansible.md)。最初にcheck modeの限界を読む。
- **期待結果**: 初回 `failed=0`、2回目 `changed=0, failed=0`。
- **戻し方**: [変更・ロールバック計画](build-package/08-change-rollback-plan.md)に従い、
  直前の正常commitへ戻す。場当たり的な手修正をしない。
- **次へ進む条件**: taskを一つ選び、「望ましい状態」と「2回目に変わらない理由」を説明できる。

## Level 5 — 壊して、直して、説明する

- **目的**: 推測で設定を変えず、状態 → ログ → 通信 → 設定の順に事実を集める。
- **前提**: Level 4完了。正常時の結果を保存済み。
- **操作**: [D-1 process down演習](drills/D-1-process-down.md)。
- **期待結果**: 停止、検知、自動復旧、正常化を観測し、RTOを実測する。
- **記録**: [トラブルシューティング一次記録](evidence/templates/troubleshooting-worklog.md)へ
  現象、影響、仮説、コマンド、根本原因、暫定・恒久対応、再発防止を書く。
- **次へ進む条件**: 3分で「目的・構成・障害・復旧・未実施」を説明できる。

## Level 6 — 発展テーマを一つ選ぶ

| 選択 | 教材 | 身につける観点 |
| --- | --- | --- |
| LVM | [B-1](drills/README.md) | デバイス安全装置、拡張、再実行 |
| Web/AP/DB | [3層ラボ](../labs/three-tier/README.md) | 層分離、依存先障害、DB復元 |
| L2/L3 | [routing lab](../labs/routing/README.md) | route、forward、packet capture |
| AWS | [AWS設計](aws-architecture.md) | IaC、責務分離、費用、destroy |

AWSのコードが存在しても、実アカウントでの `terraform apply / destroy` を実施していなければ
`NOT RUN`です。費用上限、削除手順、資格情報の管理を先にレビューしてください。

## 共通の学習記録

```text
日付 / commit SHA / 実行者:
環境（OS、VM/VPS/CI、tool version）:
レベルと目的:
実行コマンド:
期待結果 / 実測結果:
判定: PASS / FAIL / BLOCKED / NOT RUN
分かったこと:
失敗と仮説:
戻し方を実行した結果:
次に試すこと:
AI・外部情報を使った範囲:
```

## 修了チェック

- [ ] 必修Level 0〜4を順に完了した
- [ ] PASSだけでなくFAILまたはBLOCKEDの一次記録を1件残した
- [ ] 秘密値や実IPをリポジトリへcommitしていない
- [ ] 実行環境とcommit SHAを証跡に残した
- [ ] 未実施を `NOT RUN` と説明できる
- [ ] 3分説明を録画または第三者へ実施した
