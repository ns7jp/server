# dc02の時刻同期元の是正 — 2026-09-07

[DC 1台停止時の可用性試験](2026-09-03-ad-dc-outage-drill.md)で「本来PDCエミュレーター以外のDCはドメイン階層に従ってPDCから時刻を取るべきところ、`ad-dc02`はHyper-Vホスト時刻(`VMTP`)を参照している」と記録した逸脱を是正した記録です。

> **前提が変わっていたことの確認から開始しました**: 上記の指摘は2026-09-03時点、`ad-dc02`がPDCエミュレーターを保持していなかった頃のものです。[2026-09-04のFSMO奪取](2026-09-04-ad-fsmo-seize.md)で`ad-dc02`は5役割すべて(PDCエミュレーターを含む)を保持する単一DCになっており、「上位DCの階層を辿るべき」という前提そのものが成り立たなくなっていました。修正に着手する前にこの前提の変化を確認し、当時の指摘をそのまま鵜呑みにしないようにしています。

## 結果の要約

| 項目 | 結果 |
| --- | --- |
| 判定 | **PASS** |
| 診断 | `Type: NT5DS`(存在しない上位DCを探し続ける、行き場のない構成)が、FSMO奪取後も残っていた |
| 是正 | `Type`を`NTP`へ、`AnnounceFlags`を`5`(Always + Reliable)へ変更 |
| 実効時刻源 | 変更前後とも`VM IC Time Synchronization Provider`(Hyper-Vホスト時刻)で同じ。**「意図せず動いていた」状態から「明示的に構成された」状態への変更** |
| 副作用 | `Restart-Service w32time`直後5秒での確認では`Local CMOS Clock`に見えたが、60秒待つと正しい状態に復帰(一過性) |

> **2026-09-28 訂正**：上表の「明示的に構成された」は不正確です。変更したのは`Type`と`AnnounceFlags`だけで、`NtpServer`は未設定のままです(本文「一過性の退行」の節でも認めています)。時刻源としてHyper-Vホスト時刻(`VMICTimeProvider`)を使うことは、今回の設定で明示したものではなく、変更前から有効だった既定の動作が続いているだけです。判定(PASS)と実出力は当時の記録のまま残します。正しい理解は本文「根本原因」「現在の状態」の訂正を参照してください。

## 診断

**dc02のコンソール**で、GPOがWindows Time Serviceを管理していないことを先に確認しました([LAB-12](2026-09-02-ad-restore-drill.md)と同じ轍を踏まないため)。

```text
gpresult /r | Select-String -Pattern "Windows Time|W32Time" -Context 0,2 → 該当なし
```

続けて現在の構成を確認しました。

```text
[NtpClient (ローカル)]
Type: NT5DS
NtpServer: (未定義または未使用)

[VMICTimeProvider (ローカル)]
Enabled: 1
InputProvider: 1
```

`Type: NT5DS`は「自分より上位のDC(PDCエミュレーター)を辿って時刻を取得する」モードです。しかし今の`ad-dc02`自身がPDCエミュレーターであり、辿る上位DCが存在しません。行き場を失ったNT5DSは実質何もできず、Hyper-Vの統合サービスである`VMICTimeProvider`(常時有効な別系統のプロバイダー)が黙って肩代わりしていた、というのが`w32tm /query /status`で見えていた`VMTP`の正体でした。

### 根本原因

Windowsは本来、あるDCがPDCエミュレーター役割を持つと、Netlogonサービスがそれを検知して`Type`を自動的に`NTP`(階層追従をやめ、権威ある時刻源として振る舞う)に切り替える仕組みを持っています。しかし今回は`Move-ADDirectoryServerOperationMasterRole -Force`による**奪取(seize)**で役割が移っており、この自動切り替えが働かないまま`NT5DS`が残っていたと考えられます。

> **2026-09-28 訂正**：上の段落の根本原因の説明は誤りでした。PDCエミュレーター役割が移ったときに、Netlogonが検知して`Type`を自動で`NTP`へ切り替える仕組みは、Windowsにはありません。移譲(transfer)でも奪取(seize)でも同じで、**PDCエミュレーターの時刻設定は手作業で付け替えるのが仕様**です。定石は、新しいPDCエミュレーターで`w32tm /config /manualpeerlist:"<外部NTP>" /syncfromflags:manual /reliable:yes /update`を実行し、旧PDC(残っていれば)を`w32tm /config /syncfromflags:domhier /update`に戻すことです。したがって「奪取だったから自動切り替えが働かなかった」のではなく、「役割を移した後に時刻設定を付け替える手順が、奪取の手順に入っていなかった」が正しい原因です。付け替えの手順は[変更・ロールバック計画](../build-package-ad/08-change-rollback-plan.md)10節に加えました(実機では未検証)。

**FSMO奪取(seize)は役割の付け替えだけで、Windows Time Serviceの構成までは自動的に追従しない。** 09-03に記録した「VMTPは逸脱」という当時の判断は、`ad-dc02`がまだPDCでなかった時点では正しい指摘でしたが、その後の奪取によって前提が変わり、単なるフォールバックの副作用として構成不備が残っていた、というのが実態です。

## 是正

```powershell
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' -Name Type -Value 'NTP'
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config' -Name AnnounceFlags -Value 5
Restart-Service w32time
```

## 一過性の退行と、その切り分け

`Restart-Service`から5秒後に確認したところ、`w32tm /query /source`が`Local CMOS Clock`(VM内蔵ハードウェアクロック、補正なし)を返しました。修正前の`VM IC Time Synchronization Provider`より悪化しているように見え、一度は退行と判断しかけました。

断定せず、原因を2つに絞って切り分けました。

1. `Type: NTP`にしたが`NtpServer`が未設定のため、NtpClientプロバイダーが有効なサンプルを出せない
2. `Restart-Service`直後、`VMICTimeProvider`が再登録・再同期を完了する前に確認してしまった一過性の状態

```powershell
Start-Sleep 60
w32tm /query /source
```

60秒後、`VM IC Time Synchronization Provider`に復帰していることを確認しました。イベントログ(`Get-WinEvent -LogName System`、`Time-Service`/`VMIC`関連)にもエラーはありませんでした。**(2)が正しく、一過性の状態だった**と確定しました。

## 学び

- **FSMO奪取(seize)は役割の付け替えのみで、依存する周辺サービス(Windows Time Serviceの構成など)まで自動的に追従するとは限らない**。奪取後は役割に紐づく他の構成も個別に点検する必要がある
- **過去に記録した指摘は、前提が変わっていないか確認してから適用する**。「PDCエミュレーターへ辿るべき」という09-03の指摘は、09-04のFSMO奪取で前提そのものが崩れていた。古い記録を鵜呑みにせず、現状から診断し直すことで無駄な(あるいは的外れな)修正を避けられた
- **サービス再起動直後の確認は、退行に見えることがある**。`VMICTimeProvider`の再登録には数秒以上かかり、5秒後の確認では一時的に`Local CMOS Clock`にフォールバックして見えた。60秒待って再確認したことで、誤って「退行した」と記録することを避けられた。このラボで繰り返し出てきた「収束前に判断しない」というパターンが、今回は診断作業そのものにも当てはまった
- **修正の目的は「時刻源を変えること」ではなく「意図を明示すること」だった**。実際に使われている時刻源(Hyper-Vホスト時刻)は修正前後で変わっていない。変わったのは、それが暗黙のフォールバックか、明示的な構成かという点

## 現在の状態

- `ad-dc02`のWindows Time Service構成は`Type: NTP` / `AnnounceFlags: 5`で、PDCエミュレーターとして明示的に構成されている
- 実効時刻源は`VM IC Time Synchronization Provider`(Hyper-Vホスト時刻)。外部NTPに到達できない閉域環境のPDCエミュレーターとして妥当な構成

> **2026-09-28 訂正**：「閉域環境のPDCエミュレーターとして妥当な構成」は言い過ぎでした。理由は3つあります。(1) [詳細設計書](../build-package-ad/02-detailed-design.md)のW32Timeの設計は`manualpeerlist`による外部NTP同期で、今回の構成はその設計から外れていますが、逸脱として記録していませんでした。(2) 同じ9/7に、WSUS構築のため`ad-dc02`へdefault route(`0.0.0.0/0 → 192.0.2.40`)を一時的に追加しており([WSUS構築証跡](2026-09-07-wsus-build-validation.md))、完全な閉域という前提は当日の状態と食い違います。(3) 今の構成では、フォレスト全体の時刻の基準がホストPCの時計のままで、`NtpServer`も空です。仮想化したPDCエミュレーターでは、`HKLM\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\VMICTimeProvider`の`Enabled`を`0`にしてホスト時刻への依存を切り、`manualpeerlist`で外部NTP(閉域なら組織内のNTPサーバー)と同期させるのが一般的な設計です。ラボのホストPC自体がインターネットの時刻と同期しているなら実害は小さいものの、これは設計どおりの構成ではなく、**ホスト時刻に頼る暫定状態**と位置づけるのが正確です。`VMICTimeProvider`を止めるかどうかの判断と、その理由の記録はまだ行っていません。
- これにより[基本設計書](../build-package-ad/01-basic-design.md)3.4節・[FSMO奪取の証跡](2026-09-04-ad-fsmo-seize.md)で「未是正」としていた項目を解消した
