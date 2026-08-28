# 変更・ロールバック計画兼記録票

## 1. 位置づけ

一般的な変更区分と PR 運用は [`docs/change-management.md`](../change-management.md)を正本とします。本書はこの構築案件(案件ID `SM-WIN-001`、対象ホスト `monitor-win-01`)で「どの状態からどの状態へ変更し、どの条件で戻したか」を引き渡せる形で記録する案件固有の計画兼結果票です。

Linux版([`08-change-rollback-plan.md`](../build-package/08-change-rollback-plan.md))はGitのcommit SHAを基準にAnsibleで再配備するロールバックですが、Windows対応Ansible role(`common_windows`等)がまだ存在しない(`ansible/roles`配下に無い)ため、本書は次の優先順位を正本とします。詳細は[詳細設計書](02-detailed-design.md)「バックアップ・ロールバック」節にも定義しています。

1. **最優先**: VM/ハイパーバイザーのスナップショット復元(Hyper-Vの`Checkpoint-VM`/`Restore-VMCheckpoint`、VMware等)
2. スナップショットが無い場合: 変更前に取得したFirewallルール・レジストリ該当キー・IIS設定の個別エクスポートの復元
3. データ破損時: Windows Server Backupからの復元

本書が対象とするのは `monitor-win-01` 側の変更・ロールバックです。中央監視host(`monitor-01`)側の`app_node_exporter_targets`変数への追記など「済(自動)」の範囲に属する変更のGo/No-Go条件・ロールバック手順は、既存のGit/Ansible基準の手段が使えるため[Linux版変更・ロールバック計画](../build-package/08-change-rollback-plan.md)を正本とします。本書の各節では、`monitor-win-01`側の変更に中央側の変更が付随する場合の連携だけを明記します。

この原本の実施欄は初期状態では `NOT RUN` です。実作業では `docs/evidence/YYYY-MM-DD-change-<ID>.md` へコピーし、実際の値と出力を記録します。命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせます。

`monitor-win-01`に相当する実ホストの構築そのものがまだ行われていないため、本書に対応する日付付きevidenceは現時点で1件もありません。以下の空欄は次の変更で再利用する原本であり、実ホストでの変更・ロールバックは現在も`NOT RUN`です。

## 2. 変更票

| 項目 | 計画・実績 |
| --- | --- |
| Change ID / 関連 Issue | `NOT SET` |
| 対象環境・ホスト | `NOT SET` |
| 作業者 / 確認者 | `NOT SET` |
| 予定時間 / 実施時間 | `NOT SET` |
| 変更前の状態識別子(チェックポイント名 / `Get-ComputerInfo`の`OsBuildNumber`) | `NOT SET` |
| 変更後の状態識別子(チェックポイント名 / `OsBuildNumber`) | `NOT SET` |
| 変更目的 | `NOT SET` |
| 影響を受ける service / port / data | `NOT SET` |
| 中央側(`monitor-01`)への影響(`app_node_exporter_targets`追記の要否) | `NOT SET` |
| 停止見込み | `NOT SET` |
| 直前バックアップ ID(スナップショット名 または `wbadmin get versions`のバージョンタイムスタンプ) | `NOT SET` |
| ロールバック判断期限 | `NOT SET` |
| 最終結果 | `NOT RUN` |

## 3. Go / No-Go 条件

次のどれかを満たさなければ実適用を開始しません。

- [ ] 対象ホスト(既定 `monitor-win-01`)、変更前後の状態識別子(チェックポイント名または`OsBuildNumber`)を相互確認した
- [ ] 秘密値(証明書秘密鍵、ローカルAdministrator/ドメインアカウントのパスワード等)がログや採録に出ないことを確認した
- [ ] VM/ハイパーバイザーのスナップショットが取得できるか確認した。取得できる場合は取得手段・取得先を記録し、取得できない場合は代替として個別エクスポート(Firewall / レジストリ / IIS)の取得計画がある
- [ ] 変更対象に対応する単体試験([試験仕様書](06-test-specification.md)のWUT-01〜WUT-05のうち該当するもの)が成功した
- [ ] 中央側(`app_node_exporter_targets`等)へ影響する変更の場合、中央host側で`ansible-playbook playbooks/site.yml --check --diff`の差分を確認した(WUT-02相当)
- [ ] データ変更を伴う場合、直前のWindows Server Backupの作成時刻と`wbadmin get versions`の出力を確認した
- [ ] 変更前の状態(スナップショットまたはエクスポート一式)から実際に復元できる手段が確保されている
- [ ] ロールバック判断者、判断期限、サービス停止許容時間が決まっている

確認コマンド例です。出力には秘密値を含めません。

```powershell
# 対象ホストの現在状態を記録(変更前)
Get-ComputerInfo | Select-Object CsName, WindowsProductName, OsBuildNumber
Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'
Get-Service windows_exporter, W3SVC, WinRM | Select-Object Name, Status, StartType

# VMスナップショット取得可否の確認(Hyper-Vの例)
Get-VM -Name 'monitor-win-01' | Select-Object State
Get-VMCheckpoint -VMName 'monitor-win-01'

# データ変更を伴う場合、直前のWindows Server Backupの状況を確認
wbadmin get versions
```

中央側(`app_node_exporter_targets`)へ影響する変更の場合のみ、中央host側で追加確認します。

```bash
BEFORE_SHA='replace-with-the-full-current-commit-sha-of-the-central-repo'
git -C ansible rev-parse HEAD
cd ansible
ansible-inventory -i inventory/staging.local.yml --graph
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml --check --diff
```

## 4. 変更手順

1. 変更開始時刻と、windows_exporter・IIS(`W3SVC`)・WinRMの各サービスの事前状態を記録します。
2. データ変更を伴う場合は直前のWindows Server Backup実行状況を確認します。必要であれば任意タイミングのバックアップを追加取得します。
3. Go / No-Go条件で確保した手段に従い、変更直前にVMスナップショットを取得します(取得できない場合は個別エクスポートを取得します)。
4. [構築手順書](05-build-procedure.md)の該当節に沿って変更を適用します。
5. 中央側(`app_node_exporter_targets`等)に影響する変更の場合は、中央host側で`ansible-playbook playbooks/site.yml`を適用します(既存の「済(自動)」の範囲)。
6. [試験仕様書](06-test-specification.md)の影響範囲の試験を再実行します。
7. Windows Defender Firewall、windows_exporter / IIS / WinRMの各サービス状態、Event Logに新規異常がないことを確認します。
8. 監視時間を終えてから、継続またはロールバックを判定します。

```powershell
# 変更直前のスナップショット取得(Hyper-Vの例。取得タイミングは変更直前)
Checkpoint-VM -Name 'monitor-win-01' -SnapshotName "pre-change-$(Get-Date -Format yyyyMMdd-HHmm)"

# スナップショットが使えない場合の個別エクスポート取得
$stamp = Get-Date -Format yyyyMMdd-HHmm
netsh advfirewall export "C:\Backup\firewall-$stamp.wfw"
& "$env:windir\system32\inetsrv\appcmd.exe" add backup "pre-change-$stamp"
reg export "HKLM\SYSTEM\CurrentControlSet\Services\windows_exporter" "C:\Backup\windows_exporter-svc-$stamp.reg"
```

```powershell
# 変更適用後の確認
Get-Service windows_exporter, W3SVC, WinRM | Select-Object Name, Status
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost/healthz.html
curl.exe -s http://localhost:9182/metrics | Select-String "windows_cs_hostname"
Get-NetFirewallRule | Where-Object Enabled -eq $true |
  Select-Object DisplayName, Direction, Action, Profile
Get-WinEvent -LogName System -MaxEvents 20 |
  Where-Object { $_.LevelDisplayName -eq 'Error' }
```

```bash
# 中央側(app_node_exporter_targets)に影響する変更の場合のみ、中央host側で実行
cd ansible
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml --check --diff
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml
```

## 5. ロールバック開始条件

次のいずれかが発生し、判断期限までに安全に解消できない場合は変更を継続せず戻します。

- WinRM(HTTPS)接続が変更後に失敗し、判断期限内に復旧しない
- IISのhealth用エンドポイントが規定時間内に200を返さない
- windows_exporterサービスが起動しない、または`/metrics`が返らない
- Windows Defender Firewallの許可範囲が設計外に広がる、または意図せず必要な許可まで閉じる
- 新しい重大なEvent Logエラー、継続的なサービス異常が発生する
- 変更適用が途中で失敗し、対象ホストの状態を確定できない
- 実測した復旧見込みが許容停止時間を超える
- 中央側に影響する変更で、中央Prometheus / Grafana側に新規異常が発生する(この場合は本書6節に加え[Linux版変更・ロールバック計画](../build-package/08-change-rollback-plan.md)の手順も併用します)

## 6. 設定のロールバック

Windows対応Ansible roleが無いため、Linux版のような単一コマンドでの再配備はできません。次の優先順位で戻し、各手段のあとに構築後確認([試験仕様書](06-test-specification.md)の影響範囲)を再実行します。

1. **最優先: VM/ハイパーバイザーのスナップショット復元。** 3節のGo / No-Go確認時点で取得済みのスナップショットを前提とします。ロールバック開始時点で新規に取得することはできません。

```powershell
Get-VMCheckpoint -VMName 'monitor-win-01'
Restore-VMCheckpoint -VMName 'monitor-win-01' -Name '<変更直前に取得したチェックポイント名>' -Confirm:$false
Start-VM -Name 'monitor-win-01' -ErrorAction SilentlyContinue
```

2. **スナップショットが無い場合: 4節で取得した個別エクスポートの復元。** `appcmd restore backup`はIIS構成のみを戻すため、Firewallルールとレジストリキーは別コマンドで個別に戻す必要があります。Ansibleのように単一コマンドで全体を再現する仕組みが無いため、戻し漏れがないか目視で確認します。

```powershell
netsh advfirewall import "C:\Backup\firewall-<yyyyMMdd-HHmm>.wfw"
& "$env:windir\system32\inetsrv\appcmd.exe" restore backup "pre-change-<yyyyMMdd-HHmm>"
reg import "C:\Backup\windows_exporter-svc-<yyyyMMdd-HHmm>.reg"
Restart-Service windows_exporter, W3SVC
```

3. **データ破損時: Windows Server Backupからの復元(7節参照)。**

```powershell
wbadmin get versions
wbadmin start recovery -version:<復元対象のバージョンタイムスタンプ> -itemtype:File `
  -items:C:\inetpub -recoveryTarget:C:\inetpub -notrestoresecurity
Restart-Service W3SVC
```

いずれの手段を使った場合も、ロールバック後はWindows Defender Firewall、windows_exporter / IIS / WinRMの各サービス状態、Event Logを再確認します。ロールバックの完了確認は、Gitのrevision markerに相当するものが無いため、チェックポイント名・`OsBuildNumber`・エクスポート/バックアップのタイムスタンプの一致で行います。中央側(`app_node_exporter_targets`)に対する変更のロールバックは、既存のGit/Ansible基準の手段が使えるため[Linux版変更・ロールバック計画](../build-package/08-change-rollback-plan.md)6節の手順に従います。

## 7. データのロールバック

設定を戻すだけではデータ破損を解消できない場合に限り、Windows Server Backupからの復元(6節3)を使用します。復元の検証方針は[バックアップ・復旧設計](../backup-restore.md)の別volume復元(復元して内容を確認してから切り替える)の考え方に準じ、対象はWindows Server BackupのアーカイブおよびIISサイトの内容・設定とします。

- 破損した対象(IISコンテンツ、windows_exporter関連ファイル、バックアップ格納先ボリューム)を直ちに削除せず、調査用に識別・隔離します。
- 復元元アーカイブの日時(`wbadmin get versions`のバージョンタイムスタンプ)、格納先、RPOを記録します。
- 別ボリュームまたは別ホストへ復元して内容を確認してから本来の対象へ切り替えます([試験仕様書](06-test-specification.md)のWIT-09と同じ検証の考え方です)。
- 秘密値(証明書秘密鍵、パスワード)はバックアップアーカイブではなく、承認された秘密管理先から復元します。
- サービス停止復旧演習(WIT-08、D-1相当)の実測証跡はあっても、ホスト障害からのデータ復元(WIT-09)の実測証跡がない間は、ホスト障害からの復元を「検証済み」と記載しません。

## 8. 実施結果

| 時刻 | 操作 / 判断 | コマンドまたは証跡 | 結果 |
| --- | --- | --- | --- |
| `NOT RUN` | 変更前確認(スナップショット / エクスポート取得含む) | — | NOT RUN |
| `NOT RUN` | 変更適用 | — | NOT RUN |
| `NOT RUN` | 適用後試験 | — | NOT RUN |
| `NOT RUN` | 継続 / ロールバック判断 | — | NOT RUN |
| `NOT RUN` | ロールバック（必要時） | — | NOT RUN |

## 9. 終了条件

- [ ] 変更後またはロールバック後の状態識別子(チェックポイント名 / `OsBuildNumber` / バックアップのバージョンタイムスタンプ)と稼働状態が一致する
- [ ] 必須smoke testと影響範囲の再試験([試験仕様書](06-test-specification.md))が`PASS`
- [ ] 変更前後の時刻、実出力、判断理由をevidenceへ保存した(命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせる)
- [ ] 残存リスク、暫定対応、恒久対応のIssueを記録した
- [ ] 一時的なFirewall許可(RDPの一時有効化含む)、試験データ、保守モードを解除した
