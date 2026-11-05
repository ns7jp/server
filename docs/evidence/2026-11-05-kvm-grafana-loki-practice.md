# KVM 本人実習：Grafanaの数値表示とLokiのログ検索

実施日：2026-11-05。**本人操作・ai-assisted**。AIが手順と確認観点を案内し、本人が実行して画面と回答を提示しました。Codexがその内容を本記録へ整理しています。独力再現の記録ではありません。

## 同じVMで継続した範囲

[初期準備・認証・Nginx手動復旧](2026-11-05-kvm-guided-recovery.md)、[監視・通知・復旧通知](2026-11-05-kvm-monitoring-notification.md)の後、同じKVM上のUbuntu 24.04.4 LTS・一般ユーザーuser・~/serverで継続しました。

実行コードは **d4004ec087681eb751d3d199000abf41ce7d77de**。最後の git rev-parse HEAD で再確認しました。続く git status --short は画面上で出力なしです。Git除外ファイル・秘密値・全稼働コンテナの内容とソースの同一性までは検証していません。

## Grafanaの起動と数値表示

本人が docker compose up -d --no-deps grafana を実行し、Grafana 11.2.2のUpと /api/health の database: ok を確認しました。この段階ではLokiをまだ起動せず、数値表示を先に確認しました。

手元のWindows PowerShellからVMへSSHポート転送を設定し、PC側の127.0.0.1:13000をVM内の127.0.0.1:3000へ転送しました。最初のブラウザーアクセスは接続拒否で、SSHのパスワード入力を済ませた後にログイン画面が表示されたと本人が報告しています。

adminと既存のGrafana用資格情報でログインし、Infrastructure Lab / Server Monitor Infrastructure Labを開きました。資格情報の値は記録していません。時間範囲Last 15 minutesの本人提供画面で、次を確認しました。

| 表示 | 確認値・内容 |
| --- | --- |
| Application Scrape Status | 1 |
| Linux Host CPU | 2.86% |
| Linux Host Memory | 20.7% |
| CPU / Memory History | 履歴の折れ線を表示 |
| Linux Host Filesystem Use | / と /boot の使用率を表示 |

各数値はその画面時点の観測です。パネル全体の正確性・性能・可用性の保証にはしません。appのpsutil経由の値とnode-exporter経由のLinux指標は異なる収集元です。最初の画面でLokiパネルにはエラーがあり、ログ経路は後の実習で確認しました。

## Alloy・Lokiの起動と目印付きログの検索

本人が docker compose up -d loki docker-socket-proxy alloy を実行し、3サービスのUpとLoki /ready の ready を確認しました。

目印付きの認証なしアクセスを作るため、次のコマンドを案内しました。

```bash
curl --max-time 10 -sS -o /dev/null \
  -w 'http_code=%{http_code}\n' \
  'http://127.0.0.1:8080/?lab=kvm-loki-20261105'
```

Grafana ExploreでLokiを選び、次のクエリを本人が実行しました。

```logql
{compose_project="server-monitor-lab", service="nginx"} |= "kvm-loki-20261105"
```

本人提供画面で **Total: 1** と、共通ラベル service=nginx / method=GET / status=401 を確認しました。スクリーンショット内ではログ本文全体は表示範囲外なので、本文の逐語転記はしていません。端末側curl結果の画面はこの段階では未提示です。

設定上の経路はNginxのコンテナログ → Docker API proxy経由でAlloyが収集・加工 → Lokiへ送信・保存 → Grafanaが検索です。この記録では目印による検索結果を確認しており、ログの網羅性・長期保持・障害時の欠損・バックアップ復元は未検証です。

## 本人の説明

AIからの設問に、本人は次のように回答しました。手順と説明を受けて進めた学習中の回答であり、独力試験ではありません。

- Prometheus：「CPU使用率などの数値を集めて保存する。」
- Grafana：「保存された数値を問い合わせ、グラフやダッシュボードにして見せる。」
- Alloy：「ログなどのデータを収集・加工して、保存先へ送る。」
- Loki：「送られてきたログを保存し、検索できるようにする。」

## 最終状態と残り資源

本人が docker compose ps --format 'table {{.Service}}\\t{{.Status}}' を実行した画面では、alertmanager / alloy / app / blackbox / docker-socket-proxy / grafana / loki / nginx / node-exporter / prometheus の **10サービスがUp、appはhealthy**でした。Upの表示を、各機能・通知・全アラートの正常確認とは同一視しません。

同じ画面でメモリ合計3.8 GiB・used 993 MiB・available 2.9 GiB・buff/cache 3.0 GiB、Swap 0、ルート約18 GiB・使用5.3 GiB・空き12 GiB・使用率32%を確認しました。free欄148 MiBだけでメモリ不足とは判定せず、利用可能量を確認しています。これは1時点の観測で、4 GiBでの全期間の容量保証ではありません。

最後は10サービスを稼働したままで、SSHトンネル終了・全体停止・再起動・長期稼働試験は未実施です。一次資料はチャットで本人が提示した画面と回答で、原画像・生ログはリポジトリ未収録です。秘密値・プライベートIP・マシン識別子は記録していません。

**この回で確認したのは、案内に沿ったGrafanaの数値表示、目印付きNginxログのLoki検索、本人による役割の説明と最終状態です。**

[証跡台帳](README.md) / [初心者向け学習ガイド](../beginner-learning-guide.md)
