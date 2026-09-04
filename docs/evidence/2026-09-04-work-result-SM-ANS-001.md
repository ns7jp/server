# 作業結果・引き渡し報告書 — SM-ANS-001（2026-09-04 記入版）

[原本](../build-package-ansible/11-work-result-report.md)をコピーし、`ans-01`への`foundation.yml`初回構築の結果を記入したものです。

## 1. 案件概要

| 項目 | 値 |
| --- | --- |
| 案件ID | `SM-ANS-001` |
| 案件名 | Ansible自動化基盤構築案件パック |
| 対象ホスト | `ans-01`（`192.168.11.95`、Hyper-V VM、Ubuntu 24.04.4 LTS） |
| 報告日 | 2026-09-04 |
| 報告者 | ns7jp |

## 2. 計画対実績

| 項目 | 計画（設計値） | 実績 | 差異 |
| --- | --- | --- | --- |
| 対象OS | Ubuntu Server 24.04 LTS | Ubuntu 24.04.4 LTS（Hyper-V Quick Create gallery image） | 差異なし |
| 適用方式 | `ansible/playbooks/foundation.yml` | 同左（WSL2上のAnsible controllerから適用） | 差異なし |
| 初回適用 | `failed=0` | `ok=55 changed=5 failed=0 skipped=14` | 差異なし |
| 2回目適用 | `changed=0` | `ok=54 changed=0 failed=0 skipped=14` | 差異なし |
| 所要時間 | `NOT SET`（初回参考値なし） | 初回適用は数分程度（Docker Engine導入を含む。1 vCPU/1GB相当の小規模VMのため） | 参考値として記録 |

## 3. 試験集計

集計元は[2026-09-04構築・試験結果票](2026-09-04-ansible-foundation-build.md)です。

| 分類 | 件数 | PASS | FAIL | BLOCKED | NOT RUN |
| --- | --- | --- | --- | --- | --- |
| AFUT（単体・構成） | 5 | 5 | 0 | 0 | 0 |
| AFIT（構築・結合） | 7 | 6 | 0 | 1（AFIT-06） | 0 |
| AFST（セキュリティ） | 7 | 5 | 0 | 1（AFST-06） | 1（AFST-07、任意項目） |
| AFNW（ネットワーク実機検証） | 6 | 5 | 0 | 0 | 1（AFNW-06、任意項目） |

**フェーズ1必須ID（AFUT-01〜05、AFIT-01〜05、AFIT-07、AFST-01〜05）は16/16すべて`PASS`。** 残るBLOCKED/NOT RUNはフェーズ2（AFIT-06・AFST-06）と任意項目（AFST-07・AFNW-06）のみ。

## 4. 設計との差異

| 項目 | 設計値 | 実績値 | 差異の理由 |
| --- | --- | --- | --- |
| `common_admin_sudo_nopasswd` | 未設定（既定`false`） | `foundation` group既定値へ`true`を追加 | 4節・5節参照 |

## 5. 障害・トラブル

| 発生日 | 内容 | 原因 | 対応 | 再発防止 |
| --- | --- | --- | --- | --- |
| 2026-09-04 | Hyper-V Quick CreateのVMが起動直後、`eth0`が`DOWN`でIPv4が付かなかった | VMイメージに`/etc/netplan/`設定が1つも存在せず、systemd-networkdが`eth0`を管理していなかった（`unmanaged`） | `dhcp4: true`のnetplan設定を手動作成し`netplan apply` | 案件パックの欠陥ではなくVMイメージ側の初期状態。[10-host-bringup-and-acceptance.md](../build-package-ansible/10-host-bringup-and-acceptance.md)への注記を検討 |
| 2026-09-04 | `common` roleが作る`ansible-admin`アカウントのsudoが恒久的に失敗する（パスワード未設定 + `common_admin_sudo_nopasswd`既定`false`） | roleの設計がVaultを使わない前提のため、鍵以外の認証要素を渡す手段が無いままsudoにpasswordを要求していた | `group_vars/foundation/main.yml`へ`common_admin_sudo_nopasswd: true`を追加 | [欠陥台帳](defects-found.md)#30に記録。同様の管理者アカウントを持つ他パックへの展開時は同じ確認をする |

## 6. 残存リスク

| リスク | 影響 | 対応方針 |
| --- | --- | --- |
| AlmaLinux/Rocky 9実機ホストでの構築が未実施 | RHEL系での動作保証がMoleculeのコンテナ検証にとどまる | フェーズ2としてVM用意後に着手 |
| `foundation.yml`合成後のCI自動検証が無い | role単体は検証されるが、組み合わせた際の実コンテナ収束はこの日付付き証跡（人手実施）に依存 | `ansible-integration.yml`への追加を検討 |
| AFNW-06（rate limit、任意）が未実施 | rate limit機能自体はUFW/firewalldの設定として確認済みだが、実際の発火は未確認 | 対象ホストへの負荷を許容できる場面で実施 |
| 再起動後の設定保持は未確認 | 恒久稼働時の挙動が未実証 | [10-host-bringup-and-acceptance.md](../build-package-ansible/10-host-bringup-and-acceptance.md)の手順で別途確認 |

## 7. 完了判定

| 判定 | 状態 |
| --- | --- |
| フェーズ1（Ubuntu）完了 | **`PASS`**。必須ID16/16すべて`PASS`（[結果票](2026-09-04-ansible-foundation-build.md)） |
| フェーズ2（RHEL系）完了 | `NOT SET`（着手前） |
| 引き渡し完了 | ラボ範囲で完了（引き渡し元/先とも本人）。組織環境への引き渡しは`NOT RUN` |
