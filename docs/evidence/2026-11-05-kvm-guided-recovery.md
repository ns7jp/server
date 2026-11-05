# KVM 上の Ubuntu：本人操作による Nginx 停止・手動復旧

実施日：2026-11-05。支援区分：**ai-assisted**。AI が手順と確認観点を案内し、本人が操作して画面を提示しました。本文は会話内の画像と本人回答を Codex が整理したものです。画像原本・生ログはリポジトリに未収録です。

## 環境

| 項目 | 画面で確認した内容 |
| --- | --- |
| 仮想化・OS | KVM、Ubuntu 24.04.4 LTS、Linux 6.8.0-147-generic、x86-64 |
| ホスト名・操作者 | ubuntu、一般ユーザー user |
| ディスク | 仮想ディスク20 GiB。LVMの未割当8.22 GiBをルートへ追加し、約18 GiB・空き15 GiBを確認 |
| Docker / Compose | 29.1.3 / 2.40.3、Dockerサービス active |
| 対象コード | d4004ec087681eb751d3d199000abf41ce7d77de（取得後の画面で確認） |
| 作業場所・構成 | ~/server、Compose名 server-monitor-lab、app / nginx |
| 前提診断 | check-prerequisites.sh --minimal：FAIL=0、WARN=0、終了0 |

VM のインストール完了は本人の報告です。その後の OS 情報、LVM 拡張、Docker の状態、clone・前提診断、起動・停止・復旧は本人提供画面で確認しました。VM作成時のCPU・メモリ設定、OSインストールの全操作、再起動直後の時刻や復帰時間は確認していません。画面にはIP等もありますが、本文では接続先情報・識別子を省略しています。

## 操作結果

| 段階 | 実際に確認した結果 |
| --- | --- |
| 初回起動 | app healthy、nginx Up、入口は127.0.0.1:8080 |
| 正常確認 | /healthz に HTTP 200・curl終了0（2回の画面表示） |
| nginx計画停止 | nginx Exited (0)、app healthy継続 |
| 停止中の同じ入口 | 接続失敗、http_code=000、curl終了7 |
| nginx手動再開の直後 | nginx Up、app healthy。curlは接続リセット、http_code=000、終了56 |
| 後続の再確認 | 同じ入口でHTTP 200・curl終了0。nginxログに設定処理完了とworker開始 |

停止と再開はそれぞれ `docker compose stop nginx`、`docker compose start nginx`。HTTP確認は次のコマンドです。

```bash
curl --max-time 10 -sS -o /dev/null -w 'http_code=%{http_code}\n' http://127.0.0.1:8080/healthz
echo "curl_exit=$?"
```

再開コマンドの成功だけでは復旧完了にせず、接続リセット後に再確認してHTTP応答の復帰を確かめました。終了56の原因は未特定です。起動直後のタイミングだった可能性はありますが、断定しません。http_code=000はHTTP応答未受信の表示で、HTTPステータスコードではありません。復旧所要時間は計測していません。

## 本人の説明

AI が設問を提示し、本人が次の回答をしました。これまでの説明・手順案内を受けた学習中の回答です。

- 通信が通るサービス：本人「nginxです」。その後、AIが curl → nginx → app の経路を説明。
- app healthyでもアクセスできなかった理由：本人「nginxが停止していたからです」。
- 復旧判断：本人「HTTP 200・curl終了コード0を確認して復旧したと判断しました」。

## 確認できた範囲

**案内に沿った2サービスの正常確認・計画停止・手動復旧と、上記3点の回答を確認しました。** 独力での再構築・初見障害の原因特定を試した記録ではありません。

最後の画面ではHTTP 200・curl終了0が確認され、停止したnginxは再開済みです。終了時の全サービス一覧の再取得、後続の長期稼働、監視・通知、認証試験、バックアップ・復元は今回未確認です。過去のHyper-V記録やAIによるクラウド検証とは別環境の記録として残します。

[検証証跡台帳](README.md) / [初心者向け学習ガイド](../beginner-learning-guide.md)
