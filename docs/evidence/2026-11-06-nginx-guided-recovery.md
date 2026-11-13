# Ubuntu：Nginx の計画停止・手動復旧と確認範囲の説明

記録日：2026-11-06（JST、チャットの日付）。実機の実行日時・時刻同期は未採録。支援区分：**ai-assisted**。

AI がコマンドと確認観点を案内し、本人が端末で操作して画面を提示しました。本文はチャット内のスクリーンショットと本人回答を Codex が整理したものです。画像原本・生ログはリポジトリ未収録です。独力での再現・初見障害の原因特定の記録ではありません。

## 環境と確認範囲

| 項目 | 今回の画面で確認した内容 |
| --- | --- |
| 接続先 | hostname: ubuntu、ユーザー: user、開始時のディレクトリ: /home/user |
| Docker | 29.1.3、build 29.1.3-0ubuntu3~24.04.2 |
| Docker Compose | v2.40.3+ds1-0ubuntu1~24.04.1 |
| 既存構成 | server-monitor-lab の10コンテナが開始時に Up、app は healthy |
| 演習対象 | server-monitor-lab-nginx-1、入口 http://127.0.0.1:8080/healthz |
| 設定で確認した転送先 | app_backend → app:5000、/healthz → app_backend/healthz |
| 未採録 | VM の仮想化方式、OS の正確な版、対象コードの commit SHA、作業ツリーの状態、Compose の作業ディレクトリ |

~/server-nginx-practice は存在しませんでした。既存の server-monitor-lab コンテナを確認して演習しました。過去の記録にある VM・コード版と同一とは断定しません。

## 操作と実結果

| 段階 | 結果 |
| --- | --- |
| 停止前の入口確認 | HTTP=200、curl終了コード=0 |
| Nginx の計画停止 | docker stop が対象コンテナ名を返した |
| 停止中の入口確認 | 接続失敗、HTTP=000、curl終了コード=7 |
| 停止中の状態確認 | nginx: Exited (0)、app: Up (healthy)、ほか8コンテナも Up |
| Nginx 手動起動直後の初回 | Empty reply from server、HTTP=000、curl終了コード=52 |
| 同じ start コマンドを再実行後の確認 | HTTP=200、curl終了コード=0 |
| 復旧後の設定確認 | docker exec による nginx -T の設定出力を画面で確認 |

HTTP=000 は HTTP ステータスコードではなく、HTTP 応答を受け取れなかった表示です。終了52の原因は未特定です。起動直後の一時的な状態だった可能性はありますが、ログによる原因調査は行っていません。2回目の docker start が原因を解消したとは判断しません。復旧所要時間は計測していません。

### 実行コマンド

```bash
hostname
whoami
pwd
docker --version
ls -ld ~/server-nginx-practice
docker ps -a
docker compose version

# 停止前・停止中・再開後に同じ入口を確認
curl --max-time 10 -sS -o /dev/null -w 'HTTP=%{http_code}\n' http://127.0.0.1:8080/healthz
echo "curl終了コード=$?"

# 計画停止
docker stop server-monitor-lab-nginx-1

# 停止中の状態確認
docker ps -a --format 'table {{.Names}}\t{{.Status}}' --filter name=server-monitor-lab

# 手動再開（本人画面では2回実行、それぞれ直後に上記curlを実行）
docker start server-monitor-lab-nginx-1

# 復旧確認後に転送設定を表示
docker exec server-monitor-lab-nginx-1 nginx -T
```

上記は工程別の整理です。停止中・再開後の curl は表の順序で実施しました。

### 画面で確認した設定の抜粋

```nginx
upstream app_backend {
    zone app_backend 64k;
    server app:5000 resolve;
    keepalive 8;
    keepalive_timeout 2s;
}

location = /healthz {
    access_log off;
    proxy_pass http://app_backend/healthz;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
```

この設定から、今回の確認経路は curl → Nginx:8080 → app:5000/healthz と読み取れます。HTTP 200 はこの経路で正常応答を得た確認であり、アプリ全機能の正常性を示すものではありません。

## 本人の説明と支援

AI の説明と設問を受け、本人は次のように回答しました。

- 作業報告：「Nginxを停止した。停止中、HTTP接続できなくなった。HTTP=200、curl終了コード0で復旧と判断した。」
- app healthy のまま接続できなかった理由：「Nginxがappの入り口となっていて、それが停止によって閉じたため。」
- 確認範囲の違い：「app：healthyでアプリ自体のヘルスチェックの成功がわかる、Nginx経由のHTTP=200でHTTP応答を受け取れることがわかる。」

最後の回答に対し、AI は設定を根拠として「Nginx経由でappの/healthzから正常応答を受け取る」と補足しました。この経路全体の最終表現は AI の補足であり、本人がそのまま独力で回答した記録とは扱いません。

## 判定と残作業

案内に沿った正常確認・計画停止・手動復旧では、最終的に同じ入口の HTTP 200・curl終了0を確認しました。本人による停止理由・復旧判断の説明も上記の範囲で確認しました。

最終画面は起動中の Nginx の設定表示で、その前に HTTP の復帰を確認しています。終了時の全10サービス一覧・app healthy の再取得は未実施です。今回の監視値・通知受信・長期稼働・復元・外部端末からの到達性は確認していません。過去の監視・通知試験の判定は変更しません。

次回は[実習記録](templates/beginner-practice-record.md)へ、通信経路・停止対象・復旧判定を本人が先に書き、手順書を参照して再実行します。開始／終了時のコード版・日時、コマンド・実出力・直後の終了コードを保存し、判定に使った箇所を示します。今回の原画像・生ログの取得と照合、本人の判断による再実施は **NOT RUN** です。新しい実行ログは新しい日付の証跡にします。

終了52の原因は未特定のままです。次に同じ症状が出た場合は、その時点の状態・時刻・Nginx と app のログを保存して調べます。再発しなければ「今回の再実施では再発なし」とし、11月6日の原因が確定したとは記録しません。

[検証証跡台帳](README.md) / [前日の本人操作記録](2026-11-05-kvm-guided-recovery.md)
