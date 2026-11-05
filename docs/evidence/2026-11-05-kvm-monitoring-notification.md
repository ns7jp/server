# KVM 本人実習：監視・通知・停止・手動復旧を同じ構成で確認

実施日：2026-11-05。**実行者は本人、支援区分は ai-assisted**。AIがコマンド・待機の目安・確認観点を案内し、本人が実行して画面を提示しました。本文はチャットの画面をCodexが整理したものです。独力再現や初見障害の原因特定を試したものではありません。

## 環境と範囲

[同日のKVM初回実習](2026-11-05-kvm-guided-recovery.md)と同じUbuntu VM・clone（取得時コード d4004ec087681eb751d3d199000abf41ce7d77de）で継続しました。終了時のコードSHA・差分は未再取得です。

開始前の画面で、メモリ合計3.8 GiB・利用可能3.3 GiB、ルート空き14 GiBを確認。app / nginxにPrometheus / node-exporter / Alertmanager / blackboxを追加しました。後半に既存 compose.e2e.yaml のwebhook-sinkを追加し、計7サービスの部分構成を使用しました。Grafana・Loki・Alloy・docker-socket-proxyは今回起動していません。

## 監視で確認したこと

| 段階 | 本人提供画面で確認した結果 |
| --- | --- |
| 6サービス起動後 | 全6ジョブの up=1 |
| 入口の応答確認 | probe_success{job="blackbox-probe-health"}=1 |
| nginx計画停止 | 直後の確認は1、後続確認で0へ変化 |
| nginx手動再開 | /healthz のHTTP 200・curl終了0、probe_success=1へ復帰 |
| Prometheusのアラート | Watchdog firing、SLOSlowBurnRateAvailability pending、SLOErrorBudgetExhausted firing |
| Alertmanagerへの到達 | Watchdog active、SLOErrorBudgetExhausted active |

監視の収集成功を表すupと、入口経由の応答確認結果probe_successを別に確認しました。SLOアラートは停止演習を含む短い履歴に対する判定です。30日間のSLO達成・違反を評価した実績にはしません。終了時にすべてのSLOアラートが解消したかは未確認です。

## 通知受信を伴うapp停止・手動復旧

既存の検証用受信器と設定を使いました。

- 受信器：tests/e2e/webhook_sink.py、127.0.0.1:18081。起動後 /healthz が status: ok。
- 追加Compose：本人VMの .artifacts/notify-practice/compose.yaml。
- Alertmanagerの設定：docs/evidence/artifacts/2026-11-05-cloud-monitoring-cycle/alertmanager.cloud.yml を読み取り専用でマウント。
- 起動時の指定：compose.yaml / compose.e2e.yaml / .artifacts/notify-practice/compose.yaml の3ファイル。設定はgroup_wait・group_interval各5秒、repeat_intervalは1時間。
- 判定：既存 ServerMonitorUnavailable の app収集失敗が2分継続する条件。合成アラートのAPI注入は行っていません。
- 通知先：同じVM内のwebhook-sink。Slack・メール等の外部配信ではありません。

| 段階 | 実際に確認した結果 |
| --- | --- |
| app計画停止 | app Exited (0)、nginx Up |
| 障害通知 | ServerMonitorUnavailable の firing を2件受信 |
| app手動再開後の最初の確認 | appはhealth: starting、HTTP 200・curl終了0 |
| 復旧通知 | 同じアラートの resolved を受信 |
| 後続の最終確認 | app healthy、nginx Up、appのup=1、入口のprobe_success=1 |
| 履歴保存 | /events を .artifacts/notify-practice/events.json に保存、save_exit=0 |

画面にある受信器の時刻（UTC）は firing が07:03:52.309104、08:03:52.828329、resolved が08:25:03.018289です。これは受信時刻であり、障害発生・実際のHTTP復帰の時刻ではありません。復旧所要時間や通知遅延は算出しません。停止状態の画面には停止から約1時間経過した表示があり、案内した待機時間どおりに実施されたとは扱いません。

追加Composeの内容：

```yaml
services:
  alertmanager:
    volumes:
      - ./docs/evidence/artifacts/2026-11-05-cloud-monitoring-cycle/alertmanager.cloud.yml:/etc/alertmanager/alertmanager.yml:ro
```

## 判定と記録の所在

**同一構成で、監視の正常確認・停止時の変化・障害通知・手動復旧・復旧通知・最終正常確認までを、案内に沿った本人操作で確認しました。**

一次資料はチャット内で本人が提示した画像です。画像原本と生ログ・events.jsonはリポジトリ未収録です。events.jsonの保存終了0は画面で確認しましたが、ファイル内容の取得・照合はしていません。受信器の履歴はメモリ上にあり、再作成で消えるためVM上へ保存しました。秘密値・プライベートIP・マシン識別子は本文へ転記していません。

最終画面でapp / nginxの正常と上記監視値を確認しました。後続の本人操作で検証用受信器の撤去と通常Compose指定によるAlertmanagerの再作成を確認しました。全サービスの終了は実施せず、6サービスを稼働状態で残しています。AIによる別のクラウド検証と合算せず、本人の独力再現、外部通知、OS再起動後の全構成復帰、長期稼働、自動復旧、バックアップ復元、監視全体・本番運用は未確認です。

[証跡台帳](README.md) / [初心者向け学習ガイド](../beginner-learning-guide.md)

## 後片付けの確認

本人が同じ実習VMで、3ファイル指定の `docker compose rm --stop --force webhook-sink` を実行し、画面で受信器のStopped・Removedを確認しました。続いて通常の `docker compose up -d --no-deps alertmanager` を実行し、Alertmanagerを再作成しました。

後続の `docker compose ps --all` では、webhook-sinkがなく、app healthy、nginx・Prometheus・node-exporter・blackbox・AlertmanagerがUpでした。これで一時的な通知構成の後片付けまで確認しました。保存済みevents.jsonは受信器の外のVM内ファイルです。後片付け後のファイル内容再読込・通常設定のマウント内容の独立照合は未実施です。
