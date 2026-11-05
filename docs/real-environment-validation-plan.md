# 本人管理環境で残す実測証跡計画

この文書は、CIやAI支援sessionの結果を、本人管理のVPS / VM / AWSでの実績へ読み替えず、
同じ順序で再実行するための計画である。**この文書を追加しただけでは一項目もPASSにならない。**

## まず一つの構成で確認する

2026-11-05 時点では本人が対象 VM を利用できず、今回の本人実習は未実施です。
`ubuntu-practice01` を利用できるようになったら、app / nginx の小さな構成から始めます。
手順書や公式資料を参照しながら、本人が通信経路・次に確認する対象・正常と判断する根拠を説明し、
正常確認 → 計画停止 → 状態とログの確認 → 手動復旧 → 同じ入口からの正常確認を一度通します。
本人の言葉と実際の出力だけを結果票に残します。AI による手順案内があった場合はその範囲を記します。

その後、同じ環境に監視と通知の受け口を用意し、障害発生 → Prometheus の検知 →
FIRING 受信 → 調査・復旧 → HTTP と収集の復帰 → RESOLVED 受信を確認します。
通知を API で直接注入する試験と、実際の停止をルールが検知する試験を区別します。
ローカルのテスト受信器でも一巡を確認できますが、Slack への配送実績には数えません。

参考として、[2026-11-05 のクラウド実測](evidence/2026-11-05-cloud-monitoring-cycle.md)には、
AI が独立5サービスでこの一巡を実施した結果と再実行用の構成を載せています。
本人管理環境の実績へ読み替えず、下表の判定は変更しません。

この小さな確認の後に、必要に応じて下表の全体構成・再起動・長期稼働へ進みます。
下表は拡張する際の計画であり、全項目を応募前の必須条件にはしません。

## Definition of Done

以下は本人が再実行する計画の判定です。2026-09-27〜28の [新Hyper-VラボのAI実行](evidence/2026-09-28-new-hyperv-lab-operations.md)では、Ubuntu10サービス・OS再起動・0/1/6時間点検までを別の部分結果として確認しました。24時間試験は欠測・時刻不一致があり終了したため未合格です。下表のAnsible全体適用・正式な受け入れ・本人の再現が完了したという意味ではなく、部分結果だけで下表を一括PASSにはしません。なお2026-09-08には、本人管理のVM `lab-base01`（現存しない）で、部分構成のD-1と、Lokiの同一VM内の別ボリュームへの復元を、AIの手順案内を受けて行っています（[D-1](evidence/2026-09-08-lab-base01-d1-practice.md)・[復元](evidence/2026-09-08-lab-base01-restore-practice.md)）。下表の手順（Phase 1から順に行う全体構成）とは別の演習なので、Phase 4の判定は変えません。

| Phase | 対象 | 完了条件 | 現在 |
| --- | --- | --- | --- |
| 1 | fresh Ubuntu 24.04 VPS/VM | Ansible初回`failed=0`、2回目`changed=0` | NOT RUN |
| 2 | 実管理端末 | SSH tunnel、DNS、listen、firewallをNW-01〜09で確認 | NOT RUN |
| 3 | runtime | 認証、metrics、Grafana、Loki、local alertを実測 | NOT RUN |
| 4 | recovery | D-1とbackup/別volume restoreを実測 | NOT RUN |
| 5 | persistence | reboot前baselineとafter-reboot結果を比較 | NOT RUN |
| 6 | soak | 24時間、続いて72時間のsamplingを完走 | NOT RUN |
| 7 | external notification | SlackのFIRING/RESOLVEDを受信側timestamp付きで保存 | NOT RUN |
| 8 | AWS（任意） | 承認済みplan、apply、外形確認、費用、destroyを保存 | NOT RUN |

## 実施前の停止条件

- 対象IP、管理元CIDR、DNS名、作業時間帯、費用上限が未確定なら開始しない。
- snapshotまたはVPS再作成手順、直前の正常commit SHA、秘密値の受け渡しがなければ開始しない。
- 実データや共有production hostでは障害注入しない。
- AWSではBudget通知を先に設定し、`terraform plan`のresource数と月額見積りをreviewする。

## 実行順

1. [立ち上げと受け入れ試験](build-package/10-host-bringup-and-acceptance.md)に従って構築する。
2. 対象hostで `sudo ./scripts/ops/acceptance-check.sh` を実行する。
3. `--mode baseline`を保存してrebootし、`--mode after-reboot`で比較する。
4. `--mode soak --hours 24`、合格後に`--hours 72`を実行する。
5. [network実機検証](build-package/09-network-validation-procedure.md)を実管理端末から実行する。
6. Slackは秘密値をGit外で設定し、FIRINGとRESOLVEDの受信画面を採録する。
7. AWSを選ぶ場合だけ、[AWS設計](aws-architecture.md)と[コスト計画](cost-report.md)をreviewし、
   `plan → apply → acceptance → destroy`の順を崩さない。

## 証跡に必ず含めるもの

- 実施者、UTC日時、環境種別、OS、tool versions
- candidateとrollback先の40桁commit SHA
- 実行command、終了code、期待値、実測値
- raw logの保存場所とchecksum（秘密値・IPはmask）
- `PASS / FAIL / BLOCKED / NOT RUN`、未実施理由、解除条件
- 費用が発生した場合は期間と実費
- 削除・rollback後の確認結果

結果は試験仕様原本を上書きせず、`docs/evidence/YYYY-MM-DD-<scope>.md`へ保存する。
環境が提供されていない間は上表を`NOT RUN`のまま維持する。
