# AD System State 復元演習と、その途中で起きたインシデントの記録 — 2026-09-02

[作業結果・引き渡し報告](2026-09-02-work-result-SM-AD-001.md)の残存リスク「System Stateからの**復元**は未実施」を解消するために実施した演習の記録です。演習の途中で DC が強制停止するインシデントが起き、その切り分けと、そこから派生して見つかった設定の欠陥(GPO によるレジストリ上書き)も同じ記録に残します。試験IDとしては[試験仕様書](../build-package-ad/06-test-specification.md)に本PRで追加した `AIT-12(任意)` に対応します。

> **この証跡が示す範囲**: 手元 Hyper-V 上の VM 1台(`ad-dc01`)での非権威復元です。複数DC環境での権威復元、USN ロールバック、SYSVOL の複製回復は含みません。

## 結果の要約

| 項目 | 結果 |
| --- | --- |
| 判定 | **PASS**(バックアップ後に作った目印 OU が復元で消え、バックアップ時点の OU・FSMO・サービスは無傷) |
| バックアップ(System State 約8GB → D:) | 24分45秒 |
| 復元処理(`wbadmin start systemstaterecovery`) | **15分29秒**(Backup ログ 213/240 → 241/242: 15:19:58 → 15:35:27) |
| 復旧全体(DSRM 再起動の指示 → 通常起動で全サービス `Running`) | **約40分**(T0 = 15:17 → 15:55:52 起動 → 15:57 確認完了)。うち約18分は `safeboot` 解除漏れによる DSRM 再起動のやり直し。やり直しが無ければ約22分 |
| 途中で起きたインシデント | 1回目のバックアップ中に Hyper-V が VM を一時停止 → 強制停止(下記 LAB-11) |
| 派生して見つかった欠陥 | GPO が `LDAPServerIntegrity` を「なし」に上書きしていた(LAB-12) |

## タイムライン(JST)

| 時刻 | 出来事 |
| --- | --- |
| 11:35 | チェックポイント `before-restore-drill` を取得(この時点でチェーンは5世代) |
| 11:36 | ホストPCから `Invoke-Command` 経由で `wbadmin start systemstatebackup` を開始 |
| 12:22 頃 | 進捗56%で WinRM セッション切断(`PSSessionStateBroken`)。以後 ping も不通 |
| 12:23:26 | **[ホスト] イベント 12636/12635**: `ad-dc01-backup_...avhdx` が回復性エラー(状態 `Disconnected`)。**18524**: 重大なエラーのため VM を一時停止 |
| 13:05:13 | **[ホスト] イベント 18528**: 回復できず VM を無効化(強制停止) |
| 13:15 | VM を起動。ゲストの System ログに 6008(予期しないシャットダウン)、41(Kernel-Power) |
| 13:2x | 切り分け: `dcdiag /q` はログ由来の失敗のみ、NTDS の JET/ESE エラーなし。`Directory Service` ログに警告 2886/3051/3054 → `LDAPServerIntegrity` を確認すると **1** に戻っている |
| 13:3x | `Get-GPOReport` で Default Domain Controllers Policy が「LDAP サーバー署名必須 = なし」を定義していることを確認(LAB-12 確定)。GPMC で「署名必須」へ変更、`gpupdate /force` 後にレジストリ 2、`secedit` 実効値 `=4,2` |
| 13:3x〜 | チェックポイント4世代を `Remove-VMSnapshot` で統合(`phase1-complete` のみ残す)。C: 空き 56 → 60.9 GB。`Set-VM -AutomaticCheckpointsEnabled $false` |
| 13:5x | VM 再起動。起動後、警告 2886 なし、`LDAPServerIntegrity = 2` を確認 |
| 14:16〜14:40 | VM コンソールで `wbadmin start systemstatebackup`(出力はファイルへ)。**24分45秒で完了**。バージョン識別子 `09/02/2026-05:16`(UTC 表記) |
| 14:4x | 目印 OU `RestoreDrill-Marker` を作成(`whenCreated` がバックアップ後) |
| **15:17** | `bcdedit /set safeboot dsrepair` → 再起動(**T0**、作業者の記録) |
| 15:18 頃 | 「仮想マシン接続」が応答なし → 拡張セッションを無効化して基本セッションで接続(LAB-14)。`.\Administrator` + DSRM パスワードでログオン |
| 15:19 | `wbadmin start systemstaterecovery -version:09/02/2026-05:16 -backupTarget:D: -quiet` を手入力で実行(基本セッションは貼り付け不可) |
| 15:19:58 | [Backup ログ 213/240] 回復開始 |
| 15:35:27 | [Backup ログ 241/242] 回復完了。15:37 に画面で完了を確認 |
| 15:37 | `bcdedit /deletevalue {current} safeboot` を実行したが PowerShell が `{current}` をスクリプトブロックと解釈して失敗(LAB-13)。気づかずに再起動 |
| 15:39 | **DSRM で再起動**してしまう。System ログに「NTDS が起動しないため Kdc/DNS/DFSR が起動できない」。ホストからの WinRM は `AccessDenied`(ドメイン認証不可)。プロンプトが `C:\Users\Administrator.AD-DC01`(ローカルプロファイル)で DSRM と判明 |
| 15:5x | `bcdedit /deletevalue '{current}' safeboot`(引用符あり)で解除、`bcdedit /enum '{current}'` に safeboot なしを確認して再起動 |
| 15:55:52 | 通常起動。`CORP\Administrator` でログオン可 |
| 15:57 | ホストから確認: `marker : 0`、OU 7個、FSMO 5役割、6サービス `Running`、`safeboot: 0`、`ldapsig: 2` |

## 復元後の確認(実出力)

```text
boot   : 09/02/2026 15:55:52
marker : 0  (0なら復元成功)
OUs    : Domain Controllers, _Tier0-Admins, Servers, Workstations, Groups, ServiceAccounts, Employees
fsmo   : 5 roles on ad-dc01
svc    : DNS=Running Kdc=Running Netlogon=Running NTDS=Running W32Time=Running windows_exporter=Running
safeboot: 0  (0なら解除済み)
ldapsig: 2

Microsoft-Windows-Backup:
2026/09/02 15:35:27  241   (回復完了)
2026/09/02 15:35:27  242
2026/09/02 15:19:58  213   (回復開始)
2026/09/02 15:19:58  240
2026/09/02 14:40:17   14   (バックアップ完了)
2026/09/02 14:40:17    4
```

`dcdiag /q` は `SystemLog` テストのみ失敗。内容は 15:39:15〜16 の「`rspndr` 起動失敗」「Kdc/DFSR/DNS/IsmServ は起動できなかった NTDS に依存」で、**DSRM で起動した際の正常な挙動**が System ログに残っているだけです。NTDS のデータベース(JET/ESE)エラーはありません。

## インシデントと欠陥(LAB-11〜15)

[作業結果報告](2026-09-02-work-result-SM-AD-001.md)6節の LAB-01〜10 に続く番号です。

| ID | 事象 | 最初の仮説 | 実際に見たもの | 原因 | 対応 / 文書修正 |
| --- | --- | --- | --- | --- | --- |
| LAB-11 | バックアップ中に WinRM 切断 → ping 不通 → VM が再起動していた | WinRM の出力上限 / VM のハング | ホストの `Hyper-V-Worker-Admin` ログ: 12636(差分 VHDX の回復性エラー)→ 18524(一時停止)→ 18528(強制停止)。差分ファイルは5世代、最上層が 8.5 GB に膨張 | 深い差分チェーンの最上層に、ゲスト内 VSS + 数 GB の書き込みが重なり、ホスト側ストレージ I/O が停止。Hyper-V が保護のため一時停止し、回復せず強制停止 | チェーンを1世代に統合、自動チェックポイント無効化、バックアップ直前にチェックポイントを取らない。[08](../build-package-ad/08-change-rollback-plan.md)・[05](../build-package-ad/05-build-procedure.md)に運用ルールを追記。初期の「容量不足」という説明は、空き 56 GB の事実と合わないため撤回 |
| LAB-12 | `LDAPServerIntegrity` が 1 に戻っていた(AST-04 で 2 に設定済みのはず)。`LdapEnforceChannelBinding` は 2 のまま | 強制停止でレジストリが巻き戻った | `Get-GPOReport 'Default Domain Controllers Policy'`: 「ドメイン コントローラー: LDAP サーバー署名必須 = なし(SettingNumber 1)」。`secedit` 実効値 `=4,1` | GPO がこの項目を明示的に定義しており、GP 更新のたびにレジストリ編集を上書き。CBT は GPO に定義が無いため残った(非対称の理由)。AST-04 の「PASS」は設定直後の一瞬だけ成立していた | GPMC で「署名必須」に変更 → `gpupdate` → `secedit` で `=4,2` → 再起動後に警告 2886 なし。[05](../build-package-ad/05-build-procedure.md) 7.1節を GPO 手順へ全面改訂、[06](../build-package-ad/06-test-specification.md) AST-04 の判定を「`gpupdate` 後の実効値」へ、[02](../build-package-ad/02-detailed-design.md)・[03](../build-package-ad/03-parameter-sheet.md)を更新 |
| LAB-13 | `bcdedit /deletevalue {current} safeboot` が「指定された削除コマンドは有効ではありません」 | 構文 | PowerShell では `{current}` がスクリプトブロックとして展開される | `'{current}'` と引用符で囲む必要がある(cmd では不要)。解除できないまま再起動し、DSRM で起動して約18分ロス | [05](../build-package-ad/05-build-procedure.md)・[08](../build-package-ad/08-change-rollback-plan.md)のコマンドを引用符付きへ。解除後に `bcdedit /enum` で確認する行を追加 |
| LAB-14 | DSRM 起動後、「仮想マシン接続」が応答なし | VM のハング | `Get-VM` は `Running`/`Heartbeat OK`。拡張セッション(RDP ベース)がセーフモードのゲストでは成立しない | ビューア側の問題。`Set-VMHost -EnableEnhancedSessionMode $false` で基本セッションにすると表示される。基本セッションは貼り付け不可 | [05](../build-package-ad/05-build-procedure.md) 14節に注記 |
| LAB-15 | ホストPCから `Invoke-Command` で流した `wbadmin` が 56% で `PSSessionStateBroken` | (LAB-11 と同時に発生したため当初は VM 側と混同) | 大量の進捗行が WinRM セッションを流れ続けていた | 長時間・大量出力のコマンドを WinRM 越しに同期実行すると切断されうる(この回は LAB-11 の VM 停止が直接の原因だが、切断されても `wbadmin` 自体はサービス側で継続する点も含めて注意) | 2回目はコンソールで `> C:\temp\wsb.log 2>&1` にリダイレクトして実行。[05](../build-package-ad/05-build-procedure.md)・[09](../build-package-ad/09-network-validation-procedure.md)の方針(コンソールで実行 or 出力をファイルへ)に沿う |

## 学び(初心者向けの言い換え)

- **「設定した」と「設定が維持されている」は別**。GPO 管理下の項目をレジストリで直接触ると、数分後に静かに戻る。翌日に再確認して初めて分かった
- **チェックポイントは安全網だが、取れば取るほど足元が不安定になる**。深い差分チェーンの上で重い書き込みをすると、ホスト側の I/O が先に音を上げる
- **切り分けはゲストとホストの両側から**。ゲストのログは「予期しないシャットダウン」としか言わないが、ホストのログには「誰が・なぜ止めたか」が残っていた
- **DSRM から戻り忘れると、症状は「認証拒否」として現れる**。`AccessDenied` を見てパスワードを疑う前に、プロンプトのプロファイル名(`Administrator.<ホスト名>`)と `bcdedit /enum` を見る
- **PowerShell と cmd で同じコマンドでも通らないことがある**(`{current}`)。ネットの手順例をそのまま貼る前に、どちらのシェル向けかを確認する

## 後片付け

- 目印 OU: 復元で消えたため削除操作は不要
- `C:\temp\wsb-0902.log`、`ddcp.xml`、`sec.inf`、`sec2.inf`: 残置(秘密値は含まない。次回作業時に削除)
- ホストの拡張セッションモード: 無効のまま(必要なら `Set-VMHost -EnableEnhancedSessionMode $true`)
- チェックポイント: 演習直後は `phase1-complete`(2026-09-02 11:19)のみ。その後、組み込み管理者の改名と定期バックアップ登録まで済ませた 16:39 に `phase1-hardened` を取得し、`phase1-complete` を `Remove-VMSnapshot` で統合して**1世代を維持**した(`.vhdx` 2 + `.avhdx` 2 の計4ファイル、C: 空き 60.9 → 63 GB)。復元点は常に最新の1つだけを持ち、更新は「新しく取る → 古いものを統合」の順で行う
