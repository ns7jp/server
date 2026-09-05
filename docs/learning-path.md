# 未経験者向け一本道ラーニングパス

> **対象**: Linux サーバー構築を初めて学ぶ人
> **ゴール**: コマンドをコピーするだけでなく、構成、確認方法、失敗時の戻し方を自分の言葉で説明する
> **安全境界**: 破棄できる Linux VM を使い、実行していない結果は必ず `NOT RUN` と記録する

## 最初の実習から始める

初めて開いた方は [初心者向け学習ガイド](beginner-learning-guide.md)を 1 本だけ開き、
app + nginx の最小起動 → 応答と認証の確認 → 計画停止・再開 → 説明まで進めます。
このページは、その実習と後続の Level 0〜5 の対応を確認するための全体地図です。
最初の実習だけで全レベルを修了したことにはしません。

| ガイドの範囲 | このページの対応 |
| --- | --- |
| 準備・Step 1〜2 | Level 0〜1 |
| Step 3〜5（2 サービスの起動、確認、手動再開、説明） | Level 2 の入口 |
| Step 6（監視全体を起動し、数値・画面・ログを確認） | Level 2〜3 |
| Ansible 適用・D-1 | 後続の Level 4〜5 |

## まずレベルを選ぶ

**必修は Level 0〜5 です。Level 6 は選択です。**

Level 5（障害対応）まで終えて、はじめてこのポートフォリオの基本構成を
「作る・確認する・直す・説明する」まで一巡できます。
Level 6 は興味や応募先に合わせて一つだけ選ぶ発展課題です。最初から全部を理解する必要はありません。

| Level | 難易度 | テーマ | 目安 | 完了条件 |
| --- | --- | --- | ---: | --- |
| 0 | 🟢 BEGINNER | 検証環境 / Linux / Git / 終了コード | 60分 | `pwd`, `cd`, `git status`, `$?` を説明できる |
| 1 | 🟢 BEGINNER | Flask と単体テスト | 60分 | pytest が成功し、`/healthz` の役割を説明できる |
| 2 | 🟢 BEGINNER | Docker Compose | 120分 | stack を起動・確認・停止し、volume を消さずに戻せる |
| 3 | 🟢 BEGINNER | Prometheus / Grafana / Loki | 120分 | metrics・可視化・logs の経路を構成図で説明できる |
| 4 | 🟢 BEGINNER | Ansible | 半日 | 初回構築と2回目 `changed=0` を証跡へ残せる |
| 5 | 🟢 BEGINNER（必修） | 障害対応と復元 | 120分 | D-1を実行し、仮説・原因・復旧・学びを記録できる |
| 6 | 🔴 ADVANCED（選択） | LVM / 3層 / L2-L3 / AWS | 1〜2日 | 選んだ1テーマの試験結果と制約を説明できる |

Level 4 の完了条件にある `changed=0` は、2回目の実行で変更が1件も起きない状態を指します。

Level 5 を🟡ではなく🟢必修としているのは、D-1 演習が難しいからではありません。
「壊して、直して、説明する」が、このパス全体のゴール（冒頭参照）そのものだからです。
Level 0〜4 だけでは、構成を作って確認するところまでしか経験できません。

## Level 0 の前に — 検証環境と本体コードを用意する

**Linux VM も Git も触ったことがない場合は、ここから始めてください。**
すでに破棄できる Ubuntu VM を用意済みで `git clone` も済んでいる場合はこの節を読み飛ばして構いません。

1. **専用の検証環境を用意する**
   - Windows 上の Hyper-V または VirtualBox で Ubuntu 24.04 の VM を新規作成し、
     再作成方法を用意します。VM の準備がまだなら、この段階で止めて構いません。
   - WSL2 を使う場合は [Microsoft 公式 WSL 導入手順](https://learn.microsoft.com/windows/wsl/install)
     を確認し、学習専用の Ubuntu を使います。既存の仕事用ディストリビューションは使いません。
     WSL2 内の Linux と Windows 本体の観測範囲は異なります。
   - 初回の入門にクラウドは不要です。AWS は Level 6 の選択課題へ分けます。
2. **このリポジトリを取得する**

   ```bash
   git clone https://github.com/ns7jp/server.git
   cd server
   ```

   `git` コマンドの意味が分からない場合は、先に
   [サーバー構築キーワード集の「Git」の項目](server-building-keywords.md#git)を読んでから戻ってください。
3. Level 0 へ進む。

## Level 0 — 道具と現在地を確認する

- **目的**: ディレクトリ、ファイル、Git、終了コードを読めるようにする。
- **前提**: 破棄できる Ubuntu 24.04 VM。業務サーバーや共有端末では実行しない。上の「Level 0 の前に」を完了済みであること。
- **操作**:

  ```bash
  pwd
  git status --short --branch
  ./scripts/learning/check-prerequisites.sh
  echo "$?"
  ```

- **期待結果**: 診断結果が `PASS / WARN / FAIL` で表示され、FAIL の直し方を読める。
- **確認問題**: 終了コード `0` と `1` の違いは何か。`WARN` を `PASS` と数えてよいか。

  <details>
  <summary>解答例</summary>

  終了コード `0` はコマンドが成功したことを示し、`0` 以外は失敗を示す。`WARN` は合格
  （`PASS`）を意味しないが、影響を理解した上で続行できる状態であり、`FAIL` とは扱いが異なる。
  `WARN` を無条件に `PASS` として数えず、内容を確認してから先へ進む。

  </details>

- **次へ進む条件**: 実施する課題の必須条件にある FAIL を解消し、WARN の影響を学習記録に書いた。解消できなければ BLOCKED と記録する。

## Level 1 — 最小のアプリを試験する

- **目的**: サーバーアプリと自動テストの関係を知る。
- **前提**: Level 0 完了、Python 3.11 または Ubuntu 24.04 標準の 3.12。
- **操作**: [初心者向け学習ガイド「小さく確認する」](beginner-learning-guide.md#2-小さく確認する)。
- **期待結果**: compile と pytest の終了コードが0になる。
- **なぜ**: `/healthz` は「プロセスが応答できるか」だけを最小限の情報で返す。
  一方 `/metrics` はCPUなどの観測値を返す。目的が違うので、公開範囲と認証も分けている。
- **確認問題**: Pythonテストの成功だけでLinux、Docker、AWSも検証済みと言えるか。

  <details>
  <summary>解答例</summary>

  言えない。pytestにはPythonアプリや文書・設定の整合検査が含まれるが、Linuxホスト、
  Docker、Ansible、AWSの動作確認をしたことにはならない。それぞれ別のLevelで
  個別に確認する。

  </details>

- **次へ進む条件**: テスト件数、日時、commit SHAを記録した。

## Level 2 — Composeで複数サービスを動かす

- **目的**: image、container、network、volumeの関係を知る。
- **前提**: Level 1 完了、診断でDocker daemonとComposeがPASS。
- **操作**: [初心者向け学習ガイド「検証環境で起動する」](beginner-learning-guide.md#3-検証環境で起動する)。
- **期待結果**: `docker compose ps` と `/healthz` が正常で、秘密値がGit追跡されない。
- **なぜ**: secret（秘密の値）を用途別に分けると、漏えいしたときの影響範囲を限定できる。
  管理portは `127.0.0.1`（ループバック。そのPCの中からだけ届くアドレス）にbindする。
  こうすれば、認証設定を誤っても外部へ直接は露出しない。
- **戻し方**: `docker compose down`。`down -v` は永続データを消すため入門では使わない。
- **次へ進む条件**: 起動と停止を一度ずつ行い、状態とログの違いを説明できる。

## Level 3 — 観測経路を説明する

- **目的**: metrics、logs、dashboard、alertの役割を分ける。
- **前提**: Level 2 の最小構成を確認済み。
- **操作**: [ガイド Step 6](beginner-learning-guide.md#6-次の実習監視を追加する)で監視全体を起動し、
  Prometheus target、Grafana dashboard、Loki log を順に確認する。
- **期待結果**: 「収集元 → 保存先 → 表示先 → 通知先」を紙またはMermaidで再現できる。
- **確認問題**: Grafanaが停止してもPrometheusの時系列は直ちに消えるか。コンテナ内
  `psutil` とhost全体のnode-exporterは何が違うか。

  <details>
  <summary>解答例</summary>

  消えない。Grafanaは可視化するだけで、収集・保存はPrometheusが担う。Grafanaが
  停止していてもPrometheusが収集済みの時系列データはそのまま残る。コンテナ内
  `psutil` はコンテナから見える値で、指標によってはホスト側の値を含む。
  全指標をコンテナ使用量と決め付けず、Linuxホスト全体はnode-exporter側で確認する。

  </details>

- **次へ進む条件**: metricsとlogsを各1件検索し、スクリーンショットまたはraw出力を保存した。

## Level 4 — Ansibleで同じ状態を再現する

- **目的**: 手作業と構成管理の違い、冪等性を理解する。
- **前提**: Level 3 完了、対象VMのsnapshotまたは再作成方法を用意済み。
- **操作**: [Ansible配備手順](deployment-ansible.md)。最初にcheck modeの限界を読む。
  check modeは、実際には変更せず、変更予定だけを表示する実行のこと。
  どこまで当てにできるかはリンク先に書かれている。
- **期待結果**: 初回 `failed=0`、2回目 `changed=0, failed=0`。
- **戻し方**: [変更・ロールバック計画](build-package/08-change-rollback-plan.md)に従い、
  直前の正常commitへ戻す。場当たり的な手修正をしない。このテンプレートは本来チーム運用
  向けのもので、「作業者/確認者」のような役割欄も含む。学習では「変更前commit SHAへ
  git/Ansibleで戻す」部分だけを参照すればよい。
- **次へ進む条件**: taskを一つ選び、「望ましい状態」と「2回目に変わらない理由」を説明できる。

## Level 5 — 壊して、直して、説明する

- **目的**: 推測で設定を変えず、状態 → ログ → 通信 → 設定の順に事実を集める。
- **前提**: Level 4完了。正常時の結果を保存済み。
  ここでいう結果とは、障害を起こす前の、正常に動いている状態を確認したコマンドの出力のこと。
  障害時の出力と見比べるため、そのまま残しておく。
- **操作**: [D-1 process down演習](drills/D-1-process-down.md)。
- **期待結果**: 停止、検知、自動復旧、正常化を観測し、RTOを実測する。
- **記録**: 調査の過程（現象、影響、仮説、コマンド、根本原因、暫定・恒久対応、再発防止）は
  [トラブルシューティング一次記録](evidence/templates/troubleshooting-worklog.md)（
  [記入例](evidence/templates/troubleshooting-worklog-example.md)あり）へ、RTO実測とタイムラインの
  要約は[復旧演習記録テンプレート](drill-template.md)へ書く。役割が異なる2つのテンプレートで、
  どちらか一方だけで済ませない。
- **次へ進む条件**: 3分で「目的・構成・障害・復旧・未実施」を説明できる。

## Level 6 — 発展テーマを一つ選ぶ

| 選択 | 教材 | 身につける観点 |
| --- | --- | --- |
| LVM | [B-1](drills/B-1-lvm.md) | デバイス安全装置、拡張、再実行 |
| Web/AP/DB | [3層ラボ](../labs/three-tier/README.md) | 層分離、依存先障害、DB復元 |
| L2/L3 | [routing lab](../labs/routing/README.md) | route、forward、packet capture |
| AWS | [AWS設計](aws-architecture.md) / [AWSコスト計画](cost-report.md) | IaC、責務分離、費用、destroy |

各テーマを日本語で言い換えると次のとおりです。

- LVM: ディスクの容量管理
- Web/AP/DB: Web・AP・DBの3つに分けた構成
- L2/L3: ネットワークの切り分け
- AWS: クラウドの構成をコードで書く

AWSのコードが存在しても、実アカウントでの `terraform apply / destroy` を実施していなければ
`NOT RUN`です。[AWSコスト計画](cost-report.md)の費用上限（月額試算とBudgets閾値）、削除手順、
資格情報の管理を先にレビューしてください。

## 共通の学習記録

個別実習は [初心者実習記録テンプレート](evidence/templates/beginner-practice-record.md)をコピーして使えます。
下記はレベル全体の振り返り用です。

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

最後の項目は、自分で理解した範囲と、支援を受けた範囲を分けて説明できるようにするための欄です。

## 進捗トラッカー

Level 0〜6を横断して、今どこまで終えたかを一望するための表です。各Levelの
「共通の学習記録」を書いたら、ここにも日付だけ転記してください。

| Level | テーマ | 着手日 | 完了日 | 判定 |
| --- | --- | --- | --- | --- |
| 0 | 検証環境 / Linux / Git / 終了コード | | | PASS / FAIL / BLOCKED / NOT RUN |
| 1 | Flask と単体テスト | | | PASS / FAIL / BLOCKED / NOT RUN |
| 2 | Docker Compose | | | PASS / FAIL / BLOCKED / NOT RUN |
| 3 | Prometheus / Grafana / Loki | | | PASS / FAIL / BLOCKED / NOT RUN |
| 4 | Ansible | | | PASS / FAIL / BLOCKED / NOT RUN |
| 5 | 障害対応と復元（D-1） | | | PASS / FAIL / BLOCKED / NOT RUN |
| 6 | 選択した発展テーマ（　　　） | | | PASS / FAIL / BLOCKED / NOT RUN |

## 修了チェック

- [ ] 必修Level 0〜5（Level 4までの構築・確認と、Level 5の障害対応）を順に完了した
- [ ] 正常時・障害時・復旧後の一次記録を残した。想定外の失敗がなければ「なし」と書き、FAILやBLOCKEDを創作していない
- [ ] 秘密値や実IPをリポジトリへcommitしていない
- [ ] 実行環境とcommit SHAを証跡に残した
- [ ] 未実施を `NOT RUN` と説明できる
- [ ] Level 5の障害対応を含め、3分説明を録画または第三者へ実施した
