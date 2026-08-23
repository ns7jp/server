# Alertmanager → Slack 実配信 記録テンプレート

このテンプレートを `docs/evidence/YYYY-MM-DD-slack-delivery.md` へコピーし、承認済みの
演習チャンネルで synthetic alert の **FIRING と RESOLVED** を実受信した結果を記録します。
ローカルwebhook sink、Alertmanager UIのFIRING表示、設定ファイルの存在だけではPASSにしません。

## 1. 実施情報

| 項目 | 記録 |
| --- | --- |
| 全体状態 | `NOT RUN` |
| 実施日時（JST） | `NOT RUN` |
| 対象host / commit SHA | `NOT RUN` |
| Alertmanager version | `NOT RUN` |
| 演習チャンネル（マスク名） | `NOT RUN` |
| 受信承認者 | `NOT RUN` |
| alert instance ID | `NOT RUN` |
| raw log / screenshot | `NOT RUN` |

Webhook URL、workspace ID、個人名、公開IP、認証情報は記録・画面・shell historyへ残しません。

## 2. Go / No-Go

- [ ] 通知先と実施時刻についてチャンネル管理者の了承を得た
- [ ] 本番paging先ではなく演習用channelである
- [ ] WebhookはGit外のsecret file / Vaultから注入され、標準出力へ表示されない
- [ ] Slack overlayを含むCompose設定が有効で、Alertmanagerがready
- [ ] synthetic alertの一意なinstance IDと終了時刻を決めた
- [ ] 誤通知時にsilence / resolveできる担当者がいる

## 3. 実配信結果

| Check | 送信時刻（JST） | Slack到着時刻（JST） | 遅延 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| FIRING | NOT RUN | NOT RUN | NOT RUN | NOT RUN | — |
| RESOLVED | NOT RUN | NOT RUN | NOT RUN | NOT RUN | — |

受信messageについて確認します。

| 項目 | 期待値 | 結果 |
| --- | --- | --- |
| alertname / severity / instance | synthetic値と一致 | NOT RUN |
| status | FIRING / RESOLVEDを区別 | NOT RUN |
| summary | 文字化け・欠落なし | NOT RUN |
| `runbook_url` | 対応runbookへ遷移可能 | NOT RUN |
| 重複 / 想定外channel | なし | NOT RUN |
| 秘密値露出 | なし | NOT RUN |

## 4. 送信と解消の記録

実際のpayloadは一意なinstance IDと短い有効期間を使います。Webhook URLへ直接curlせず、
稼働中AlertmanagerのAPIへ投入してrouting全体を確認します。秘密値を含まないpayloadとHTTP status、
Alertmanager logの該当時刻だけをraw logへ保存します。

```text
送信コマンド: NOT RUN
HTTP status: NOT RUN
Alertmanager routing確認: NOT RUN
FIRING screenshot: NOT RUN
RESOLVED screenshot: NOT RUN
Slack thread URL（公開版はマスク）: NOT RUN
```

## 5. 終了判定

- [ ] FIRINGとRESOLVEDを同じ一意instanceで実受信した
- [ ] 送信・到着時刻と通知遅延を記録した
- [ ] `runbook_url`を実際に開いて確認した
- [ ] 想定外channel、重複、秘密値露出がない
- [ ] synthetic alertが解消され、残留silenceや試験設定がない
- [ ] 問題と恒久対応をIssueへ記録した

一つでも未確認なら全体状態を `PASS` にしません。
