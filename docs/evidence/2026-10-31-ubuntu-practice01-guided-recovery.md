# Ubuntu：Nginx の停止・手動復旧と説明の確認（2026-10-31）

**本人が Tera Term から操作し、正常応答→Nginx 停止による接続失敗→手動再開後の正常応答を確認しました。支援区分は `ai-assisted` です。** AI がコマンドと確認観点を案内し、本人が画面を提示しました。本文はその画面と会話を Codex が整理したものです。

## 環境と資料

| 項目 | 確認できた内容 |
| --- | --- |
| 対象 | 本人の Hyper-V VM `ubuntu-practice01`、Ubuntu 24.04.5 LTS、ユーザー `opsadmin` |
| 接続・構成 | Windows の Tera Term、`~/server-nginx-practice`、Compose 名 `nginx-practice`、app / nginx |
| 対象コード | `a31c05159ad7074b0825ec5e22df55f2b1ac0375`。開始時の `git rev-parse HEAD` で確認 |
| 作業差分 | 終了時の `git status --short` は出力なし。追跡外・除外ファイルの同一性は未確認 |
| 観測時刻 | 起動確認 06:51:56 UTC、停止確認 06:55:26 UTC、再開確認 06:56:37 UTC、終了確認 06:57:50 UTC（JST はそれぞれ15時台） |
| 時計 | ゲストの表示。`Etc/UTC`、System clock synchronized: yes、NTP service: active。独立した時計との照合は未実施 |
| 一次資料 | このチャットで本人が提示した画像と回答。画像原本・生ログはリポジトリ未収録 |
| 操作ログ | 本人が `script --log-out` でホーム配下の `portfolio-private/demo-*.log` に採録し、終了後に `sha256sum` を実行した画面を確認。原ログ取得・ハッシュ再計算は未実施 |

## 操作と実結果

| 順序 | 本人が実行した操作 | 画面で確認した結果 |
| --- | --- | --- |
| 初期状態 | `docker compose -p nginx-practice ps --all app nginx` | app / nginx とも `Exited (0)` |
| 起動 | `docker compose -p nginx-practice start app nginx`、状態確認、入口の `/healthz` に curl | app healthy、nginx 稼働、HTTP 200、curl 終了0 |
| 入口の停止 | `docker compose -p nginx-practice stop nginx`、同じ curl、状態確認 | nginx `Exited (0)`、app healthy 継続。curl 接続失敗・終了7、`http_code=000` |
| 手動復旧 | `docker compose -p nginx-practice start nginx`、同じ curl、状態確認 | HTTP 200、curl 終了0、app healthy、nginx 稼働 |
| 終了 | 作業差分・時刻同期の確認、`exit`、原ログのハッシュ表示 | 差分表示なし、時刻同期yes、script終了後にハッシュを表示 |

HTTP 確認に使用したコマンドは次のとおりです。終了コードは curl の直後に確認しました。

```bash
curl --max-time 10 -sS -o /dev/null -w 'http_code=%{http_code}\n' http://127.0.0.1:8080/healthz
echo "curl_exit=$?"
```

`000` は HTTP ステータスコードではなく、HTTP 応答を受け取れなかった表示です。この演習の停止中は curl 終了7と接続失敗の文言を確認しました。

## 本人の説明と支援の範囲

最初に「app が healthy でもアクセスできなかった理由」を尋ねた際、本人は「理由はわかりません」と回答しました。
その後 AI が「利用者→nginx→app」という経路と、app 内部の healthcheck の確認範囲を説明しました。
説明後の確認では、本人は次のように回答しました。

- 停止していた対象：「今回止まっていたのは nginxです」
- 復旧判断の根拠：「HTTP 200・curl 終了コード0で判断できます」

この回答で確認できたのは、説明後に停止対象と HTTP 復帰の根拠を答えられた範囲です。独力での原因特定、初見の障害対応、経路全体の独力説明を確認したものではありません。

## 判定と残作業

正常→停止→手動復旧の操作観点は期待値を満たしました。連続録画・本人の自発的な判断説明・5分以内の実演・3回の反復は未確認のため、本人向けライブデモ全体の合格にはしていません。
観測時刻の間には会話・待ち時間があり、差分を作業時間や復旧所要時間とは扱いません。

最終確認時は app / nginx が稼働しています。最後の停止・撤去は未実施です。
OS 初期構築、OS 再起動後の自動復帰、外部通知、監視全体、24時間稼働、別 VM 復元、WSUS 再試験、自動復旧 D-1 は今回の対象外です。
次は同じ経路を本人の言葉で説明する練習と、記録の追加確認を行います。本人の結果票への記入、原ログの公開用コピー・画像の取得と照合も残っています。

[検証証跡台帳](README.md) / [前回10/1の実習](2026-10-01-ubuntu-practice01-nginx-manual-recovery.md)
