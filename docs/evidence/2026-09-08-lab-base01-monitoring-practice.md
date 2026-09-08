# lab-base01：5サービスによる数値監視・停止検知・収集復帰（2026-09-08）

## 結果と範囲

本人のHyper-V上のUbuntu VMで、メモリ2GiBのまま監視を段階的に追加した。
app / node-exporter / Prometheus / Alertmanagerを起動し、Grafanaを追加した計5サービスで、
数値の取得・表示と、アプリの手動停止／再開に伴う収集状態の1→0→1を確認した。
最後に5コンテナと3ネットワークを撤去した。

**教材の全10サービスの受け入れではなく、数値監視の部分演習である。**
ログ収集・外部通知・自動復旧D-1・Ansible・AWSは **NOT RUN**。
UIのup=1は直近scrapeの成功であり、アプリの全機能・監視全体の正常性ではない。

## 来歴と環境

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を案内し、本人が操作して画像を提供。AIによるVMへの接続・実行ではない |
| 日付 | 2026-09-08 JST（対話の日付）。実施の全開始終了時刻や連続ログは未採録 |
| 対象 | 個人学習用Hyper-V VM `lab-base01`、Ubuntu Server 24.04.4 LTS、メモリ約1.9GiBとして認識 |
| 前段 | [Docker最小構成演習](2026-09-08-lab-base01-compose-practice.md)。そのcloneと秘密値を再利用する手順 |
| 教材版の境界 | 前段で採録したHEADは `1e5b3335cdf0d8ca7d0726b4411792be9f38c73a`。本演習の開始・終了時にSHAを再採録していないため、同一版の厳密な再検証とは扱わない |
| 参照した手順 | [当該SHAの学習ガイド](https://github.com/ns7jp/server/blob/1e5b3335cdf0d8ca7d0726b4411792be9f38c73a/docs/beginner-learning-guide.md) Step 6。実施は以下の部分構成へ変更 |
| 基盤 | Docker29.8.0、Compose v5.5.1、Linux6.8.0-139、Python3.12.3を前提診断で確認（[E01]） |
| イメージ | Prometheus v2.55.1、node-exporter v1.8.2、Alertmanager v0.27.0、Grafana11.2.2（[E02]、[E05]） |
| 証拠 | [本人提供の原画像10枚・ハッシュ一覧](screenshots/2026-09-08-lab-base01-monitoring/README.md)。rawログ全文は未提供 |

## メモリ制約への対応

前提診断はFAIL0/WARN2、終了0。警告はAnsible未導入とメモリ6GiB未満（[E01]）。
Ansibleはこの段階で使用しない。メモリ警告は消したことにせず、部分構成で進めた。
ホストPCの空きメモリに余裕がなく、別用途のAD・WSUS VMを停止しないという本人の指示を尊重した。
ホスト側アプリ・他VMを停止した実績はない。

案内した起動範囲は次のとおり。画像では起動後の対象一覧を確認する。

```bash
docker compose up -d app node-exporter alertmanager prometheus
docker compose up -d --no-deps grafana
```

Grafanaの依存先であるLokiは起動しない。Prometheusの依存関係に必要なapp、node-exporter、
Alertmanagerを先に起動した。起動直後の観測では4サービスでavailable約1.3GiB（[E02]）、
5サービスで約1.2GiB、Swap使用0（[E05]）。これはその時点の観測であり、
2GiBでの長期稼働・負荷時の安定性・ホスト側メモリ解放の保証ではない。
docker statsのMEM LIMIT表示は各サービスへの個別上限設定を証明するものではない。

## 確認結果

MP番号は本報告書の確認観点であり、前段のT/CP番号や監視案件の必須IDと合算しない。

| ID | 観点 | 判定 | 結果と証拠 |
| --- | --- | --- | --- |
| MP-01 | 前提診断 | 条件付き続行 | FAIL0/WARN2・終了0。メモリ警告とAnsible未導入を記録（[E01]） |
| MP-02 | 4サービスの起動 | PASS | 4件Up、app healthy、メモリ/Swapを観測（[E02]） |
| MP-03 | アプリ・Ubuntuの数値収集 | PASS | `up{job="server-monitor"}`と`up{job="linux-node"}`が1（[E03]） |
| MP-04 | Ubuntuメモリ指標の計算 | PASS | `100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)`をlinux-nodeに絞って評価し、約32.0228%（[E04]） |
| MP-05 | Grafanaの起動・health | PASS | 5サービスUp、Grafanaのapi/healthがdatabase ok・version11.2.2（[E05]） |
| MP-06 | ログイン後のダッシュボード表示 | PASS | Infrastructure Labのダッシュボードに数値と履歴、scrape status1を表示（[E07]） |
| MP-07 | 手動停止後の収集失敗表示 | PASS | 左上Application Scrape Statusが赤い0（[E08]）。停止操作は本人への案内と結果画像による記録 |
| MP-08 | 手動再開後の収集復帰表示 | PASS | 左上が緑の1へ復帰（[E09]）。自動復旧・所要時間測定ではない |
| MP-09 | コンテナ・ネットワークの撤去 | PASS | compose downで5コンテナ・3ネットワークRemoved、psにサービス行なし、venv終了（[E10]） |

Grafanaで最初に表示されたLinux Host CPUは3.27%、Linux Host Memoryは37.1%（[E07]）。
停止中はscrape status0、再開後は1となった。これらは各画面時点の値であり、
Prometheus APIを実行した時刻の32.0228%と一致する必要はない。
Linux HostはUbuntu VMを指し、Windowsホスト全体の値ではない。
Application Containerというパネル名があっても、psutilの全指標がコンテナ専用値とは限らない。

## アクセス方法と発見事項

Grafanaの公開先はVMの127.0.0.1:3000。Windowsからは、既存の名前付きSSH鍵を使い、
ローカル127.0.0.1:3000をVMの同ポートへ転送するSSHトンネルを案内した。
本人がログイン画面表示とadminログイン成功を申告し、その後ダッシュボード画像を提供した。
トンネル自体の起動コマンド・待受の画像、ログインフォームの記録は未採録。

パスワード暗記を避けるため、SSH経由でGrafana用ファイルを読みWindowsのクリップボードへ
直接渡す手順を使用した。秘密値本文は共有画像に表示されていない（[E06]）。
後片付けに案内した `Set-Clipboard -Value ""` はこの環境でArgumentNullExceptionとなった。
AIの案内の問題として記録し、非秘密の文字列 `cleared` で置き換える手順を再案内した。
ただし置き換え成功やクリップボード履歴削除の実行結果は未採録で、完了したと断言しない。

## 終了状態・未実施範囲

- 起動した5サービスと作成された3ネットワークの撤去は画像で確認（[E10]）。
- `docker compose down`に`-v`を付けず、監視データ用の名前付きボリュームを削除しない手順。
  終了後のボリューム一覧・データの再読込み・永続性試験は未採録で、復元成功とは扱わない。
- .envと秘密値の再生成・削除は行わない案内。終了時の存在・ハッシュ再確認は未採録。
- SSHトンネルのCtrl+Cによる終了を案内したが、完了の申告・画面は未提供。
- Nginx、blackbox、Loki、Alloy、docker-socket-proxyは今回未起動。
  それらを対象とする監視・probe・ログパネルの全正常性は **NOT RUN**。
- Grafana下部のLoki警告表示は画像に残る。ログが取得できたことや警告を解消したことを意味しない。
- Alertmanagerは起動を確認したのみ。アラート条件の発火・解消、外部通知・Slack実配信は **NOT RUN**。
- 起動/停止のCLI表示時間、画面の更新待ち20〜30秒を、検知時間・RTOの実測値へ読み替えない。
- 自動復旧D-1、全10サービス、長期稼働・性能、再起動後の再現性、Ansible/AWSは **NOT RUN**。
- 自分の言葉での説明、独力の再構築、第三者への引き渡しを完了した記録ではない。
- PR作成時の画像・リンク・整合検査は別のWindows環境での文書検査。VM操作やCIを再実行した証拠ではない。

次の再開時にはメモリと保存データの状態を確認し、今回の部分構成と全構成を区別する。
本報告書は記録追加であり、現在のVMや他のAD・WSUS VMへ変更を加えない。

- [検証証跡台帳](README.md)
- [前段の最小構成演習](2026-09-08-lab-base01-compose-practice.md)
- [元画像・SHA-256一覧](screenshots/2026-09-08-lab-base01-monitoring/README.md)

[E01]: screenshots/2026-09-08-lab-base01-monitoring/E01-prerequisites.png
[E02]: screenshots/2026-09-08-lab-base01-monitoring/E02-four-services.png
[E03]: screenshots/2026-09-08-lab-base01-monitoring/E03-scrape-up.png
[E04]: screenshots/2026-09-08-lab-base01-monitoring/E04-memory-query.png
[E05]: screenshots/2026-09-08-lab-base01-monitoring/E05-grafana-health.png
[E06]: screenshots/2026-09-08-lab-base01-monitoring/E06-clipboard-error.png
[E07]: screenshots/2026-09-08-lab-base01-monitoring/E07-dashboard-normal.png
[E08]: screenshots/2026-09-08-lab-base01-monitoring/E08-dashboard-down.png
[E09]: screenshots/2026-09-08-lab-base01-monitoring/E09-dashboard-recovered.png
[E10]: screenshots/2026-09-08-lab-base01-monitoring/E10-cleanup.png
