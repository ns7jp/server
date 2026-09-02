# AD構築・試験結果票 — 2026-09-01〜02

[試験仕様書・結果票](../build-package-ad/06-test-specification.md)の原本をコピーし、手元のHyper-V上に構築した`ad-dc01`(Windows Server 2022 Standard 評価版)で実施した結果を記入したものです。ANW-01〜09は[別票](2026-09-01-network-host-validation-ad.md)にあります。

> **この証跡が示す範囲**: ホストPC(Windows 11、Hyper-V)上の内部スイッチに接続したVM 1台で、[構築手順書](../build-package-ad/05-build-procedure.md)のフェーズ1を1手順ずつ実行した記録です。実行者はAI支援セッションで手順を受け取り、結果をスクリーンショットで確認しました。組織DNS、実ドメインメンバー、中央Prometheus、永続host、24h/72h稼働は含みません。

## 基本情報

| 項目 | 値 |
| --- | --- |
| 全体状態 | フェーズ1 必須31 ID すべて`PASS`(内訳: AUT 4、AIT 10、AST 8、ANW 9)。AIT-09(フェーズ2)は`BLOCKED` |
| 実施日時（JST） | 2026-09-01 午後 〜 2026-09-02 午前 |
| 実施者 | ns7jp |
| 対象環境 / host | `ad-dc01.corp.example.test`(`192.0.2.50/24`)、Hyper-V Gen2 VM、vCPU/メモリはラボ既定、C: 30GB + D: 20GB(Backup) |
| 管理端末 | ホストPC(`192.0.2.40/24`)、WinRM HTTPS(5986)で`Invoke-Command`。フォレスト作成など初回操作はVMコンソール |
| commit SHA | 実施時の手順書は`6c2d1cecf21e57e296d5790e77c6ebb5d820f628`(初版)。発見した誤りは[PR #128](https://github.com/ns7jp/server/pull/128)と本票のPRで修正 |
| OS build / 機能レベル | `20348` / `Windows2016Forest` / `Windows2016Domain` |
| PowerShell | 対象host `5.1.20348.558`(組込)。7.4系は未導入 |

DSRMパスワード、Administratorパスワード、証明書秘密鍵は記載していません。IPは文書の例示値(TEST-NET-1)をそのまま使用しています。

## 単体試験（AUT）

| ID | 確認対象 | 結果 | 実出力（要点）/ 備考 |
| --- | --- | --- | --- |
| AUT-01 | PowerShellスクリプト構文チェック | PASS(修正後) | ホストPCのWindows PowerShell 5.1で、`05-build-procedure.md`の```powershell ブロック43個を`[System.Management.Automation.Language.Parser]::ParseInput`でパース。初回は#41(System State復元)で2エラー(`-version:<復元対象の…>`の`<>`が文字列外)。プレースホルダーを変数の文字列リテラルへ変更し、`blocks=43 blocks_with_errors=0`を確認 |
| AUT-02 | DSRMパスワード強度の設計確認 | PASS | `03-parameter-sheet.md`: 秘密値台帳で管理、NFR-07相当以上の強度。`05`: `Read-Host -AsSecureString`で入力し文書・ログに残さない。値そのものは確認していない |
| AUT-03 | 文書間整合性レビュー | PASS | 00〜04で`corp.example.test`、`CORP`、`ad-dc01`、`192.0.2.50`/`.40`、最小長14、`WinThreshold`の記載を突合。`example.com`/`192.168.`等の混入なし。OU構造は初版に`OU=Users`の誤りがあり、PR #128で02/03/05/08を揃えた |
| AUT-04 | 成果物リンク | PASS | `pytest tests/test_portfolio_artifacts.py -k internal_markdown_links` → `1 passed, 52 deselected` |

## 結合試験（AIT）

| ID | 確認対象 | 結果 | 実出力（要点）/ 備考 |
| --- | --- | --- | --- |
| AIT-01 | 新規フォレスト作成・初回DC昇格 | PASS | VMコンソールで`Install-ADDSForest -DomainName corp.example.test -DomainNetbiosName CORP -ForestMode WinThreshold -DomainMode WinThreshold -InstallDns`。直前にHyper-Vチェックポイントを取得。自動再起動後に`CORP\Administrator`でログオン |
| AIT-02 | 昇格後必須サービス確認 | PASS | `Get-Service NTDS, DNS, Netlogon, Kdc, W32Time` すべて`Running`。DNSクライアントは`127.0.0.1`優先 |
| AIT-03 | AD統合DNSでの名前解決 | PASS | `_ldap._tcp.dc._msdcs` / `_kerberos._tcp.dc._msdcs` のSRVが`ad-dc01.corp.example.test`(389/88)を返す。Aレコード`192.0.2.50` |
| AIT-04 | OU/パスワードポリシー | PASS | OU 6個(`_Tier0-Admins`, `Servers`, `Workstations`, `Employees`, `Groups`, `ServiceAccounts`)+既定`Domain Controllers`。`New-ADOrganizationalUnit -Name "Users"`は`CN=Users`と衝突して失敗(設計誤り、PR #128で修正)。`Set-ADDefaultDomainPasswordPolicy`後、弱いパスワード`abc12345`で`New-ADUser`が`ADPasswordComplexityException`、強いパスワードは成功→削除 |
| AIT-05 | FSMO確認 | PASS | `netdom query fsmo`: スキーマ/ドメイン名前付け/PDC/RID/インフラストラクチャ すべて`ad-dc01.corp.example.test` |
| AIT-06 | System Stateバックアップ | PASS | 初回の`wbadmin start systemstatebackup`は成功表示だが`wbadmin get versions`が空。GUIで「Windows Server バックアップがインストールされていません」を確認し、`Install-WindowsFeature Windows-Server-Backup`(先行コマンドで未反映だった)後に再実行。20GBのVHDXを追加してD:(NTFS `Backup`)へ取得、`wbadmin get versions`にSystem State復元可能と記録 |
| AIT-07 | ADごみ箱によるオブジェクト復元 | PASS | `Enable-ADOptionalFeature 'Recycle Bin Feature'`。1回目は`Name`で削除済みオブジェクトを検索して失敗(削除時に`Name`が`<name>\nDEL:<GUID>`へ変わるため)。`-PassThru`で`ObjectGUID`を控え、GUIDで`Get-ADObject -IncludeDeletedObjects`→`Restore-ADObject`。属性が復元されたことを`Get-ADUser`で確認後に削除 |
| AIT-08 | サービス停止復旧演習 | PASS | DNSサービスを`Stop-Service`→`Start-Service`。**RTO 0.906秒**(`Get-Date`差分)。前後の`Get-Service`で`Running`復帰を確認 |
| AIT-09 | host/ADメトリクスscrape(フェーズ2) | BLOCKED | 中央Prometheus hostが本ラボに存在せず、`compose.yaml`の`monitoring` network `internal: true`制約も未解消。windows_exporter自体はローカルで`windows_ad_*`メトリクスを返すことを確認(ANW-05/06) |
| AIT-10 | 実ホストnetwork | PASS | ANW-01〜09 9/9 PASS。[別票](2026-09-01-network-host-validation-ad.md) |
| AIT-11 | 再実行安全性 | PASS | 昇格済みの`ad-dc01`で`Install-ADDSForest`を再実行→`TestFailedException`(前提条件の検証に失敗)で停止。`Get-ADForest`/`Get-ADDomain`/`netdom query fsmo`/`Get-Service`で既存環境が無傷であることを確認 |

## セキュリティ試験（AST）

| ID | 確認対象 | 結果 | 実出力（要点）/ 備考 |
| --- | --- | --- | --- |
| AST-01 | WinRM listener確認 | PASS | `WSMan:\localhost\Listener`: `Transport=HTTPS, Address=*` の1件のみ(HTTPなし)。`Basic: false`、`Kerberos: true`、`Negotiate: true`、`AllowUnencrypted: false` |
| AST-02 | RDP状態確認 | PASS | `リモート デスクトップ`グループ3ルール(シャドウ/ユーザーモードTCP/UDP)すべて`Enabled: False`。3389非待受(ANW-05) |
| AST-03 | パスワードポリシー確認 | PASS | `Get-ADDefaultDomainPasswordPolicy`: MinPasswordLength 14、ComplexityEnabled True、MaxPasswordAge 90日、PasswordHistoryCount 24、LockoutThreshold 10、LockoutDuration/ObservationWindow 10分 |
| AST-04 | LDAP署名/チャネルバインディング | PASS | `HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters`の`LDAPServerIntegrity=2`、`LdapEnforceChannelBinding=2`。`Restart-Service NTDS -Force`が依存サービス(DNS)の起動待ちで数分応答しなかったが、`Ctrl+C`後の`Get-Service`で全サービス`Running`(cmdletの状態ポーリングの問題で、サービス自体は正常) |
| AST-05 | SMBv1無効確認 | PASS | `Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol` → `State: Disabled` |
| AST-06 | 監査ポリシー確認 | PASS | `auditpol /get /subcategory:"ディレクトリ サービスの変更"` → `成功および失敗` |
| AST-07 | 特権グループメンバー最小化 | PASS | `Get-ADGroupMember "Domain Admins"` → `Administrator`のみ |
| AST-08 | Firewall許可範囲確認 | PASS | AD DS関連5グループ(`Active Directory Domain Services`, `DNS サービス`, `Kerberos キー配布センター`, `DFS レプリケーション`, `ファイル レプリケーション`)=`192.0.2.0/24`、`WinRM-HTTPS-MgmtOnly`=`192.0.2.40`。英語グループ名では`ObjectNotFound`(ロケール依存、PR #128で修正)。詳細はANW-08 |

## 実施中に見つかった手順書・設計書の欠陥

すべて実機で再現し、原因を実出力で確定してから文書側を修正しました。実機の構成変更で回避したものはありません。

| # | 欠陥 | 発見ID | 修正PR |
| --- | --- | --- | --- |
| 1 | `OU=Users`が既定`CN=Users`と衝突して作成不可 | AIT-04 | [#128](https://github.com/ns7jp/server/pull/128) |
| 2 | Firewallルールグループ名が英語固定で日本語版OSでは`ObjectNotFound` | AST-08 | #128 |
| 3 | `pktmon start --etw -p 128`が無効な構文 | ANW-07 | #128 |
| 4 | `Get-NetFirewallProfile`が`NotConfigured`を返し期待値`Block`と不一致 | ANW-08 | #128 |
| 5 | 「AD CS未導入ならLDAPS非待受」の前提が誤り(WinRM証明書をNTDSが流用) | ANW-05 | #128 |
| 6 | System State復元コマンドの`<プレースホルダー>`が文字列外にあり構文エラー | AUT-01 | 本票のPR |

手順書の記述以外で学んだ運用上の注意(文書には注記として反映済み、または本票のみ):

- Hyper-VのVMMSはSYSTEMアカウントで動くため、UNCパス上のISOやVHDXを扱えない(認証エラー)。ISOとVM格納先はローカルディスクに置く
- 閉域のDCはインターネットへ出られないため、windows_exporterのMSIは管理端末でダウンロード・SHA256検証し、`Copy-Item -ToSession`で転送してVM側でも再検証した
- `Get-Credential`のGUIダイアログが表示されない環境では`Read-Host -AsSecureString`+`PSCredential`で代替できる。パスワード誤入力はSecurityログのイベント4625・サブステータス`0xC000006A`で切り分けられる
- `Test-WSMan`には`-SkipCACheck`等のパラメータが無い。自己署名証明書では`New-PSSessionOption`を`Invoke-Command`/`Enter-PSSession`に渡す

## 終了判定

- 必須: AUT-01〜04、AIT-01〜08/10/11、AST-01〜08、ANW-01〜09 → **31/31 PASS**
- フェーズ2(AIT-09)は`BLOCKED`のまま。解除条件は[要件定義書](../build-package-ad/00-requirements.md)のとおりで、本ラボでは満たせない
- 引き渡し判定([07-handover-checklist](../build-package-ad/07-handover-checklist.md))は、永続host・24h/72h確認・組織環境の項目が`NOT RUN`のため、ラボ検証完了にとどまる
