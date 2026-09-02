# 変更・ロールバック計画兼記録票

> 💡 **初めて読む方へ**: この文書は設定を変更するとき、「失敗したらどう戻すか」を先に決めておく文書です。案件パック全体の地図は[初心者ガイド](beginner-guide.md#08-変更ロールバック計画兼記録票)を参照してください。

## 1. 位置づけ

一般的な変更区分と PR 運用は [`docs/change-management.md`](../change-management.md)を正本とします。本書はこの構築案件(案件ID `SM-AD-001`、対象ホスト `ad-dc01`)で「どの状態からどの状態へ変更し、どの条件で戻したか」を引き渡せる形で記録する案件固有の計画兼結果票です。

Linux版([`08-change-rollback-plan.md`](../build-package/08-change-rollback-plan.md))はGitのcommit SHAを基準にAnsibleで再配備するロールバックですが、Windows対応Ansible role(`common_windows`等、AD DS対応role相当)がまだ存在しない(`ansible/roles`配下に無い)ため、Linux版のようなcommit SHA基準での単一コマンド再配備は使えません。本書は次の優先順位を正本とします。詳細は[詳細設計書](02-detailed-design.md)「バックアップ・ロールバック」節にも定義しています。

1. **最優先**: VM/ハイパーバイザーのスナップショット復元(Hyper-Vの`Checkpoint-VM`/`Restore-VMCheckpoint`、VMware等)
2. スナップショットが無い場合: 変更前に取得したFirewallルール・レジストリ該当キー等の個別エクスポートの復元
3. データ破損時: Windows Server BackupによるSystem State復元。System State復元には**非権威復元(non-authoritative restore)**と**権威復元(authoritative restore)**の違いがあり、通常の障害復旧では非権威復元を使い、誤って削除したオブジェクトを他のドメインコントローラーからの複製で上書きされないよう戻したい場合に限り権威復元(`ntdsutil` authoritative restore)を検討します。詳細は6節で扱います。

本書が対象とするのは `ad-dc01` 側の変更・ロールバックです。中央監視host(`monitor-01`)側の`app_node_exporter_targets`変数への追記など「済(自動)」の範囲に属する変更のGo/No-Go条件・ロールバック手順は、既存のGit/Ansible基準の手段が使えるため[Linux版変更・ロールバック計画](../build-package/08-change-rollback-plan.md)を正本とします。本書の各節では、`ad-dc01`側の変更に中央側の変更が付随する場合の連携だけを明記します。

この原本の実施欄は初期状態では `NOT RUN` です。実作業では `docs/evidence/YYYY-MM-DD-change-<ID>.md` へコピーし、実際の値と出力を記録します。命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせます。

`ad-dc01`に相当する実ホストの構築そのものがまだ行われていないため、本書に対応する日付付きevidenceは現時点で1件もありません。以下の空欄は次の変更で再利用する原本であり、実ホストでの変更・ロールバックは現在も`NOT RUN`です。

## 2. 変更票

| 項目 | 計画・実績 |
| --- | --- |
| Change ID / 関連 Issue | `NOT SET` |
| 対象環境・ホスト | `NOT SET` |
| 作業者 / 確認者 | `NOT SET` |
| 予定時間 / 実施時間 | `NOT SET` |
| 変更前の状態識別子(スナップショット名 / `Get-ComputerInfo`の`OsBuildNumber`) | `NOT SET` |
| 変更後の状態識別子(スナップショット名 / `OsBuildNumber`) | `NOT SET` |
| 変更目的 | `NOT SET` |
| 影響を受ける service / port / data | `NOT SET` |
| 中央側(`monitor-01`)への影響(`app_node_exporter_targets`追記の要否) | `NOT SET` |
| 停止見込み | `NOT SET` |
| 直前バックアップ ID(スナップショット名 または `wbadmin get versions`のバージョンタイムスタンプ) | `NOT SET` |
| ロールバック判断期限 | `NOT SET` |
| 最終結果 | `NOT RUN` |

## 3. Go / No-Go 条件

次のどれかを満たさなければ実適用を開始しません。

- [ ] 対象ホスト(既定 `ad-dc01`)、変更前後の状態識別子(スナップショット名または`OsBuildNumber`)を相互確認した
- [ ] 秘密値(DSRMパスワード、証明書秘密鍵、特権アカウントのパスワード等)がログや採録に出ないことを確認した
- [ ] `netdom query fsmo`で、FSMO 5役割(スキーママスター、ドメイン名前付けマスター、RIDマスター、PDCエミュレータ、インフラストラクチャマスター)がすべて`ad-dc01`に存在することを確認した
- [ ] `Get-ADDomainController -Filter *`で、`ad-dc01`以外にレプリケーション対象となるドメインコントローラーが存在しない単一DC構成であることを確認した
- [ ] DSRM(ディレクトリサービス復元モード)パスワードが秘密値台帳から利用可能であることを確認した(値そのものはログ・diff・採録へ出さない)
- [ ] VM/ハイパーバイザーのスナップショットが取得できるか確認した。取得できる場合は取得手段・取得先を記録し、取得できない場合は代替として個別エクスポート(Firewall / レジストリ)の取得計画がある
- [ ] 変更対象に対応する単体試験([試験仕様書](06-test-specification.md)の該当AIT/AST ID)が成功した
- [ ] 中央側(`app_node_exporter_targets`等)へ影響する変更の場合、中央host側で`ansible-playbook playbooks/site.yml --check --diff`の差分を確認した
- [ ] データ変更を伴う場合、直前のSystem Stateバックアップの作成時刻と`wbadmin get versions`の出力を確認した
- [ ] 変更前の状態(スナップショットまたはエクスポート一式)から実際に復元できる手段が確保されている
- [ ] ロールバック判断者、判断期限、サービス停止許容時間が決まっている

確認コマンド例です。出力には秘密値を含めません。

```powershell
# 対象ホストの現在状態を記録(変更前)
Get-ComputerInfo | Select-Object CsName, WindowsProductName, OsBuildNumber
Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'
Get-Service NTDS, DNS, Netlogon, Kdc, W32Time | Select-Object Name, Status, StartType

# AD固有の確認: FSMO保持者と単一DC構成
netdom query fsmo
Get-ADDomainController -Filter * | Select-Object Name, Site, IPv4Address

# VMスナップショット取得可否の確認(Hyper-Vの例)
Get-VM -Name 'ad-dc01' | Select-Object State
Get-VMCheckpoint -VMName 'ad-dc01'

# データ変更を伴う場合、直前のSystem State バックアップの状況を確認
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

1. 変更開始時刻と、NTDS・DNS・Netlogon等ディレクトリサービス関連サービスの事前状態、FSMO保持者(`netdom query fsmo`)を記録します。
2. データ変更を伴う場合は直前のSystem Stateバックアップ実行状況(`wbadmin get versions`)を確認します。必要であれば任意タイミングのバックアップを追加取得します。
3. Go / No-Go条件で確保した手段に従い、変更直前にVMスナップショットを取得します(取得できない場合は個別エクスポートを取得します)。
4. [構築手順書](05-build-procedure.md)の該当節に沿って変更を適用します。
5. 中央側(`app_node_exporter_targets`等)に影響する変更の場合は、中央host側で`ansible-playbook playbooks/site.yml`を適用します(既存の「済(自動)」の範囲)。
6. [試験仕様書](06-test-specification.md)の影響範囲の試験を再実行します。AD DS特有の確認として、`Get-Service NTDS,DNS,Netlogon`(AIT-02相当)と`netdom query fsmo`(AIT-05相当)を必ず含めます。
7. Windows Defender Firewall、AD DS関連サービス状態、Directory Service/SystemのEvent Logに新規異常がないことを確認します。
8. 監視時間を終えてから、継続またはロールバックを判定します。

```powershell
# 変更直前のスナップショット取得(Hyper-Vの例。取得タイミングは変更直前)
Checkpoint-VM -Name 'ad-dc01' -SnapshotName "pre-change-$(Get-Date -Format yyyyMMdd-HHmm)"

# スナップショットが使えない場合の個別エクスポート取得
$stamp = Get-Date -Format yyyyMMdd-HHmm
netsh advfirewall export "C:\Backup\firewall-$stamp.wfw"
reg export "HKLM\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" "C:\Backup\ntds-parameters-$stamp.reg"
```

```powershell
# 変更適用後の確認(AD DS特有の確認を含む)
Get-Service NTDS, DNS, Netlogon, Kdc, W32Time | Select-Object Name, Status
netdom query fsmo
Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.corp.example.test" -Type SRV
Get-NetFirewallRule | Where-Object Enabled -eq $true |
  Select-Object DisplayName, Direction, Action, Profile
Get-WinEvent -LogName "Directory Service" -MaxEvents 20 |
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

- NTDSまたはDNSサービスが変更後に起動しない
- `netdom query fsmo`の結果、FSMO 5役割のいずれかの保持者が想定(`ad-dc01`)と異なる
- AD統合DNSゾーンが応答しない(`Resolve-DnsName`によるAレコード・SRVレコードの名前解決が失敗する)
- Netlogonサービスが起動せず、SYSVOL/NETLOGON共有が参照できない
- WinRM(HTTPS)接続が変更後に失敗し、判断期限内に復旧しない
- Windows Defender Firewallの許可範囲が設計外に広がる、または意図せず必要な許可まで閉じる
- 新しい重大なDirectory Service / SystemのEvent Logエラー、継続的なサービス異常が発生する
- 変更適用が途中で失敗し、対象ホストの状態を確定できない
- 実測した復旧見込みが許容停止時間を超える
- 中央側に影響する変更で、中央Prometheus / Grafana側に新規異常が発生する(この場合は本書6節に加え[Linux版変更・ロールバック計画](../build-package/08-change-rollback-plan.md)の手順も併用します)

## 6. 設定のロールバック

Windows対応Ansible roleが無いため、Linux版のような単一コマンドでの再配備はできません。次の優先順位で戻し、各手段のあとに構築後確認([試験仕様書](06-test-specification.md)の影響範囲、特にAIT-02のサービス確認とAIT-05のFSMO確認)を再実行します。

1. **最優先: VM/ハイパーバイザーのスナップショット復元。** 3節のGo / No-Go確認時点で取得済みのスナップショットを前提とします。ロールバック開始時点で新規に取得することはできません。

```powershell
Get-VMCheckpoint -VMName 'ad-dc01'
Restore-VMCheckpoint -VMName 'ad-dc01' -Name '<変更直前に取得したチェックポイント名>' -Confirm:$false
Start-VM -Name 'ad-dc01' -ErrorAction SilentlyContinue
```

2. **スナップショットが無い場合: 4節で取得した個別エクスポートの復元。** Ansibleのように単一コマンドで全体を再現する仕組みが無いため、戻し漏れがないか目視で確認します。

```powershell
netsh advfirewall import "C:\Backup\firewall-<yyyyMMdd-HHmm>.wfw"
reg import "C:\Backup\ntds-parameters-<yyyyMMdd-HHmm>.reg"
Restart-Service NTDS -Force
Restart-Service DNS, Netlogon
```

3. **データ破損時: Windows Server BackupによるSystem State復元。**

System State復元には**非権威復元(non-authoritative restore)**と**権威復元(authoritative restore)**の2種類があり、目的が異なります。**通常の障害復旧**(`ntds.dit`の破損、サービス起動不能等でSystem State全体を戻す場合)では、復元後に他のドメインコントローラーとの複製によって最新状態へ追いつかせる**非権威復元**を使います。一方、誤って削除・変更したオブジェクトを戻す目的でSystem State復元だけを行うと、複製パートナーが存在する構成では、復元直後に他のドメインコントローラーから最新の(削除後の)状態で上書きされてしまいます。この上書きを防ぎ、復元したオブジェクトを正として他のドメインコントローラーへ複製させたい場合に**限り**、`ntdsutil`による**権威復元**を検討します。本パックは単一DC構成(3節で確認するとおり複製対象が存在しない構成)のため、通常のロールバックでは上書きの問題自体が発生しませんが、[基本設計書](01-basic-design.md)2.4節に記す2台目DC追加後の運用を見据え、権威復元の手順もここに記録します。

非権威復元(通常の障害復旧で使用します):

```powershell
wbadmin get versions
wbadmin start systemstaterecovery -version:<復元対象のバージョンタイムスタンプ> -backuptarget:D: -quiet
```

権威復元(誤って削除したオブジェクトを他のドメインコントローラーからの複製で上書きされないよう戻したい場合のみ検討します。非権威復元を先に実行してから、再起動前に`ntdsutil`を実行します):

```powershell
bcdedit /set safeboot dsrepair
shutdown /r /t 0
```

```
REM DSRM Administratorアカウントでログオンし、非権威復元(wbadmin start systemstaterecovery)を先に実行したうえで実行する
ntdsutil
activate instance ntds
authoritative restore
restore subtree "OU=Employees,DC=corp,DC=example,DC=test"
quit
quit
```

```powershell
bcdedit /deletevalue safeboot
shutdown /r /t 0
```

いずれの手段を使った場合も、ロールバック後は`Get-Service NTDS,DNS,Netlogon,Kdc,W32Time`、`netdom query fsmo`、`Resolve-DnsName`で、AD DS関連サービス・FSMO保持者・DNSゾーンの応答をあわせて再確認します。ロールバックの完了確認は、Gitのrevision markerに相当するものが無いため、スナップショット名(またはチェックポイント名)・`OsBuildNumber`・エクスポート/バックアップのタイムスタンプの一致で行います。中央側(`app_node_exporter_targets`)に対する変更のロールバックは、既存のGit/Ansible基準の手段が使えるため[Linux版変更・ロールバック計画](../build-package/08-change-rollback-plan.md)6節の手順に従います。

## 7. データのロールバック

設定を戻すだけではデータ破損を解消できない場合に限り、AD ごみ箱による復元、またはWindows Server BackupによるSystem State復元(6節3)を使用します。両者は次の基準で使い分けます。

- 少数オブジェクトの誤削除・誤変更で、tombstone lifetime(既定180日)以内、かつAD ごみ箱機能(`Enable-ADOptionalFeature 'Recycle Bin Feature'`)が有効な場合は、**AD ごみ箱による復元**(`Get-ADObject -IncludeDeletedObjects`と`Restore-ADObject`、AIT-07相当)を優先します。ダウンタイムが無く、対象オブジェクト以外の変更を巻き戻さないためです。
- `ntds.dit`自体の破損、AD ごみ箱で戻せない範囲の欠損(機能無効時、tombstone lifetime超過、System State全体の不整合)の場合は、**System State復元**(6節3、原則として非権威復元)を使用します。
- AD ごみ箱でも復元できず、かつ誤って削除したオブジェクトを他のドメインコントローラーからの複製で上書きされないよう確実に戻す必要がある場合に限り、6節3の**権威復元**(`ntdsutil` authoritative restore)を検討します。単一DC構成の本パックでは複製パートナーが存在しないためこの状況は通常発生しませんが、判断基準として記録します。

復元作業では次の点を確認します。

- 破損した対象(SYSVOL配下ファイル、`ntds.dit`格納ボリューム、バックアップ格納先ボリューム)を直ちに削除せず、調査用に識別・隔離します。
- 復元元アーカイブの日時(`wbadmin get versions`のバージョンタイムスタンプ)、格納先、RPOを記録します。
- 別ボリュームまたは別ホストへ復元して内容を確認してから本来の対象へ切り替えます([試験仕様書](06-test-specification.md)のAIT-06と同じ検証の考え方です)。
- 秘密値(DSRMパスワード等)はバックアップアーカイブではなく、承認された秘密管理先から復元します。
- サービス停止復旧演習(AIT-08相当)の実測証跡はあっても、ホスト障害からのSystem State復元(AIT-06)・AD ごみ箱復元(AIT-07)の実測証跡がない間は、ホスト障害からの復元を「検証済み」と記載しません。

## 8. 実施結果

| 時刻 | 操作 / 判断 | コマンドまたは証跡 | 結果 |
| --- | --- | --- | --- |
| `NOT RUN` | 変更前確認(スナップショット / エクスポート取得含む) | — | NOT RUN |
| `NOT RUN` | 変更適用 | — | NOT RUN |
| `NOT RUN` | 適用後試験 | — | NOT RUN |
| `NOT RUN` | 継続 / ロールバック判断 | — | NOT RUN |
| `NOT RUN` | ロールバック（必要時） | — | NOT RUN |

## 9. 終了条件

- [ ] 変更後またはロールバック後の状態識別子(スナップショット名 / チェックポイント名 / `OsBuildNumber` / バックアップのバージョンタイムスタンプ)と稼働状態が一致する
- [ ] 必須smoke testと影響範囲の再試験([試験仕様書](06-test-specification.md))が`PASS`(AD DS関連サービスの起動状態とFSMO保持者の確認を含む)
- [ ] 変更前後の時刻、実出力、判断理由をevidenceへ保存した(命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせる)
- [ ] 残存リスク、暫定対応、恒久対応のIssueを記録した
- [ ] 一時的なFirewall許可、DSRMブート設定(`bcdedit /set safeboot`)、試験データ、保守モードを解除した