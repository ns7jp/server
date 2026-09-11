# server — Linux サーバー構築・監視の学習ポートフォリオ

[![Python check](https://github.com/ns7jp/server/actions/workflows/python-check.yml/badge.svg)](https://github.com/ns7jp/server/actions/workflows/python-check.yml)
[![Full-stack Ansible E2E](https://github.com/ns7jp/server/actions/workflows/full-stack-e2e.yml/badge.svg)](https://github.com/ns7jp/server/actions/workflows/full-stack-e2e.yml)

**「サーバーを作る → 動作を確かめる → 異常を調べる → 元へ戻す」を学ぶ、未経験サーバー構築エンジニア志望者の個人学習ラボです。**
業務での構築・運用経験を示すものではありません。コード・手順・試験記録をつなぎ、確認できた範囲を自分の言葉で説明することを目指します。

## 本人が手元の VM で確認したこと

採用向けには、まず次の実行記録をご覧ください。**AI の手順案内を受けて本人が操作し、結果画像を残した実習**です。独力での再構築・説明を確認した記録とは区別しています。

| 実施日 | 本人の操作と確認結果 | この記録の限界 |
| --- | --- | --- |
| 2026-09-07〜08 | [Ubuntu 初期構築](docs/evidence/2026-09-08-lab-base01-initial-build.md)：固定 IP、SSH 鍵認証、sudo、UFW、時刻同期、自動更新、設定不備からの復旧 | OS 単体の演習。監視案件全体の受け入れではない |
| 2026-09-08 | [Docker 最小構成](docs/evidence/2026-09-08-lab-base01-compose-practice.md)：app/nginx 起動、未認証 401・認証あり 200、計画停止・手動再開 | 2 サービスに限定。手動再開は自動復旧試験とは別 |
| 2026-09-08 | [数値監視](docs/evidence/2026-09-08-lab-base01-monitoring-practice.md)：Prometheus/Grafana で収集状態の 1→0→1。[ログ検索](docs/evidence/2026-09-08-lab-base01-loki-practice.md)：目印付き Nginx ログ 2 件 | メモリ 2 GiB の VM で、それぞれ 5 / 6 サービスを分けて起動。全構成の同時稼働・通知は未実施 |
| 2026-09-08 | [バックアップ復元](docs/evidence/2026-09-08-lab-base01-restore-practice.md)：Loki の別名ボリュームから同じログ 2 件を読取り。[D-1](docs/evidence/2026-09-08-lab-base01-d1-practice.md)：再起動回数 0→1、HTTP 復帰の計測 2 秒、後続 healthy 確認 | 復元は同一 VM・同一仮想ディスク内。2 秒は 1 回の HTTP 復帰計測で、監視通知や全機能の復旧時間ではない |
| 2026-09-08〜09 | [Ansible 入門](docs/evidence/2026-09-08-lab-base01-ansible-intro-practice.md)、[変更予測と適用](docs/evidence/2026-09-09-lab-base01-check-diff-practice.md)、[切り戻し](docs/evidence/2026-09-09-lab-base01-rollback-practice.md)、[入力検証](docs/evidence/2026-09-09-lab-base01-validation-practice.md)：再実行の changed=0、不正値の拒否と本文維持 | ホーム内の演習ファイルが対象。OS 全体への適用、実ポート待受の確認ではない |
| 2026-09-09〜10 | [Git の保存・履歴・除外](docs/evidence/2026-09-10-lab-base01-git-practice.md)、[マージ・競合解消・abort](docs/evidence/2026-09-10-lab-base01-git-merge-practice.md)：元の main と clean 状態へ復帰 | VM 内の別の演習リポジトリ。GitHub の PR マージや Ansible 反映ではない |

次は [小さな構成の再起動・24 時間点検・別 VM 復元・引き渡し](docs/partial-lab-continuation.md)へ進みます。**この続編は手順を準備した段階で、新しい実機結果は `NOT RUN`** です。過去の記録を上書きせず、実行した段階だけ追記します。

## 未経験から始める方へ

**最初に開く文書は [初心者向け学習ガイド](docs/beginner-learning-guide.md) です。**
最初は Linux 上の `app`（応答するアプリ）と `nginx`（通信の入口）の **2 サービス**だけを動かします。監視と Ansible は、その後に追加して学びます。

| 順番 | やること | できたかの確認 |
| --- | --- | --- |
| 1. 見る | ガイドの構成図と 5 つの用語を読む | 入口とアプリの役割を言える |
| 2. 動かす | 専用 Linux 検証環境で最小構成を起動する | `app` と `nginx` が起動する |
| 3. 確認する | 応答と認証の有無を比べる | health は `200`、認証なしの画面は `401` |
| 4. 壊して直す | 正常時の記録後に計画停止・再開する | 停止前・停止中・復旧後の違いを記録する |
| 5. 説明する | [学習記録](docs/evidence/templates/beginner-practice-record.md)を基に話す | 自分で確認したことと未実施を分けて言える |

コードの取得と前提診断は **Linux の Bash、取得した `server` ディレクトリ内**で行います。Linux の準備がまだなら、ガイドの「実行場所と準備」から始めてください。

```bash
git clone https://github.com/ns7jp/server.git
cd server
bash scripts/learning/check-prerequisites.sh --minimal
```

環境がまだなくても、ガイドの図と HTTP の期待値を読む 10 分の練習から始められます。`--minimal` は最初の 2 サービス用の診断です。`FAIL` が出たら表示された `NEXT` を確認します。実習の終了時は同じ場所で `docker compose down` を使います。操作前の予想・実結果・自分の説明を記録し、後日の再現と分けて振り返ります。

## 構成

```mermaid
flowchart LR
    Browser["利用者のブラウザ"] -->|"127.0.0.1:8080"| Nginx["nginx：入口"]
    Nginx --> App["app：状態を返す"]
    Prometheus["Prometheus：数値を集めて保存"] -->|"定期取得"| App
    Prometheus -->|"定期取得"| Node["node-exporter：Linux の数値"]
    Grafana["Grafana：グラフ表示"] -->|"問い合わせ"| Prometheus
```

**最初は左の 3 要素だけで考えます。** Linux は動作の土台、Docker Compose は部品の起動係です。上の矢印はリクエストの方向です。Grafana が Prometheus に問い合わせて数値を受け取ります。ログ収集と通知まで含む構成は [詳細な構成図](docs/architecture.md) にあります。

コンテナ内の `psutil` は実行環境から見える値を返します。すべてがコンテナの使用量だけを表すとは限らないため、Linux ホストの監視は `node-exporter` 側で確認します。

<a id="3分で説明するなら"></a>
## 30 秒で説明するなら

> サーバーを構築し、動作確認と障害対応まで学ぶ個人ラボです。Linux 上でアプリを動かし、応答と認証を確認します。次に Prometheus で数値を集め、Grafana で見えるようにします。実際に行った操作と結果を記録し、未実施の内容も分けて説明します。

これはプロジェクトの紹介例です。「私は構築・検証しました」と話す範囲は、自分の実行記録がある項目に限ります。[3 分説明の型・想定質問・復習方法](docs/beginner-learning-guide.md#5-説明して定着させる)で練習できます。

## 採用ご担当者向け：最初に見る 4 点

1. [構成と設計判断](docs/design-decisions.md)：何を作り、なぜその構成にしたか。
2. [Linux 構築案件パック](docs/build-package/README.md)：要件 → 設計値 → 構築 → 試験 → 証跡 → 運用 → 変更の文書。
3. [検証証跡台帳](docs/evidence/README.md)：実行日時・環境・対象 commit・結果・未実施の範囲。
4. [失敗から学んだ事例](docs/lessons-learned.md)：想定が外れた原因、修正と再発防止。

[保存済み証跡のデモ](https://ns7jp.github.io/demo.html)は 2026-08-18/19 の画像・ログを再構成した閲覧用リプレイで、実操作の連続録画ではありません。

## 実装と検証の範囲

| 区分 | このリポジトリで示せるもの | 境界 |
| --- | --- | --- |
| 実装済み | 認証付き Flask アプリ、Compose、監視、Ansible、復旧手順 | コードが存在することと各環境で動作することは別 |
| 記録済みの CI 実測 | [2026-08-22 の E2E](docs/evidence/2026-08-22-full-stack-e2e.md)：一括構築・冪等性・復旧・復元など 23 ID PASS | 当該 commit の使い捨て Ubuntu runner。最新差分や永続ホストの保証には使わない |
| 記録済みの VM 実測 | [2026-09-04 Ubuntu の基盤構築](docs/evidence/2026-09-04-ansible-foundation-build.md)と[AlmaLinux の基盤構築](docs/evidence/2026-09-04-ansible-foundation-el9-build.md)：`foundation.yml` の `common` / `docker` role 適用・冪等性 | 監視全体の `site.yml` とは別。AlmaLinux は再利用 VM で、新規構築・最小公開の証明には未到達 |
| 記録済みの手作業構築 | [2026-09-07〜08 lab-base01](docs/evidence/2026-09-08-lab-base01-initial-build.md)：Hyper-V 上の Ubuntu へ固定 IP・SSH 鍵認証・sudo・UFW・時刻同期・自動更新を手作業で設定し、設定不備を起こして表示とログを照合し復旧。判定は PASS 14 / PASS-ADAPTED 4 / PARTIAL 2 / NOT RUN 1、ほかに T-14 代替演習 1 件 PASS | Ansible も本リポジトリのコードも使わない OS 単体の演習で、`SM-LAB-001` の受け入れではない。AI が手順案内・画像読取り・記録編集を支援。「教材どおり 21/21 PASS」ではない。独力での再現、第三者への引き渡し、長期稼働は対象外 |
| 記録済みの手作業アプリ起動 | [2026-09-08 lab-base01 の Docker 最小構成](docs/evidence/2026-09-08-lab-base01-compose-practice.md)：同じ VM に Docker Engine / Compose を導入し、指定 SHA の作業ツリーで pytest 167 件、app と nginx の 2 サービス起動、未認証 401 と Basic 認証つき 200、Nginx の計画停止と手動再開、撤去までを CP-01〜13 で PASS | 起動したのは app と nginx の 2 つだけ。Prometheus / Grafana / Alloy / Loki / Alertmanager の起動、Ansible 適用、D-1 自動復旧、AWS は `NOT RUN`。表示された停止 0.7 秒などは Docker CLI の表示で、利用者視点の RTO ではない |
| 未実施 | AWS の実適用・削除、Slack 実配信、監視ラボの長期稼働、D-2 ホスト障害復元 | `NOT RUN`。[実測計画](docs/real-environment-validation-plan.md)を参照 |

実行者が本人・CI・AI 支援環境のどれかも各証跡で区別します。既存の PASS を、読む人自身の習得・実行実績へ転記しません。

## ドキュメント

| 読みたいこと | 開く文書 |
| --- | --- |
| 最初の実習を進める | [初心者向け学習ガイド](docs/beginner-learning-guide.md) |
| 確認を繰り返しすぎず安全に作業を閉じる | [手放して進める運用キット](docs/work-completion/README.md)（詳細設計・記録テンプレート・判定サンプル） |
| 次の学習範囲を決める | [一本道ラーニングパス](docs/learning-path.md)（Level 0〜5 と選択式 Level 6） |
| 言葉の意味をたとえと覚え方で覚える | [サーバー基礎用語集（やさしい版）](docs/server-basics-glossary/README.md)（408 語・五十音さくいん付き） |
| 知らない言葉を、このリポジトリのファイルと結び付けて調べる | [サーバー構築キーワード集](docs/server-building-keywords.md) |
| コマンド・結果・説明を記録する | [初心者実習記録テンプレート](docs/evidence/templates/beginner-practice-record.md) |
| 要件や設計書の読み方を知る | [案件パック初心者ガイド](docs/build-package/beginner-guide.md) |
| 機能・OS・AWS・各案件パックを探す | [実装・設計・教材の詳細一覧](docs/project-reference.md) |

## AI の利用について

文書作成、コード生成、レビュー、検証補助に AI を使っています。本人の理解や実施を代行した実績として扱いません。学習記録には **自分で実行・説明できる範囲、AI に支援された範囲、未確認の範囲**を残します。[利用範囲の詳細](docs/project-reference.md#ai-の利用について)も公開しています。

<details>
<summary>以前の README の節から探す</summary>

<a id="実装したこと"></a><a id="ダッシュボード機能"></a><a id="構成管理ansible"></a><a id="クラウド配備aws--terraform"></a><a id="slo--エラーバジェット"></a><a id="復旧演習"></a><a id="変更管理"></a><a id="ログ集約"></a><a id="セキュアな初期値"></a><a id="ディレクトリ構成"></a><a id="対応-os"></a><a id="手を動かす演習b-シリーズ"></a><a id="現在の制約と次の拡張"></a><a id="まず読む文書"></a><a id="発展的な設計将来構想"></a>

各機能・構成・演習・制約は [詳細一覧](docs/project-reference.md)へ移しました。

<a id="docker-compose-で起動"></a><a id="アプリ単体で起動"></a><a id="テスト"></a>

起動と確認は [初心者向け学習ガイド](docs/beginner-learning-guide.md)、配備方法の比較は [詳細一覧](docs/project-reference.md)を参照してください。

</details>

## License

[MIT License](LICENSE)

## Author

島田則幸 (Noriyuki Shimada)
