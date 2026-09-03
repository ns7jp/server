# 立ち上げと受け入れ試験

> 💡 **初めて読む方へ**: この文書は「まだ確認していない項目」を、恒久ホストを1台用意してから埋めるための手順書です。使い捨ての検証環境では確認できない「再起動後も設定が保たれるか」を中心に扱います。

## 1. ホストの選択肢

| 選択肢 | 費用 | 向いている用途 |
| --- | --- | --- |
| VirtualBox / Hyper-Vの無償VM | 無料（自PCのリソースのみ） | 個人の学習・ポートフォリオ用途 |
| クラウドの無料枠（AWS/GCP等） | 条件付き無料。課金設定に注意 | 短期間の検証。[AWSコスト計画](../cost-report.md)参照 |
| 既存の検証用VMの再利用 | 追加費用なし | 既に[Linux版パック](../build-package/README.md)用のVMがある場合、別VMとして`ans-01`を追加 |

いずれの場合も、対象VMはこのパックの範囲では**Docker Composeでワークロードを起動しない**ため、最小構成（1 vCPU / メモリ1GB / ディスク10GB程度）で足ります。監視アプリを同居させる予定がある場合は、[Linux版パックの最小要件](../build-package/03-parameter-sheet.md)を参照してください。

## 2. 立ち上げ手順

1. Ubuntu Server 24.04 LTS（または22.04 LTS）のインストールメディアから新規VMを作成する
2. OSインストール時にSSHサーバーを有効化し、初期ユーザーを作成する
3. 管理端末から`ssh <初期ユーザー>@<IP>`で到達性を確認する
4. [05-build-procedure.md](05-build-procedure.md)の手順0〜6を実施する

## 3. この手順で埋まるもの・埋まらないもの

| 項目 | 使い捨て検証環境 | 恒久ホスト（本手順） |
| --- | --- | --- |
| 初回構築・冪等性 | 確認できる | 確認できる |
| 再起動後もSSHハードニング・firewall設定が保たれるか | 確認しにくい（起動のたびに作り直すため） | **確認できる**（再起動して`--check --diff`が差分ゼロであることを確認） |
| 24 / 72時間安定稼働 | 確認できない | 確認できる（放置して再度SSH到達性とDocker稼働を確認） |
| 実際の管理端末・組織DNS・cloud firewallとの組み合わせ | 確認できない | 環境による |

## 4. 再起動後の確認（acceptance）

```bash
sudo reboot
# 再起動後
ssh <admin_user>@<target_ip> 'systemctl is-active docker; sudo sshd -T | grep -i passwordauthentication'
ansible-playbook -i inventory/foundation.local.yml playbooks/foundation.yml --check --diff
```

期待結果: 再起動後もDockerが`active`で、SSHハードニングが保たれており、`--check --diff`で新たな差分が出ないこと。

現時点では、この手順を実施できる恒久ホストが用意されていないため、本節の結果はすべて`NOT RUN`です。実施した場合は日付付きevidenceを作成し、[試験仕様書](06-test-specification.md)AFIT-01/02の結果と合わせて記録してください。
