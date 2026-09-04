# 変更・ロールバック計画兼記録票

## 1. 位置づけ

一般的な変更区分とPR運用は[`docs/change-management.md`](../change-management.md)を正本とします。本書は本案件(案件ID`SM-WSUS-001`、対象ホスト`wsus-01`)固有の変更計画・実施記録票です。

Windows対応Ansible roleが`ansible/roles`に無く、Linux版([`08-change-rollback-plan.md`](../build-package/08-change-rollback-plan.md))のcommit SHA基準再配備は使えないため、[Windows版](../build-package-windows/08-change-rollback-plan.md)・[AD版](../build-package-ad/08-change-rollback-plan.md)と同じ優先順位を採ります(詳細は[詳細設計書](02-detailed-design.md)「バックアップ・ロールバック」節)。最優先はVM/ハイパーバイザーのスナップショット復元、無ければFirewall・GPO(`Backup-GPO`)のエクスポートと承認ルール・コンピューターグループの記録値からの手動復元、データ破損時はSUSDB(WID)・コンテンツストアからの復元です。

対象は`wsus-01`側の変更です。中央側(`monitor-01`)の`app_node_exporter_targets`追記は、フェーズ2が未実装3点の解消まで`BLOCKED`のため発生せず、発生時は[Linux版変更・ロールバック計画](../build-package/08-change-rollback-plan.md)を正本とします。

実施欄は初期状態`NOT RUN`です。実作業では`docs/evidence/YYYY-MM-DD-change-<ID>.md`へコピーして記録します(命名・記録ルールは[検証証跡台帳](../evidence/README.md))。`wsus-01`の実ホスト構築自体が未了のため対応evidenceは現時点で無く、[AD版パック](../build-package-ad/README.md)のような実機評価済みの体裁は取らず、[Windows版パック](../build-package-windows/08-change-rollback-plan.md)と同じ「作成済みだが未実施」の状態を保ちます。

## 2. 変更票

| 項目 | 計画・実績 |
| --- | --- |
| Change ID / 関連 Issue | `NOT SET` |
| 対象環境・ホスト | `NOT SET` |
| 変更種別(GPO / 承認ルール・コンピューターグループ / 同期設定 / WsusPoolチューニング / その他) | `NOT SET` |
| 作業者 / 確認者 | `NOT SET` |
| 予定時間 / 実施時間 | `NOT SET` |
| 変更前後の状態識別子(チェックポイント名 / `OsBuildNumber`) | `NOT SET` |
| 変更目的 / 影響を受ける service・port・data | `NOT SET` |
| 変更前のコンテンツストア空き容量(`D:`) | `NOT SET` |
| GPO変更時の直前`Backup-GPO`ID / 承認ルール・コンピューターグループ変更時の記録有無 | `NOT SET` |
| 中央側(`monitor-01`)への影響 | `NOT SET`(フェーズ2`BLOCKED`のため通常無し) |
| 停止見込み / ロールバック判断期限 | `NOT SET` |
| 直前バックアップID(VMチェックポイント / `wbadmin`バージョン) | `NOT SET` |
| 最終結果 | `NOT RUN` |

## 3. Go/No-Go条件

- [ ] 対象ホスト、変更前後の状態識別子を相互確認した。秘密値(サービスアカウント・Administrator等のパスワード)がログや採録に出ないことも確認した
- [ ] `WsusService`・`W3SVC`・`WinRM`が正常稼働であること、コンテンツストア(`D:`)の空き容量を確認した
- [ ] GPO変更時は直前に`Backup-GPO`を、承認ルール・コンピューターグループ変更時は変更前の値を本書2節または画面キャプチャで記録した。WSUSには`Backup-GPO`相当のエクスポート機能が無く、記録漏れは手戻りになる
- [ ] VMスナップショットが取得できるか確認した(できない場合は個別エクスポートの取得計画がある)
- [ ] 変更対象に対応する試験([試験仕様書](06-test-specification.md)の該当SUT/SIT ID)が成功した
- [ ] データ変更時は直前のバックアップ取得時刻を確認した
- [ ] 復元できる手段が確保され、ロールバック判断者・判断期限・停止許容時間が決まっている

```powershell
Get-Service WsusService, W3SVC, WinRM | Select-Object Name, Status
Backup-GPO -Name "WSUS-Client-Policy" -Path "C:\Backup\gpo-$(Get-Date -Format yyyyMMdd-HHmm)"
```

## 4. 変更手順

1. 変更開始時刻、対象サービスの事前状態、コンテンツストア空き容量を記録します。
2. GPO変更時は`Backup-GPO`を、承認ルール・コンピューターグループ変更時は変更前の値を本書2節へ記録し、必要ならバックアップを追加取得します。
3. 変更直前にVMスナップショットを取得します(できない場合は個別エクスポート)。
4. [構築手順書](05-build-procedure.md)の該当節に沿って変更を適用します。
5. [試験仕様書](06-test-specification.md)の影響範囲の試験(GPOならSIT-04、承認ルールならSIT-05・06等)を再実行します。
6. Firewall、対象サービス(`WsusPool`含む)状態、グループポリシー操作ログ・WSUS同期ログに新規異常がないことを確認します。
7. 監視時間を終えてから継続またはロールバックを判定します。

```powershell
Checkpoint-VM -Name 'wsus-01' -SnapshotName "pre-change-$(Get-Date -Format yyyyMMdd-HHmm)"
Get-IISAppPool WsusPool | Select-Object Name, State
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:8530/ClientWebService/client.asmx
```

## 5. ロールバック開始条件

次のいずれかが判断期限までに解消しない場合、変更を継続せず戻します。

- `WsusService`が起動しない、または`wsusutil`によるコンソール接続がエラーになる
- `WsusPool`が停止/クラッシュし、WSUS管理サイト(8530)がクライアント同期要求に応答しない(503含む)
- Microsoft Updateとの同期が継続的に失敗する
- GPOのクライアント側ターゲティングが崩れ、`wsus-01`自身がWSUSコンソールの`Servers`グループへ自己登録できない
- 承認ルールの対象範囲が設計(分類Critical/Security、製品Windows Server 2022、対象`Pilot`)を超え、意図しない更新が自動承認・配布される
- コンテンツストア(`D:`)の空き容量が枯渇した、またはその見込みが立った
- WinRM(HTTPS)接続が期限内に復旧しない、Firewall許可範囲が設計外に広がる/必要な許可まで閉じる
- 重大なEvent Logエラー・継続的なサービス異常、途中失敗で状態を確定できない、実測復旧見込みが許容停止時間を超える

## 6. 設定のロールバック

Windows対応Ansible roleが無く単一コマンド再配備はできません。次の優先順位で戻し、各手段のあとに構築後確認([試験仕様書](06-test-specification.md)の影響範囲)を再実行します。

1. **最優先: VMスナップショット復元。** 3節で取得済みのものが前提で、ロールバック開始時点での新規取得はできません。

```powershell
Restore-VMCheckpoint -VMName 'wsus-01' -Name '<変更直前のチェックポイント名>' -Confirm:$false
Start-VM -Name 'wsus-01' -ErrorAction SilentlyContinue
```

2. **スナップショットが無い場合: 個別エクスポート・記録値からの復元。** GPOと、承認ルール・コンピューターグループとで戻し方が異なります。

**例A(GPO変更)**: 「自動更新を構成する」をオプション3から4へ誤変更、または更新サービスの場所URLを誤入力した想定です。4節の`Backup-GPO`から戻します。

```powershell
Restore-GPO -BackupId "<Backup-GPOの出力IDを指定>" -Path "C:\Backup\gpo-<yyyyMMdd-HHmm>"
gpupdate /force
```

**例B(承認ルール・コンピューターグループ変更)**: 自動承認ルール「Critical and Security Updates - Pilot Auto-Approve」の対象グループを誤って`Pilot`から`Servers`へ広げてしまった想定です。WSUSには`Restore-GPO`相当の一括復元機能が無く、コンソール上で対象グループを記録値(`Pilot`)へ手動で戻します。承認済みなら対象更新を「承認の取り消し」へ変更し、グループ階層自体の誤変更(ADのOUとは別概念)も手動で作り直し、記録値と画面上の設定を突き合わせます。

3. **データ破損時: SUSDB・コンテンツストアからの復元(7節参照)。**

いずれの手段でも、戻した後は対象サービス状態とEvent Logを再確認します。Gitのrevision markerに相当するものが無いため、完了確認はチェックポイント名・`OsBuildNumber`・バックアップのタイムスタンプ・記録済み設定値との一致で行います。

## 7. データのロールバック

設定を戻すだけでは解消できない場合に限り、SUSDB(WID)・コンテンツストアの復元を使用します。検証方針は[バックアップ・復旧設計](../backup-restore.md)の別volume復元(復元して内容を確認してから切り替える)に準じます。

- SUSDB(WID)は、WIDのローカル名前付きパイプ(`MICROSOFT##WID`への接続)経由のバックアップからの復元、または`wsus-01`全体をWindows Server Backupでシステム状態含めて復元する方式のいずれかを設計として示します。実機で選定するため現時点`NOT SET`です。
- コンテンツストア(`D:\WSUS\WSUSContent`)は、フォルダー全体のバックアップから`wbadmin`のファイル復元、または別途取得したコピーから復元します。

```powershell
wbadmin get versions
wbadmin start recovery -version:<復元対象のバージョンタイムスタンプ> -itemtype:File `
  -items:D:\WSUS\WSUSContent -recoveryTarget:D:\WSUS\WSUSContent -notrestoresecurity
Restart-Service WsusService, W3SVC
```

- 破損対象を直ちに削除せず調査用に隔離し、復元元アーカイブの日時・格納先・RPOを記録します。格納先は別ボリューム推奨で、実機で決定するため`NOT SET`です。
- 別ボリュームまたは別ホストへ復元して内容を確認してから本来の対象へ切り替えます(SIT-08と同じ考え方)。秘密値はバックアップアーカイブではなく承認された秘密管理先から復元します。
- SIT-08の実測証跡がない間は、データ復元を「検証済み」と記載しません。復元後は承認状況・コンピューターグループ・自動承認ルールが復元前の記録値と一致するかもあわせて確認します。

## 8. 実施結果

| 時刻 | 操作 / 判断 | コマンドまたは証跡 | 結果 |
| --- | --- | --- | --- |
| `NOT RUN` | 変更前確認(スナップショット / エクスポート取得含む) | — | NOT RUN |
| `NOT RUN` | 変更適用 | — | NOT RUN |
| `NOT RUN` | 適用後試験 | — | NOT RUN |
| `NOT RUN` | 継続 / ロールバック判断 | — | NOT RUN |
| `NOT RUN` | ロールバック(必要時) | — | NOT RUN |

## 9. 終了条件

- [ ] 変更後またはロールバック後の状態識別子(チェックポイント名 / `OsBuildNumber` / バックアップのバージョンタイムスタンプ)と稼働状態が一致する
- [ ] 必須smoke testと影響範囲の再試験([試験仕様書](06-test-specification.md))が`PASS`
- [ ] GPO・承認ルール・コンピューターグループを変更した場合、バックアップまたは記録値と現在の設定が一致する
- [ ] 変更前後の時刻、実出力、判断理由をevidenceへ保存した(命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせる)
- [ ] 残存リスク、暫定対応、恒久対応のIssueを記録した
- [ ] 一時的なFirewall許可、試験データ、保守モードを解除した
