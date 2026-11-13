# 実習一覧と検証範囲

[作品の概要](../README.md) / [全件の検証証跡台帳](evidence/README.md) / [実装・設計・教材](project-reference.md)

README に掲載した代表事例の背景と、従来の実習一覧・CI の確認範囲をまとめています。
個々の実施日・環境・実行者を区別して読み、別々の演習を全構成の合格として合算しません。新しい記録は[検証証跡台帳](evidence/README.md)から確認できます。

## 手元の VM で私が確認したこと

下表は、2026 年 9〜10 月に **AI の手順案内を受けて、私が手元の Hyper-V 上の VM を操作し、結果を画面で確認した実習**の一覧です。

| 実施日 | 私の操作と確認結果 |
| --- | --- |
| 2026-09-01〜02 | [AD の構築・試験](evidence/2026-09-01-ad-build-validation.md)：Windows Server 2022 評価版の `ad-dc01`（VM 1 台）で AD DS（ドメインの認証基盤）を構築し、試験仕様書のフェーズ 1 必須 31 項目がすべて PASS。手順書・設計書の欠陥 6 件を実機で見つけて修正 |
| 2026-09-02 | [System State 復元](evidence/2026-09-02-ad-restore-drill.md)：非権威復元で、バックアップ後に作った目印の OU が消えることを確認。復元処理 15 分 29 秒、復旧全体は約 40 分（うち約 18 分は `safeboot` 解除漏れによるやり直し）。当日見落とした SYSVOL の欠損は翌日に訂正。唯一の DC なのに `-authsysvol`（SYSVOL の権威復元）を付けずに復元しており、手順書は 2026-09-28 に直した（実機では未検証） |
| 2026-09-03〜04 | [2 台目の DC と複製](evidence/2026-09-03-ad-second-dc-replication.md)：複製の失敗 0/5、遅延 17.8 秒。GPO（グループポリシー）が届かない原因が SYSVOL から欠けた `gpt.ini` であることを突き止め、手書きで再作成して適用を再開（応急処置。パスワードポリシーの正本である `GptTmpl.inf` は欠けたまま。欠損は前日の復元を `-authsysvol` なしで行ったことが最有力の仮説で、未確認）。[計画停止](evidence/2026-09-03-ad-dc-outage-drill.md)：1 台を止めても DNS・LDAP・Kerberos が継続し、復帰後の収束は 18 分 31 秒。[FSMO 奪取](evidence/2026-09-04-ad-fsmo-seize.md)：正常停止した 1 台を失った想定で、残った DC へ FSMO 役割（特定の DC だけが担う管理役割）を奪取し、`ntdsutil` で古い DC の情報を削除 |
| 2026-09-07〜08 | [WSUS の構築](evidence/2026-09-07-wsus-build-validation.md)：更新配信サーバー `wsus-01` をドメインに参加させて構築。必須 28 項目中 26 PASS / 1 FAIL / 1 期待結果未達で、判定は FAIL。翌日、[残った 2 件の原因](evidence/2026-09-08-wsus-sit04-sit06-root-cause.md)を実機で特定し、手順書を修正（SIT-06 は承認ルールの分類・製品が 0 件で保存され、「絞り込みなし」と解釈されていた。修正後の通し再試験は未実施） |
| 2026-09-07〜08 | [Ubuntu 初期構築](evidence/2026-09-08-lab-base01-initial-build.md)：固定 IP、SSH 鍵認証、sudo、UFW、時刻同期、自動更新を手作業で設定し、わざと起こした設定不備から復旧（OS 単体の演習） |
| 2026-09-08 | [Docker 最小構成](evidence/2026-09-08-lab-base01-compose-practice.md)：app と nginx の 2 サービスを起動し、未認証 401・認証あり 200、計画停止・手動再開を確認 |
| 2026-09-08 | [数値監視](evidence/2026-09-08-lab-base01-monitoring-practice.md)：Prometheus / Grafana で収集状態の 1→0→1。[ログ検索](evidence/2026-09-08-lab-base01-loki-practice.md)：目印付き Nginx ログ 2 件（メモリ 2 GiB の VM で、それぞれ 5 / 6 サービスを分けて起動） |
| 2026-09-08 | [バックアップ復元](evidence/2026-09-08-lab-base01-restore-practice.md)：Loki の別名ボリューム（同じ VM 内）から同じログ 2 件を読取り。[D-1](evidence/2026-09-08-lab-base01-d1-practice.md)：アプリの自動再起動で再起動回数 0→1、HTTP 復帰 2 秒（1 回の計測）、その後 healthy を確認 |
| 2026-09-30 | [新しい VM と SSH 鍵認証](evidence/2026-09-30-ubuntu-practice01-ssh-key-auth.md)：新しい Ubuntu VM（`ubuntu-practice01`）を用意し、公開鍵認証が失敗したときに、登録した鍵の各行の先頭に余分な文字（BOM）と行末の CR があることを確認。修正後の接続成功は本人の報告だけで、成功画面は未採録 |
| 2026-10-01 | [Docker 導入と Nginx の手動再開](evidence/2026-10-01-ubuntu-practice01-nginx-manual-recovery.md)：同じ VM に Docker を入れ、app と nginx で healthz 200・未認証 401・認証あり 200、nginx の計画停止中の接続失敗と手動再開後の 200 を確認（画像はリポジトリ未収録） |

Ansible と Git の小さな練習（2026-09-09〜15）の記録は、[練習ログ](evidence/practice/README.md)に分けています。各記録で確認できていない範囲は、それぞれの証跡と下の[実装と検証の範囲](#実装と検証の範囲)に書いています。

AD の作業結果と、障害・課題 15 件（LAB-01〜15）の対処は[作業結果・引き渡し報告](evidence/2026-09-02-work-result-SM-AD-001.md)にまとめています。

## AI が実行した新しいラボの検証（2026-09-27〜28）

旧 VM が残っていないため、新しい Hyper-V ラボを用意しました。[新ラボの実行記録](evidence/2026-09-28-new-hyperv-lab-operations.md)には、本人の承認を受けて **Codex が操作・判定した結果**をまとめています。上記の本人による実習や、AI なしの独力再現とは分けています。

Ubuntu の10サービス起動と OS 再起動後の33項目を確認しました。0・1・6時間の点検記録はありますが、記録の欠測と時計の不一致があり、24時間前に本人の指示で終了したため、**24時間試験は未完了・未合格**です。AD はフォレスト作成後の確認待ち、WSUS は起動準備まで、別 VM は復元先の OS・Docker 準備までです。バックアップ転送・別 VM 復元・第三者確認は未実施です。[続編の手順](partial-lab-continuation.md)では、これらの部分結果と残作業を区別しています。

## CI での性能改善と保存済みデモ

**2026-09-17 の性能改善**: [旧 CI の分析](evidence/2026-09-17-performance-ci-analysis.md)で HTTP 502 の集計漏れを見つけ、集計・CI 判定と上流接続の再利用を修正しました。[比較と確認試験](evidence/2026-09-17-upstream-keepalive-comparison.md)では、同じ負荷設定の 2 回の CI で、並列 1/2/4/8/16 の HTTP・通信失敗が 0 件でした。最終試験では、認証（未認証 401・認証あり 200）と、アプリの IP を変えた後の復旧も確かめました。AI 支援による分析・改善で、測定は使い捨て runner での短時間のものです（長期運用や本番の容量は対象外）。

[保存済み証跡のデモ](https://ns7jp.github.io/demo.html)は 2026-08-18/19 の画像・ログを再構成した閲覧用リプレイで、実操作の連続録画ではありません。

## 実装と検証の範囲

| 区分 | このリポジトリで示せるもの | 境界 |
| --- | --- | --- |
| 実装済み | 認証付き Flask アプリ、Compose、監視、Ansible、復旧手順 | コードが存在することと各環境で動作することは別 |
| 記録済みの CI 実測 | [2026-08-22 の E2E](evidence/2026-08-22-full-stack-e2e.md)：一括構築・冪等性・復旧・復元など 23 ID PASS | 当該 commit の使い捨て Ubuntu runner。最新差分や永続ホストの保証には使わない |
| 記録済みの VM 実測 | [2026-09-04 Ubuntu の基盤構築](evidence/2026-09-04-ansible-foundation-build.md)と[AlmaLinux の基盤構築](evidence/2026-09-04-ansible-foundation-el9-build.md)：`foundation.yml` の `common` / `docker` role 適用・冪等性 | 監視全体の `site.yml` とは別。AlmaLinux は再利用 VM で、新規構築・最小公開の証明には未到達 |
| 記録済みの手作業構築（2026-09） | [手元の VM で私が確認したこと](#手元の-vm-で私が確認したこと)の Ubuntu・Docker 最小構成・AD / WSUS の各記録。AD / WSUS は [AD 構築案件パック](build-package-ad/README.md)と [WSUS 構築案件パック](build-package-wsus/README.md)の手順書・試験仕様書に沿って構築・試験し、実機で見つけた手順書の誤り・欠落（AD 6 件・WSUS 9 件）を修正（[AD の作業結果](evidence/2026-09-02-work-result-SM-AD-001.md)・[WSUS の作業結果](evidence/2026-09-07-work-result-SM-WSUS-001.md)） | AI の手順案内を受けた手作業で、本リポジトリの Ansible（Windows 用 role を含む）は使っていない。監視全体の同時稼働と通知、組織 DNS・クライアント PC、中央 Prometheus からの収集（BLOCKED）、電源断からの復旧、独力での再現、長期稼働は `NOT RUN` |
| AI が実行した新ラボ（2026-09-27〜28） | [実行記録](evidence/2026-09-28-new-hyperv-lab-operations.md)：Ubuntu10サービス、OS再起動後33項目、0・1・6時間点検 | 24時間試験は未完了・未合格、本人の独力再現ではない。新ADの受け入れ・WSUS通し試験・別VM復元も未完了 |
| 未実施・未達 | AWS の実適用・削除、Slack 実配信、D-2 ホスト障害復元は `NOT RUN`。新ラボの24時間観測は開始後に終了し未合格、72時間確認は `NOT RUN` | [実測計画](real-environment-validation-plan.md)と日付付き記録を参照 |

実行者が私・CI・AI 支援環境のどれかは、原則として各証跡に書いています。2026-08-19 の [D-1](drills/logs/2026-08-19-D-1.md) と[二セグメント障害ラボ](evidence/2026-08-19-network-drill.md)の記録には実行者の記載がなく、実行者不明として扱います。2026-09-07 の [dc02 の時刻同期](evidence/2026-09-07-ad-dc02-time-sync-fix.md)と [windows_exporter の最小権限化](evidence/2026-09-07-ad-windows-exporter-least-privilege.md)の記録も、本文には実行者の記載がありません。プロフィールでは 2026-09-01〜15 の VM の記録を、AI の手順案内を受けて私が操作したものとしており、この 2 本もその期間に入ります。そのことを各記録の冒頭に追記しています。
