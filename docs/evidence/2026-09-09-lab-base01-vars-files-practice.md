# lab-base01：Ansibleの環境別変数ファイル演習（2026-09-09）

## 結果と範囲

本人のUbuntu VMで、前段の[変数指定演習](2026-09-09-lab-base01-variables-practice.md)の
variables.ymlを使い、`-e @ファイル名`で変数を読み込む演習を行った。
staging用ファイルでは変更不要、training用ファイルへの切替でchanged=1、
同じtraining用ファイルの通常再実行でchanged=0と本文維持を確認した。

**ホーム内の同一ファイルの本文を切り替えた演習**で、複数サーバーや実際のtraining/staging環境を
作成・配備したものではない。ファイル名によって接続先ホストが切り替わったわけではない。

## 来歴・対象

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が操作・画像提供 |
| 実施日 | 2026-09-09 JST（対話の日付）。各操作の正確な時刻は未採録 |
| 環境 | 前段と同じHyper-V VM lab-base01、Ubuntu24.04.4 LTS、opsadmin |
| ツール版 | 前段のAnsible core2.16.3/Python3.12.3を参考とする。今回の再採録は未実施 |
| 作業場所 | `/home/opsadmin/ansible-first-lab`。serverリポジトリ外 |
| Playbook | variables.yml。今回の全文・ハッシュはVMから未取得 |
| 出力 | managed-vars/environment.txt。開始時staging、終了時training |
| 原資料 | [原画像3枚・SHA-256](screenshots/2026-09-09-lab-base01-vars-files/README.md)。連続rawログは未提供 |

## 変数ファイル

catによる本文表示を画像で確認した（[E01]）。ファイル作成コマンドや作成時の終了コードは未採録。

env-training.yml：

```yaml
environment_name: training
```

env-staging.yml：

```yaml
environment_name: staging
```

`-e @env-training.yml`の`@`は、指定ファイルをextra varsとして読み込む指定である。
この演習で指定した値は出力本文に使われ、hostsはlocalhostのまま。

## 確認結果

VF番号は本報告書専用の確認観点ID。

| ID | 観点 | 判定 | 実測結果と限界 |
| --- | --- | --- | --- |
| VF-01 | 変数ファイルと現在値 | PASS | 2ファイルのtraining/staging指定、実ファイルenvironment=staging（[E01]） |
| VF-02 | stagingファイルのcheck | PASS | `-e @env-staging.yml --check --diff`でchanged0/failed0/終了0（[E01]） |
| VF-03 | training予測後の本文 | 部分確認 | [E02]上部にchanged1/failed0/終了0と旧本文staging。予測コマンド・差分全体は画面外 |
| VF-04 | trainingファイルの適用 | PASS | `-e @env-training.yml --diff`でstaging→trainingの差分、directoryはok・fileはchanged、changed1/failed0/終了0、本文training（[E02]） |
| VF-05 | 同一指定の通常再実行 | PASS | `-e @env-training.yml`でok2/changed0/failed0/終了0、本文trainingを維持（[E03]） |

画像で確認した適用と再実行：

```bash
ansible-playbook -i localhost, variables.yml -e @env-training.yml --diff
ansible-playbook -i localhost, variables.yml -e @env-training.yml
```

同じPlaybookを使い、読み込む変数ファイルだけを切り替える手順を案内した。
ただし操作間のvariables.ymlのハッシュ比較は未実施なので、ファイル不変をバイト単位で証明したとは扱わない。
予測時のchangedと実適用のchangedを分けて記録し、画面外の操作を補完しない。

## 終了状態と未実施範囲

- 出力本文はenvironment=training。variables.yml、2つの変数ファイル、managed-varsは復習用に保管する方針。
- 構成ファイル削除や常駐サービス停止が必要な演習ではない。今回の操作範囲はホーム内に限定。
- training適用後にstagingファイルを通常実行して戻す試験は **NOT RUN**。
- 変数ファイル作成時の終了コード、Playbook全文・ハッシュ、権限/所有者の再確認は未採録。
- inventory/group_varsによるホスト別設定、複数VM、リモート構築、Vault、OS/SSH/UFW変更は **NOT RUN**。
- 独力での説明・Playbook記述、全ロールの冪等性を確認した記録ではない。
- 本PRは本人提供画像を整理した文書追加。編集環境で本人VMのAnsibleを再実行したものではない。

- [検証証跡台帳](README.md)
- [前段の実行時変数指定](2026-09-09-lab-base01-variables-practice.md)
- [原画像3枚・ハッシュ](screenshots/2026-09-09-lab-base01-vars-files/README.md)

[E01]: screenshots/2026-09-09-lab-base01-vars-files/E01-files-and-staging.png
[E02]: screenshots/2026-09-09-lab-base01-vars-files/E02-training-apply.png
[E03]: screenshots/2026-09-09-lab-base01-vars-files/E03-training-repeat.png
