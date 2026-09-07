# windows_exporterの最小権限化(gMSA) — 2026-09-07

[03 パラメータシート](../build-package-ad/03-parameter-sheet.md)・[02 詳細設計書](../build-package-ad/02-detailed-design.md)・
[07 引き渡しチェックリスト](../build-package-ad/07-handover-checklist.md)で「AST-07相当の継続課題」として
記録していた、windows_exporterサービスの実行アカウント(既定`LocalSystem`)の最小権限化を実施した記録です。

対象は現時点で唯一のDCである`ad-dc02`です(`ad-dc01`は[2026-09-04のFSMO奪取](2026-09-04-ad-fsmo-seize.md)で削除済み)。

## 結果の要約

| 項目 | 結果 |
| --- | --- |
| 判定 | **PASS** |
| 採用した方式 | gMSA(グループ管理サービスアカウント)`CORP\svc-winexp$` |
| 付与した権限 | `BUILTIN\Performance Monitor Users`グループへのメンバー追加のみ(`Domain Admins`等の特権グループには一切追加していない) |
| 検証 | `StartName: CORP\svc-winexp$`、`State: Running`、`/metrics`が`windows_ad_*`系メトリクスを引き続き返すことを確認 |

## 背景: なぜgMSAか

ドメインコントローラーには**ローカルSAM(ローカルユーザー・ローカルグループの台帳)が存在しません**。
そのため、通常のWindows Serverで行うような「サービス専用のローカルアカウントを作る」パターンは
DC上では成立せず、サービスアカウントは常にドメインアカウントになります。

人間が管理するドメインアカウント(固定パスワード)を作る方法もありますが、パスワードの
定期変更・失念・漏えいのリスクが残ります。gMSA(Group Managed Service Account)は
パスワードをAD自身が自動的にローテーションし、人手による管理が不要な、DC上でも使える
最小権限アカウントの第一選択です。

## 手順

### 1. KDS root keyの準備

gMSAのパスワード自動ローテーションは、KDS(Key Distribution Services) root keyに依存します。

```powershell
Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))
```

> **ラボ限定のテクニック**: `-EffectiveTime`を過去時刻にして即座に有効化しています。
> 本番環境では、KDS root keyがフォレスト内の全DCへ複製されるまで**約10時間**待つのが
> 正しい手順です。この即時反映は検証用の短縮であり、本番では使いません。

`Add-KdsRootKey`はGuidを返して成功しましたが、直後の`Get-KdsRootKey`は空を返しました。
10秒待って再確認すると`IsFormatValid: True`で正しく読めました。作成直後の読み取りタイミングの
癖であり、失敗ではありません。

```powershell
Start-Sleep 10
Get-KdsRootKey | Format-List *
```

### 2. gMSAの作成

```powershell
New-ADServiceAccount -Name svc-winexp -DNSHostName svc-winexp.corp.example.test `
  -PrincipalsAllowedToRetrieveManagedPassword "AD-DC02$"
Install-ADServiceAccount -Identity svc-winexp
Test-ADServiceAccount -Identity svc-winexp
```

`Test-ADServiceAccount`が`True`を返し、`ad-dc02`自身がこのgMSAのパスワードを取得できることを
確認しました。`PrincipalsAllowedToRetrieveManagedPassword`にはコンピューターアカウント
(`AD-DC02$`)そのものを指定しています。

### 3. `Performance Monitor Users`への追加

windows_exporterがWMI経由でパフォーマンスカウンターを読み取れるよう、組み込みグループ
`Performance Monitor Users`へgMSAを追加します。

**ここでつまずきました**。`Add-LocalGroupMember -Group "Performance Monitor Users" -Member "CORP\svc-winexp$"`が
`GroupNotFound`で失敗し、`Get-LocalGroup`の一覧にも`Performance Monitor Users`が出てきません。

原因は前項と同じで、**DCにはローカルSAMが無いため、`LocalAccounts`モジュール
(`Get-LocalGroup`/`Add-LocalGroupMember`)はBUILTINグループを一切扱えません**。
このモジュールがDC上で返すのは、`Cert Publishers`のようなドメインローカルグループだけです。

回避策として、well-knownなSIDから直接名前解決し、レガシーな`net localgroup`コマンドで
追加しました。

```powershell
(New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-558")).Translate([System.Security.Principal.NTAccount]).Value
# => BUILTIN\Performance Monitor Users (このOSではロケール化されていなかった)

net localgroup "Performance Monitor Users" "CORP\svc-winexp$" /add
net localgroup "Performance Monitor Users"
# => メンバーにCORP\svc-winexp$が表示されることを確認
```

`net localgroup`はレガシーコマンドですが、`LocalAccounts`モジュールと異なりBUILTINグループを
正しく操作できました。

### 4. サービスの実行アカウント切り替え

```powershell
sc.exe --% config windows_exporter obj= "CORP\svc-winexp$" password= ""
```

**ここで2段階でつまずきました**。

1回目: `sc.exe config windows_exporter obj= "CORP\svc-winexp$" password=""`(等号の直後に
スペースなし)が、変更を適用せず`sc.exe`自身の使用方法(ヘルプ)を表示して終了しました。
`sc.exe`のヘルプ本文に「等号と値の間にはスペースが必要です」と明記されていたため、
最初はスペース不足が原因と判断しました。

2回目: スペースを入れた`password= ""`で再実行しても、**まったく同じ使用方法ダンプが
再現**しました。1回目の診断だけでは説明がつきません。

真因は、**PowerShellがネイティブ実行ファイル(`sc.exe`)を呼び出す際、空文字列(`""`)の
引数を丸ごと消してしまう**という既知の挙動でした。`password= ""`と書いても、実際に
`sc.exe`へ渡る引数リストからは`""`が消え、`password=`という値のないトークンだけが渡り、
再び使用方法ダンプを引き起こしていました。スペースの有無は必要条件でしたが、
十分条件ではなかったということです。

回避策は、PowerShellの`--%`(stop-parsing演算子)を使い、それ以降のコマンドライン文字列を
PowerShellに一切解釈させず、生のまま外部コマンドへ渡すことです。

```powershell
sc.exe --% config windows_exporter obj= "CORP\svc-winexp$" password= ""
# => [SC] ChangeServiceConfig SUCCESS
```

`--%`以降は変数展開・引用符解釈が完全に無効になるため、`""`もそのまま2文字の引用符として
`sc.exe`に渡ります。gMSAの場合、`sc.exe`はこの空パスワードを見て「gMSAなのでパスワード管理は
LSAに任せる」という扱いをします。

### 5. 検証

```powershell
Restart-Service windows_exporter
Start-Sleep 10
Get-CimInstance Win32_Service -Filter "Name='windows_exporter'" | Select-Object Name, State, StartName
```

```text
Name              State   StartName
----              -----   ---------
windows_exporter  Running CORP\svc-winexp$
```

```powershell
(Invoke-WebRequest -Uri http://localhost:9182/metrics -UseBasicParsing).Content -split "`n" |
  Select-String "^windows_ad_|^windows_dns_" | Select-Object -First 10
```

`windows_ad_address_book_client_sessions`、`windows_ad_approximate_highest_distinguished_name_tag`
等、AD系メトリクスが従来どおり取得できることを確認しました。実行アカウントを`LocalSystem`から
最小権限のgMSAへ切り替えても、windows_exporterの`ad`/`dns` collectorの動作に影響はありません。

## 学び

- **DCにはローカルSAMが存在しない**ため、サービスアカウントは常にドメインアカウントになる。
  人手管理のパスワードを避けたい場合、gMSAが最小権限化の第一選択になる
- **`LocalAccounts`モジュール(`Get-LocalGroup`/`Add-LocalGroupMember`)は、DC上ではBUILTINグループを
  扱えない**。ドメインローカルグループしか見えていないことに気づかず、GroupNotFoundを
  「グループ名の綴り間違い」と誤診しやすい。well-knownなSIDからの名前解決 + レガシーな
  `net localgroup`が実務的な回避策になる
- **PowerShellはネイティブ実行ファイル呼び出し時に空文字列(`""`)の引数を消す**。
  `sc.exe`の`password=""`のように「意図的な空値」を渡したい場面では、`--%`
  (stop-parsing演算子)でコマンドライン全体をPowerShellの解釈から外す必要がある
- **1つのエラーメッセージの裏に、異なる2つの原因が重なっていることがある**。
  `sc.exe`の使用方法ダンプは、1回目はスペース不足、2回目は空文字列引数の消失という
  別の原因で再現した。1回目の仮説で直ったように見えても、同じ症状が再現したら
  仮説そのものを疑い直す必要がある

## 現在の状態

`ad-dc02`のwindows_exporterサービスは、gMSA `CORP\svc-winexp$`(`Performance Monitor Users`
グループのメンバーのみ、特権グループには非所属)で稼働しています。
[パラメータシート](../build-package-ad/03-parameter-sheet.md)・[詳細設計書](../build-package-ad/02-detailed-design.md)・
[引き渡しチェックリスト](../build-package-ad/07-handover-checklist.md)に「継続課題」として記録していた
最小権限化はこれで解消しました。
