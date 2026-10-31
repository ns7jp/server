# Ubuntu：再起動後の app / nginx 復帰確認（2026-10-31）

本人が Hyper-V の Ubuntu VM を操作し、再接続後に Docker・app・nginx の稼働と HTTP 200 を確認しました。
支援区分は **`ai-assisted`**。AI が手順を案内し、本人が操作・画像を提示、Codex が記録を整理しました。

## 対象と前提

| 項目 | 確認した内容 |
| --- | --- |
| 対象 | Hyper-V VM `ubuntu-practice01`、Ubuntu 24.04.5 LTS、ユーザー `opsadmin` |
| 接続と構成 | Tera Term、`~/server-nginx-practice`、Compose 名 `nginx-practice`、app / nginx の2サービス |
| 終了時コード版 | `a31c05159ad7074b0825ec5e22df55f2b1ac0375`。`git status --short` は出力なし |
| Docker 自動起動 | 再起動前の `systemctl is-enabled docker` は `enabled` |
| コンテナ再起動設定 | 再起動前の inspect で app / nginx とも `restart=unless-stopped` |
| 元資料 | 本人提示のチャット内画像と発言。原画像・ログファイルはリポジトリ未収録 |

## 実施経過と観測結果

1. AI が再起動前の状態採録と `sudo reboot` を案内しました。再起動前ログのファイル存在は後述のハッシュ表示で確認しましたが、本文と再起動コマンドの実行画面は未取得です。
2. 再接続の試行で Tera Term がタイムアウトしました。VM コンソールから現在の IP を確認したところ、以前の接続先と異なっていました。新しい IP を指定すると本人が接続成功を報告しました。古い IP への試行がタイムアウトしたことと IP 変更を観測しましたが、全通信経路の原因調査は未実施です。
3. 再接続後は Compose の `start` / `up` / `restart` を行わず、以下の状態確認だけを行うよう案内しました。提供画面で確認した出力は次のとおりです。

| 観測 | 結果 |
| --- | --- |
| ゲストの確認時刻 | `2026-10-31T12:59:18+00:00`（JST 21:59:18） |
| `uptime -s` | `2026-10-31 12:50:14`（ゲストは UTC 設定） |
| `systemctl is-active docker` | `active` |
| app | `Up 8 minutes (healthy)` |
| nginx | `Up 8 minutes`、公開先 `127.0.0.1:8080` |
| 入口経由の `/healthz` | `http_code=200`、直後の `curl_exit=0` |
| 終了確認時刻 | `2026-10-31T13:00:51+00:00`（JST 22:00:51） |

HTTP 確認は、前の停止・復旧演習と同じ次のコマンドです。

```bash
curl --max-time 10 -sS -o /dev/null -w 'http_code=%{http_code}\n' http://127.0.0.1:8080/healthz
echo "curl_exit=$?"
```

再接続後の提供画面には起動・再起動コマンドはありません。全操作を連続録画した記録や Docker events は未取得です。

## ログと判定範囲

本人が `script --log-out` で採録し、`exit` 後に `sha256sum` で `portfolio-private/reboot-before-*.log` と `reboot-after-*.log` のハッシュを表示した画面を確認しました。
原ログを取得しての再計算・本文照合は未実施です。ハッシュの表示だけで原ログの完全性や内容を検証済みとは扱いません。

**確認済みの範囲は、再接続後の2サービスの稼働と入口の HTTP 応答です。** Docker の enabled と restart policy は事前に確認しており、案内した確認経路では手動起動を挟まず復帰しています。
再起動直後の観測ではなく、ゲストの起動時刻から約9分後の確認です。起動直後の復帰時間・RTO、前後の全設定・イメージの同一性、監視全体の復帰、24時間稼働、外部通知、別 VM 復元は未確認です。

最終確認時は app / nginx が稼働しています。この記録を独力の構築・障害切り分けや連続稼働の実績には広げません。

[検証証跡台帳](README.md) / [同日の Nginx 停止・手動復旧](2026-10-31-ubuntu-practice01-guided-recovery.md)
