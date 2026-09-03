# 作業結果・引き渡し報告書 — SM-AD-001 ラボ構築（2026-09-01〜02）

[原本](../build-package-ad/11-work-result-report.md)を複製し、手元のHyper-V上に構築した`ad-dc01`のフェーズ1作業結果を記入したものです。原本は上書きしていません。

> **この報告書が示す範囲**: ホストPC(Windows 11、Hyper-V)上の内部スイッチに接続したVM 1台に対する、フェーズ1(ホスト単体構築)の作業実績です。引き渡し先は本人(ポートフォリオ用途)であり、組織の本番環境への引き渡しではありません。永続host、24h/72h稼働、組織DNS、実ドメインメンバー、中央Prometheusからのscrapeは含みません。

## 1. 文書・作業管理

| 項目 | 値 |
| --- | --- |
| 案件ID | `SM-AD-001` |
| 変更ID / チケット | `SM-AD-001-LAB01`(チケットシステムなし。本報告書とPR #128 / #129 / 本PRで代替) |
| 作業目的 | ADパック([docs/build-package-ad/](../build-package-ad/README.md))のフェーズ1手順を実機で通しで実行し、手順書の妥当性を確認して証跡を残す |
| 対象環境 / ホスト | Hyper-V Gen2 VM `ad-dc01`(`ad-dc01.corp.example.test`、`192.0.2.50/24`、内部スイッチ`ADLab-Internal`) |
| 対象フェーズ(フェーズ1のみ / フェーズ1+2) | フェーズ1のみ |
| ドメインFQDN | `corp.example.test`(設計値どおり) |
| NetBIOS名 | `CORP`(設計値どおり) |
| DSRM(ディレクトリサービス復元モード)パスワードの受け渡し状況 | 作業者本人が`Install-ADDSForest`実行時に`Read-Host -AsSecureString`で対話入力。Git管理外のローカルの秘密値メモに保管。第三者への受け渡しなし。値はどの文書・証跡にも記載していない |
| 作業者 / 確認者 | ns7jp(作業・確認とも本人。AI支援セッションで手順を1つずつ受け取り、結果をスクリーンショットで確認) |
| 作業予定日時 | 2026-09-01(午後〜) |
| 作業実績日時 | 2026-09-01 11:39(OSインストール完了) 〜 2026-09-02 11:19(フェーズ1完了チェックポイント取得) |
| 対象ホストのビルド番号(`Get-ComputerInfo` の `OsBuildNumber`) | `20348`(Windows Server 2022 Standard 評価版、Desktop Experience) |
| 変更前の状態識別子(スナップショット名) | `before-forest-creation`(2026-09-01 13:57、Hyper-Vチェックポイント) |
| 変更後の状態識別子(スナップショット名) | `phase1-hardened`(2026-09-02 16:39。Phase 1 完了 + GPO によるLDAP署名必須化 + 復元演習 + 管理者改名 + 定期バックアップ登録まで含む)。取得時点で `phase1-complete`(11:19)を統合し、チェックポイントは1世代のみ |
| windows_exporter バージョン / SHA256 | `0.31.8` / `0aadce6afb20182b678bfca9e8f2e8464ef48c469b28b4cf02e99d82158f5d40`(amd64.msi) |
| 中央inventory適用commit SHA(フェーズ2有効化時) | `NOT SET`(フェーズ2は`BLOCKED`のため未適用) |
| 作業結果 | フェーズ1 `PASS`(必須31 ID すべてPASS)。フェーズ2 `BLOCKED` |
| 関連 Issue / PR | [#113](https://github.com/ns7jp/server/pull/113)(パック初版)、[#128](https://github.com/ns7jp/server/pull/128)(ANW証跡+手順書修正5件)、[#129](https://github.com/ns7jp/server/pull/129)(AUT/AIT/AST証跡+修正1件) |

## 2. 作業前判定

| 確認項目 | 判定 | 証跡 / 備考 |
| --- | --- | --- |
| 対象、影響範囲、停止時間が合意済み | PASS | 本人のラボVM。影響範囲はVM 1台と、ホストPCの内部スイッチ用仮想アダプタのみ |
| 管理端末からWinRM(HTTPS)が利用可能 | PASS | 昇格前(ワークグループ)・昇格後(ドメイン)の両方で`Enter-PSSession`/`Invoke-Command`成功。自己署名証明書のため`-SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck)`が必要 |
| 初回フォレスト作成用のコンソール直接ログオン手段を確認 | PASS | Hyper-V仮想マシン接続(コンソール)を使用 |
| RDP一時許可またはコンソール等の代替接続手段を確認 | PASS | Hyper-Vコンソールを代替手段とし、RDPは一度も有効化していない |
| DSRMパスワードが秘密値台帳で生成・保管され、NFR-07相当の強度を満たしている | PASS | AUT-02。値は未確認(設計上の強度基準と手順の記載を確認) |
| 変更前後の状態識別子を固定 | PASS | `before-forest-creation` → `phase1-complete` |
| VM/ハイパーバイザーのスナップショット取得可否を確認 | PASS | 4世代のチェックポイントを取得(下記) |
| Go / No-Go 条件を確認 | PASS | [変更・ロールバック計画](../build-package-ad/08-change-rollback-plan.md)。ロールバック手段はチェックポイント復元 |

チェックポイントの系譜: `自動チェックポイント(09/01 11:39)` → `before-forest-creation(13:57)` → `before-ait11-reexecution-test(17:06)` → `phase1-complete(09/02 11:19)`。

## 3. 計画対実績

| 工程 | 予定操作 | 実績開始–終了 / 所要時間 | 結果 | 証跡 | 差異・備考 |
| --- | --- | --- | --- | --- | --- |
| 事前確認 | Hyper-V準備、OSインストール、ホスト名・IP・timezone、WinRM HTTPS、Firewall | 09/01 午前〜13:57 | PASS | [build validation](2026-09-01-ad-build-validation.md) | `New-VMSwitch`は管理者権限が必要。Hyper-V VMMSはUNC上のISO/VHDXを扱えず(認証エラー)、ローカルディスクへ移動 |
| 初回構築(フェーズ1) | 新規フォレスト作成・初回DC昇格(AIT-01) | 09/01 13:57〜14:30頃 | PASS | 同上 | `-ForestMode/-DomainMode WinThreshold`。自動再起動後に`CORP\Administrator`でログオン |
| 昇格後確認(フェーズ1) | 必須サービス、AD統合DNS、OU/GPO、FSMO(AIT-02〜05) | 09/01 午後 | PASS | 同上 | `New-ADOrganizationalUnit -Name "Users"`が`CN=Users`と衝突。`Employees`をドメイン直下へ(設計修正、#128) |
| バックアップ・復元(フェーズ1) | System Stateバックアップ、ADごみ箱復元(AIT-06、07) | 09/01 午後 | PASS | 同上 | Windows Server Backup機能が未反映で初回は記録されず、再導入。20GBのVHDXをD:として追加。ごみ箱検索は`Name`ではなく`ObjectGUID`で行う必要があった |
| 障害復旧(フェーズ1) | サービス停止復旧演習、RTO記録(AIT-08) | 09/01 午後 | PASS | 同上 | DNSサービス停止→起動、**RTO 0.906秒** |
| 再実行安全性(フェーズ1) | 昇格済みDCへ`Install-ADDSForest`を再実行(AIT-11) | 09/01 17:06〜 | PASS | 同上 | `TestFailedException`で停止、既存環境は無傷 |
| セキュリティ設定(フェーズ1) | LDAP署名/CB、SMBv1、監査、特権グループ、Firewallスコープ(AST-04〜08) | 09/01 午後 | PASS | 同上 | Firewallグループ名が日本語ローカライズ名で、英語名は`ObjectNotFound`(手順修正、#128) |
| windows_exporter導入(フェーズ1) | MSI導入、`ad`/`dns` collector有効化 | 09/02 午前 | PASS | [network validation](2026-09-01-network-host-validation-ad.md) ANW-05/06 | 当初この節を飛ばしてANW-05へ進み9182非待受で気づいた。閉域DCからGitHubへ出られず、管理端末で取得・検証し`Copy-Item -ToSession`で転送 |
| 実機network検証(フェーズ1) | ANW-01〜09(AIT-10) | 09/01 17:40〜09/02 10:30頃 | PASS | 同上 | 差異5件(LDAPS待受、pktmon構文、Firewall表示値、nltest、グループ名)。すべて文書側の誤りとして#128で修正 |
| 単体・設定確認 | AUT-01〜04 | 09/02 午前 | PASS | [build validation](2026-09-01-ad-build-validation.md) | AUT-01で復元コマンドの構文誤りを検出(#129で修正) |
| 中央統合(フェーズ2) | `app_node_exporter_targets`追記、scrape確認(AIT-09) | — | BLOCKED | — | 中央Prometheus hostが本ラボに無く、`monitoring` network `internal: true`制約も未解消 |
| 後処理 | 検証用ユーザー削除、一時IP削除、pktmon停止、MSI削除、最終状態取得 | 09/02 11:19 | PASS | 両証跡の終了判定 | RDP一時許可は使用せず。`phase1-complete`チェックポイント取得 |

## 4. 試験集計

| 区分 | 対象件数 | PASS | FAIL | BLOCKED | NOT RUN | 結果票 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 単体・設定確認(AUT) | 4 | 4 | 0 | 0 | 0 | [2026-09-01 build validation](2026-09-01-ad-build-validation.md) |
| 構築・結合試験(AIT) | 11 | 10 | 0 | 1 | 0 | 同上(AIT-09がBLOCKED) |
| セキュリティ試験(AST) | 8 | 8 | 0 | 0 | 0 | 同上 |
| ネットワーク実機検証(ANW) | 9 | 9 | 0 | 0 | 0 | [2026-09-01 network validation](2026-09-01-network-host-validation-ad.md) |
| 合計 | 32 | 31 | 0 | 1 | 0 | [試験仕様書・結果票](../build-package-ad/06-test-specification.md) |

フェーズ1の必須31 IDは31/31 PASS。BLOCKEDの1件はフェーズ2(AIT-09)であり、設計時点で前提が揃わないことが分かっていた項目です。

## 5. 設計値と実績値の差異

| 項目 | 設計値 | 実績値 | 影響 | 対応 / 承認 |
| --- | --- | --- | --- | --- |
| OS / ビルド番号 | Windows Server 2022 Standard, Desktop Experience | 同左、評価版、build `20348` | なし | 差異なし |
| CPU / memory / disk | 設計: 60GB単一ディスク | C: 30GB + D: 20GB(System State用に後から追加)。vCPU/メモリはHyper-V既定 | バックアップ先を別ボリュームにできたため、むしろ設計より安全 | ラボ構成として承認(本人)。パラメータシート実機記入欄に記録 |
| ドメインFQDN / NetBIOS名 / 機能レベル | `corp.example.test` / `CORP` / WinThreshold | 同左(`Windows2016Forest` / `Windows2016Domain`) | なし | 差異なし |
| IP / DNS / route | `192.0.2.50/24`、DNS `127.0.0.1`優先、閉域 | 同左。default routeなし | なし | 差異なし(閉域の理由を証跡に記録) |
| FSMO役割保持者 | 5役割すべて`ad-dc01` | 同左 | なし | 差異なし |
| OU構造 | `Employees`は`OU=Users`配下 | `Users`OUは作成不可。`Employees`はドメイン直下 | 設計誤り | #128で設計を修正。実機は修正後の設計と一致 |
| 既定ドメインGPOパスワードポリシー | 最小長14、複雑性、90日、履歴24、ロックアウト10回/10分/10分 | 同左 | なし | 差異なし |
| windows_exporter | バージョン`NOT SET`、中央Prometheus host限定のFirewallルール | `0.31.8`。Firewall許可ルールは未作成(中央host未決定) | 9182は既定Blockで全拒否。scrape不可はフェーズ2 BLOCKEDと同じ理由 | 承認(本人)。中央host決定時に`WindowsExporter-Prometheus-Only`を作成 |
| port / Firewall | 636/3269は非待受。`DefaultInboundAction`=Block | 636/3269は待受(WinRM用自己署名証明書をNTDSが採用)。永続ストア表示は`NotConfigured`、実効値はBlock | 設計書の前提が誤り。実害なし | #128で設計・手順を修正 |
| Firewallルールグループ名 | 英語名 | 日本語ローカライズ名 | 手順書どおりでは`ObjectNotFound` | #128で修正 |
| PowerShell | 組込5.1 + 7.4系追加導入 | 5.1のみ | 手順は5.1で完走。7.4固有の機能は使っていない | 承認(本人)。7.4導入は任意項目として残す |

## 6. 障害・課題・再試験

| ID | 発生時刻 | 事象 / 影響 | 原因 | 対応 | 再試験 | Issue |
| --- | --- | --- | --- | --- | --- | --- |
| LAB-01 | 09/01 午前 | Hyper-V GUIでISOをマウントできない(「ユーザー名またはパスワードが正しくありません」) | VMMSはSYSTEMで動作し、UNCパスへ認証できない | ISOとVM格納先をローカルディスクへ | PASS | — |
| LAB-02 | 09/01 午後 | `New-ADOrganizationalUnit -Name "Users"`が「既に使用されている名前」で失敗 | 既定`CN=Users`とRDNが衝突 | `Employees`をドメイン直下に作成 | PASS(AIT-04) | #128 |
| LAB-03 | 09/01 午後 | Firewallスコープ設定で英語グループ名3件が`ObjectNotFound` | 日本語版OSはグループ名がローカライズ | `Get-NetFirewallRule \| Select -ExpandProperty DisplayGroup -Unique`で実名を確認 | PASS(AST-08) | #128 |
| LAB-04 | 09/01 午後 | `wbadmin start systemstatebackup`が成功表示なのに`get versions`が空 | `Install-WindowsFeature Windows-Server-Backup`が未反映 | GUIで未導入を確認し再導入。バックアップ用に20GB VHDXを追加 | PASS(AIT-06) | — |
| LAB-05 | 09/01 午後 | ADごみ箱の削除済みオブジェクトが`Name`で見つからない | 削除時に`Name`が`<name>\nDEL:<GUID>`へ変わる | `ObjectGUID`で検索 | PASS(AIT-07) | — |
| LAB-06 | 09/01 夕 | 昇格後、管理端末からのWinRMが`AccessDenied` | Securityログ4625・サブステータス`0xC000006A`(パスワード誤入力)。VM内で`Start-Process -Credential`によりパスワード自体は正しいと確認 | 貼り付けで再入力 | PASS | — |
| LAB-07 | 09/02 午前 | `Invoke-WebRequest`でwindows_exporter MSIを取得できない | 閉域DCは`github.com`へ到達不可(default routeなし) | 管理端末で取得・SHA256検証→`Copy-Item -ToSession`→VM側で再検証 | PASS(ANW-05) | — |
| LAB-08 | 09/02 午前 | `pktmon start --etw -p 128`で`.etl`が生成されない | `--etw`は存在せず、`start`の`-p`は`--provider` | `pktmon start -h`で構文確認、`--capture --pkt-size 128`へ | PASS(ANW-07) | #128 |
| LAB-09 | 09/02 午前 | `Get-NetFirewallProfile`が`NotConfigured` | 永続ストアの値。実効値は`-PolicyStore ActiveStore` | ActiveStoreで`Block`を確認 | PASS(ANW-08) | #128 |
| LAB-10 | 09/02 午前 | AUT-01で`05`のブロック#41に構文エラー | `-version:<プレースホルダー>`の`<>`が文字列外 | 変数の文字列リテラルへ | PASS(AUT-01) | #129 |
| LAB-11 | 09/02 12:23 | System Stateバックアップ中にHyper-VがVMを一時停止→強制停止 | 5世代の差分チェーン上でVSS+数GB書き込み→ホストI/O停止(ホストログ12636/18524/18528) | チェーンを1世代に統合、自動チェックポイント無効化 | PASS(再バックアップ完走) | [復元演習](2026-09-02-ad-restore-drill.md) |
| LAB-12 | 09/02 13:2x | `LDAPServerIntegrity`が1に戻っていた | Default Domain Controllers Policyが「なし」を定義しレジストリ編集を上書き | GPMCで「署名必須」へ。`gpupdate`後`secedit`で`=4,2`、再起動後2886なし | PASS(AST-04再確認) | 同上 |
| LAB-13 | 09/02 15:37 | `bcdedit /deletevalue {current} safeboot`が失敗しDSRMで再起動 | PowerShellが`{current}`をスクリプトブロックと解釈 | `'{current}'`と引用符で囲む | PASS | 同上 |
| LAB-14 | 09/02 15:1x | DSRM起動後に「仮想マシン接続」が応答なし | 拡張セッションがセーフモードで成立しない | 基本セッションへ切替 | PASS | 同上 |
| LAB-15 | 09/02 12:22 | WinRM経由の`wbadmin`が56%で切断 | LAB-11のVM停止(および長時間・大量出力をWinRMで流していた) | コンソール実行+出力をファイルへ | PASS | 同上 |

切り分けはいずれも「仮説→実出力で反証→原因確定」の順で行い、推測でPASSにしたものはありません。詳細は各証跡の備考欄にあります。

## 7. 残存リスク・未実施

| 項目 | 状態 | 解除条件 |
| --- | --- | --- |
| 対象ホストの新規構築・受け入れ(フェーズ1) | PASS(ラボ) | 永続host・組織環境での再実施は`NOT RUN` |
| 実管理端末 / 内部ネットワーク / Firewall検証(フェーズ1) | PASS(ラボ) | 実ドメインメンバーからの認証・GPO適用は`NOT RUN`(ANW-09の境界) |
| サービス停止復旧演習・RTO記録(フェーズ1) | PASS(RTO 0.906秒) | — |
| System Stateバックアップ / ADごみ箱復元試験(フェーズ1) | PASS | System Stateからの**復元**も2026-09-02午後に実演し PASS([復元演習](2026-09-02-ad-restore-drill.md)、復元15分29秒、復旧全体約40分)。演習中に DC の強制停止(LAB-11)と GPO によるレジストリ上書き(LAB-12)を発見・解消 |
| host/ADメトリクスscrape(フェーズ2、AIT-09) | BLOCKED | 中央Prometheus hostの用意と`compose.yaml`のnetwork変更 |
| Windows対応Ansible roleの追加 | NOT READY | 変更なし |
| 2台目DC追加によるレプリケーション実測 | 実施済み(2026-09-03) | `ad-dc02`を追加し複製遅延17.8秒を実測、FSMO移譲でフォレスト2役割をdc02へ分離([証跡](2026-09-03-ad-second-dc-replication.md))。**dc02のフェーズ1相当設定を完了**(WinRM HTTPS / Firewall / RDP / SMBv1 / windows_exporter 0.31.8 / System Stateバックアップ 27分4秒)し、**GPO化したセキュリティ設定3件の自動継承**も検証済み。役割の奪取(seize)、DC 1台停止時の可用性試験は`NOT RUN` |
| **GPOの健全性(SYSVOL側の実体)** | 是正済み(2026-09-03) | 09-02のSystem State復元により、Default Domain Policyの`gpt.ini`と`GptTmpl.inf`、および`SYSVOL\domain\scripts`が失われていた。**単一DCでは無症状**(GPOは1件も適用されない状態だが、適用済みのローカルポリシーが残るため)。2台目追加時に発覚し、`gpt.ini`再作成と`scripts`作成で復旧([証跡](2026-09-03-ad-second-dc-replication.md) LAB-19/LAB-20)。復元後の確認手順を[構築手順書](../build-package-ad/05-build-procedure.md)14節に追加 |
| **セキュリティ設定のGPO化(残り2件)** | 是正済み(2026-09-03) | LAB-12では`LDAPServerIntegrity`のみGPO化していたが、`LdapEnforceChannelBinding`とDSアクセス監査はレジストリ/`auditpol`直編集のままで、**新規DCへ引き継がれない状態**だった。両方をDefault Domain Controllers Policyへ移し、両DCで実効値の一致を確認。[構築手順書](../build-package-ad/05-build-procedure.md)7.1・7.3節を改訂 |
| monitor-win-01のドメイン参加検証 | NOT RUN | 同上 |
| windows_exporterサービスアカウントの最小権限化 | NOT READY | `LocalSystem`で導入 |
| 定期バックアップのスケジュール登録 | **実動確認済み(2026-09-03)** | 登録: `wbadmin enable backup -addtarget:D: -schedule:03:30 -systemstate -quiet`。**自動実行を確認**: `LastRunTime 2026/09/03 10:43:43` / `LastTaskResult 0` / `NextRunTime 2026/09/04 3:30:30`、Backupログ`ID 1`(10:44:21)→`ID 4`(11:48:09)。ただし実行は03:30ではなく**OS起動7分半後のキャッチアップ**(ラボVMは03:30に停止していたため)。所要は他VMの構築作業と並行したため**63分48秒**(単独実行時24分17秒の2.6倍)。24時間稼働でない環境では実行時刻が保証されないこと、バックアップ枠は他の負荷と競合させないことを[構築手順書](../build-package-ad/05-build-procedure.md)9.1節に追記 |
| バックアップ保持14日の達成 | NOT MET(ラボ) | D:(20GB)に2世代で14GB使用、残り6GB。**この容量では14日分は保持できない**。Windows Server Backupに世代数・日数の指定パラメータは無く、格納先の空き容量に応じた自動ローテーションのため、目標値の達成には格納先容量の見積もりが必要 |
| 組み込み管理者(RID 500)の改名 | 実施済み(2026-09-02 夕) | 昇格後のためドメイン側で`Set-ADUser -SamAccountName` + `Rename-ADObject`。新名称で`whoami`成功、`SID.EndsWith('-500')=True`。新名称は秘密値台帳。DSRM用の名前は`Administrator`のまま(昇格後は変更不可) |
| PowerShell 7.4系の追加導入 | NOT RUN | 任意 |
| LDAPSの正式化(AD CS / 組織CA証明書) | NOT RUN | 現状はWinRM用自己署名証明書による偶発的な待受 |
| ログ集約(フェーズ2) | BLOCKED | 変更なし |
| 永続host再起動・24h/72h確認 | NOT RUN | ラボVMは随時停止するため対象外 |

## 8. 引き渡し物

| 成果物 | 対象版 / 保存先 | 受領確認 |
| --- | --- | --- |
| 対象ホストの状態識別子 | Hyper-Vチェックポイント`phase1-hardened`(2026-09-02 16:39)、`OsBuildNumber 20348`。差分チェーンは1世代(`.vhdx` 2 + `.avhdx` 2) | 受領(本人) |
| 設計・パラメータ | `docs/build-package-ad/`(#128 / #129 修正後) | 受領(本人) |
| 中央inventory変更(フェーズ2有効化時) | `NOT SET`(未適用) | — |
| 試験結果・実行ログ | [2026-09-01 build validation](2026-09-01-ad-build-validation.md) | 受領(本人) |
| ネットワーク実機検証結果票 | [2026-09-01 network validation](2026-09-01-network-host-validation-ad.md) | 受領(本人) |
| 運用ランブック | [運用runbook索引](../runbooks/README.md)(AD固有のrunbookは未作成) | 受領(本人) |
| backup / restore手順 | [パラメータシート](../build-package-ad/03-parameter-sheet.md)「バックアップ設計」、[構築手順書](../build-package-ad/05-build-procedure.md)復元節 | 受領(本人)。復元の実演は未実施 |
| 変更 / rollback記録 | 本報告書2節のチェックポイント系譜。`Restore-VMSnapshot -VMName ad-dc01 -Name <name>`で復元 | 受領(本人) |
| DSRMパスワードの受け渡し・再発行方法 | 本人のローカル秘密値メモ。再発行は`ntdsutil "set dsrm password"` | 受領(本人) |
| その他の秘密値 | 組み込み管理者(RID 500)は2026-09-02に改名済み。新名称は本人のローカル秘密値メモのみ(このリポジトリには記載しない)。DSRM用アカウント名は`Administrator`のまま。WinRM証明書の秘密鍵はVM内ストアのみ | 受領(本人) |

## 9. 完了・受領判定

- [x] フェーズ1の必須試験がすべて`PASS`で、結果票と集計が一致する(31/31)
- [x] フェーズ1に`FAIL` / `BLOCKED` / 必須の`NOT RUN`が残っていない
- [x] フェーズ2が「未実装」3点の解消条件とともに`BLOCKED`として明記されている
- [x] 設計差異、障害、残存リスク、未解決Issueを説明した(5節〜7節)
- [x] 一時設定・テストデータを撤去し、最終状態を採録した(検証用ユーザー削除、一時IP削除、pktmon停止、MSI削除、`phase1-complete`取得)
- [x] ロールバックまたは復元の開始条件と連絡先を共有した(チェックポイント復元。連絡先は本人)
- [x] DSRMパスワードの受け渡し・再発行方法を、値を記載せずに共有した
- [ ] [引き渡しチェックリスト](../build-package-ad/07-handover-checklist.md)を完了した — 永続host・24h/72h・組織環境の項目が対象外のため、ラボ範囲の項目のみ確認

| 判定 | 値 |
| --- | --- |
| 作業完了(フェーズ1) | `PASS`(ラボ範囲) |
| 作業完了(フェーズ2) | `BLOCKED`(未実装3点の解消が前提) |
| 引き渡し可否 | ラボ成果物として引き渡し可。組織環境への適用可否は本報告書の範囲外 |
| 判定理由 | 必須31 ID PASS、差異はすべて文書側の修正として解消、残存リスクは7節に列挙 |
| 引き渡し日時 | 2026-09-02 |
| 引き渡し元 / 先 | ns7jp(作業者) → ns7jp(ポートフォリオ所有者) |
| 承認者 | ns7jp |
