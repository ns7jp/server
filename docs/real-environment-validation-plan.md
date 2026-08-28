# 本人管理環境で残す実測証跡計画

この文書は、CIやAI支援sessionの結果を、本人管理のVPS / VM / AWSでの実績へ読み替えず、
同じ順序で再実行するための計画である。**この文書を追加しただけでは一項目もPASSにならない。**

## Definition of Done

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
