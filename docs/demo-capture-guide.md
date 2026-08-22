# 2〜3 分デモ実行・収録ガイド

採用担当者が短時間で「設計書だけでなく実際に動かした」と判断できるよう、
`構築証跡 → 稼働確認 → 通知経路 → 障害注入 → 自動復旧` を一つのデモにします。

> **公開デモ:** [2分15秒の保存済み実測証跡リプレイ](https://ns7jp.github.io/demo.html)を
> 公開しています。これは2026-08-18/19のscreen shotとD-1 logを時系列に再構成した映像で、
> 実操作の連続録画ではありません。実操作の連続録画は未公開です。成功したGitHub Actions
> artifactの`demo.cast`は、workflow内で実行したterminal sessionとして別に扱います。

## 最小操作で実行する

1. GitHubの `Actions` で `Full-stack Ansible E2E` を `Run workflow` します。
2. 完了後、`full-stack-e2e-<run id>-<attempt>` artifactをダウンロードします。
3. `summary.md`、`ansible-second.log`、`demo.cast` を確認します。
4. `demo.cast` は asciinema で再生できます。

```bash
asciinema play demo.cast
```

workflowは [一気通貫E2Eの説明](e2e-validation.md)どおり、新規host構築から
backup restoreまで実行した後、[run-demo.sh](../scripts/demo/run-demo.sh)を別sessionとして
録画します。castやlogが生成された事実だけでPASSにはせず、`summary.md`の判定を正本にします。

## 人がナレーションを入れて収録する

E2Eを実行した使い捨てUbuntu VMで次を実行し、OBSなどでterminalとbrowserを収録します。

```bash
sudo bash scripts/demo/run-demo.sh \
  --project-dir /opt/server-monitor \
  --evidence-dir "$PWD/.artifacts/demo/manual" \
  --pace-seconds 5
```

自動台本が表示する順番は次のとおりです。

| 目安 | 画面 | 実際に確認すること |
| --- | --- | --- |
| 0:00–0:25 | terminal | commit、実行日時、core 10 services、health |
| 0:25–0:50 | Grafana / terminal | Grafana healthとPrometheus `linux-node up=1` |
| 0:50–1:20 | terminal / Alertmanager | synthetic alertがlocal webhookへFIRING/RESOLVED配送 |
| 1:20–2:15 | terminal | app PIDをhost側からkillし、自動再起動とRTOを計測 |
| 2:15–2:45 | terminal | D-1 summary、証跡directory、最終health |

synthetic alertは通知経路を短時間で安全に検証するためのものです。D-1障害で発生した
alertだと偽りません。CIでは通知先をlocal webhook sinkに限定しています。

## 収録時に読む要点

1. 「Ubuntu hostは`site.yml`で構築し、2回目`changed=0`は別logに残しています」
2. 「core 10 servicesとPrometheusのhost targetが現在稼働しています」
3. 「これはlocal webhookまでの通知試験で、Slack実配信ではありません」
4. 「app processを予期しない形で終了し、Dockerのrestart policyで復旧させます」
5. 「RTOとraw logはartifactへ残し、未実行項目をPASSにしません」

## Grafanaを画面に含める場合

管理portはloopbackだけにbindしています。リモートVMではSSH tunnelを張り、browserから
`http://127.0.0.1:13000` を開きます。

```bash
ssh -N -L 13000:127.0.0.1:3000 <user>@<vm>
```

Grafana admin passwordは秘密管理先から入力し、録画画面、shell history、字幕に出しません。

## Slackを含めてよい条件

Slackを映すのは、実webhookを設定し、秘密値を隠した上でFIRING/RESOLVEDの実配信を
その収録sessionで確認できた場合だけです。それまではlocal webhookの画面と説明を使います。

## 収録前チェック

- [ ] webhook URL、password、token、公開IP、account ID、個人名が画面に出ない
- [ ] browserの通知、bookmark、個人account名を隠した
- [ ] `summary.md`がPASSか確認し、FAILなら失敗を隠さず原因調査として扱う
- [ ] commit SHAと実行日時が動画とartifactで一致する
- [ ] synthetic alertと実障害を明確に区別して説明する

## 公開後に更新する場所

| 場所 | 更新内容 |
| --- | --- |
| `README.md` | 証跡リプレイと実操作の連続録画を区別し、後者の公開時だけ収録日・commitを追記 |
| `docs/evidence/README.md` | 動画URL、Actions run URL、artifact名、対象commit |
| `docs/drills/logs/YYYY-MM-DD-D-1.md` | 動画中のRTOと発見事項 |

動画本体はGitHub Release、YouTube限定公開、またはportfolio siteへ置きます。
公開後もraw logとActions runを併記し、編集済み動画だけを実測根拠にしません。
