# 試験仕様書・結果票

[要件定義書](00-requirements.md)の受け入れ条件を、再実行できるコマンドと期待結果へ展開した原本です。試験ID体系(WUT / WIT / WST / WNW)の正本は本書とし、他の文書(特に[ネットワーク実機検証手順](09-network-validation-procedure.md))は本書のIDを参照するだけに留めます。

> ## この文書の読み方(先に読んでください)
>
> **下の表がすべて `NOT RUN` なのは、まだ何も試していないからではありません。**
> [Linux版試験仕様書・結果票](../build-package/06-test-specification.md)と同じく、これは
> 対象ホストが決まっていない段階の**空白の原本**です。monitor-win-01 に相当する検証用ホストを
> 用意するたびに複製して記入し、原本自体は後から上書きしません。
>
> Linux版には既に実測済みの証跡([検証証跡台帳](../evidence/README.md)参照)へのリンクが
> ありますが、本書(Windows版)には**現時点で1件もありません**。本パックはまだ設計・手順書の
> 整備段階であり、monitor-win-01 に相当する実ホストの構築そのものが行われていないためです。
> したがって WUT / WIT / WST / WNW のいずれのIDについても、結果欄は `NOT RUN` が唯一の
> 正しい値です。これは「Linux版より試験項目が緩い」ことを意味せず、単に「この構築案件が
> まだ実施段階に入っていない」ことを示しています。
>
> ### フェーズ2のIDはBLOCKEDが前提です
>
> フェーズ2(中央監視統合)に属する **WIT-03、WIT-05、WIT-06、WIT-07、WIT-11** は、
> [要件定義書](00-requirements.md)に記載した次の「未実装」3点が解消するまで、実行しても
> 前提が揃わず `BLOCKED` になることが設計時点で分かっています。
>
> 1. `ansible/roles` 配下にWindows対応role(`common_windows`等)が無く、Ansibleでの自動構築ができない
> 2. Prometheusコンテナは `monitoring`(`internal: true`)に加え `host-access`(internal指定なしの
>    bridge)にも接続されており、nftables実機検証でMASQUERADE/`DOCKER-FORWARD` acceptを確認済みの
>    ため、`internal: true` 単体は外部egressを塞いでいない。未確立なのは、Dockerホストと対象
>    Windowsホストの実ネットワークセグメント間のL3到達性(`NOT SET`)、およびwindows_exporter側
>    Firewallが実際の送信元(Dockerホストの実IP)を許可しているか(`NOT SET`)の2点。現状のjob名
>    `linux-node` へWindowsを混ぜること自体、名前が実態と合わなくなる点も残存課題です
> 3. Windows Event Log / IISログを既存Lokiへ送る経路(Grafana Alloy for Windowsの導入、Lokiの
>    push APIをloopback以外からも安全に受け付けるための認証・network設計)が無い
>
> `BLOCKED` は失敗ではなく、前提条件と解除条件を記録した状態です。ただし本書は実行そのものを
> していない空白の原本なので、結果欄はここでもなお `NOT RUN` のままにし、実際に実行して
> `BLOCKED` と確定した時点で日付付きの証跡へ理由とともに記入します。期待結果欄には、
> どの未実装点が解除条件になるかをあらかじめ書き添えています。
>
> ### この原本を埋めるには
>
> monitor-win-01 に相当する検証用ホストを1台用意し([立ち上げ環境の選択肢](10-host-bringup-and-acceptance.md)参照)、
> [構築手順書](05-build-procedure.md)に沿ってフェーズ1を実施したうえで、本書の表と同じ試験IDに
> 対応する結果を記入します。記入した結果はこの原本を直接上書きせず、日付付きの証跡ファイル
> (例: `docs/evidence/YYYY-MM-DD-windows-build-validation.md`)へコピーして保存します。
> 命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせます。
>
> ネットワーク実機検証(WNW-01〜09)の記入様式は
> [Windows版ネットワーク結果票テンプレート](../evidence/templates/network-host-validation-windows.md)
> を使います。手順の詳細は[ネットワーク実機検証手順](09-network-validation-procedure.md)を正本とします。

## 記録情報

| 項目 | 値 |
| --- | --- |
| 実施日時 | `NOT RUN` |
| 実施者 | `NOT RUN` |
| 環境 | `NOT RUN` |
| ホストのビルド番号(`winver` または `Get-ComputerInfo` の `OsBuildNumber`) | `NOT SET` |
| windows_exporter バージョン / SHA256 | `NOT SET` |
| PowerShell バージョン(組込5.1 / 追加導入7.4系) | `NOT SET` |

結果は `PASS / FAIL / BLOCKED / NOT RUN` のいずれかを記入します。初期値の `NOT RUN` は成功実績ではありません。

| 判定 | 意味 |
| --- | --- |
| `PASS` | 期待結果を実出力で確認し証跡への参照がある |
| `FAIL` | 実行したが一致しない |
| `BLOCKED` | 前提不足で実行できず理由と解除条件がある |
| `NOT RUN` | 未実行、成功実績として数えない |

設計値と実績値は必ず分けて記録し、未実施の実績値は `NOT SET` / `NOT RUN` / `NOT READY` のいずれかを使います。安易に `PASS` へ書き換えないでください。

## 単体・設定確認

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| WUT-01 | PowerShellスクリプト構文チェック | `Invoke-ScriptAnalyzer`(PSScriptAnalyzer)または構文parse | exit 0 / エラー無し | NOT RUN | — |
| WUT-02 | 中央inventoryのdry-run | 中央host側で `app_node_exporter_targets` へWindows targetを追記後 `ansible-playbook site.yml --check --diff` | 意図した差分のみ(Windows target追加以外に変更なし) | NOT RUN | — |
| WUT-03 | windows_exporterインストーラのハッシュ検証 | `Get-FileHash <msi> -Algorithm SHA256` | 公開SHA256と一致 | NOT RUN | — |
| WUT-04 | Windows Defender Firewallルールの存在確認(dry) | `Get-NetFirewallRule` | 設計と一致 | NOT RUN | — |
| WUT-05 | 成果物リンク | `pytest tests/test_portfolio_artifacts.py -k internal_markdown_links` | README / docsの相対リンクがすべてリポジトリ内で解決 | NOT RUN | — |

WUT-02は中央host側(既存Linux監視host)の設定検証だけであり、Windows実機が無くても今すぐ実施できます。実機の有無を理由にNOT RUNのまま放置しないでください。

## 構築・結合試験

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| WIT-01 | 新規構築 | 本パックの手動PowerShell手順一式を実行 | エラーなく完了 | NOT RUN | — |
| WIT-02 | 冪等性 | 同一手順を2回目実行 | 不要な変更(サービス再作成、Firewallルール重複等)が発生しない | NOT RUN | — |
| WIT-03 | host metrics(フェーズ2) | 中央PrometheusのTargets画面を確認 | `up{job="linux-node", host="monitor-win-01"}=1`(BLOCKED: Dockerホスト↔対象ネットワーク間の実L3到達性、およびwindows_exporter側Firewall許可(Dockerホストの実IP向け)が確立するまで) | NOT RUN | — |
| WIT-04 | IIS site | health用エンドポイントへHTTP GET | 200 | NOT RUN | — |
| WIT-05 | blackbox probe(フェーズ2) | 中央blackbox-exporterのprobe結果を確認 | `probe_success=1`(BLOCKED: `ansible/roles/app/templates/prometheus.yml.j2` のprobe対象汎用化が未実装のため) | NOT RUN | — |
| WIT-06 | ログ集約(フェーズ2) | GrafanaでLogQLを実行 | Windows Event Log / IISログを検索できる(BLOCKED: Grafana Alloy for Windows未導入のため) | NOT RUN | — |
| WIT-07 | alert(フェーズ2) | テストアラートを発火 | 2分以内に通知(BLOCKED: WIT-03が前提のためBLOCKED) | NOT RUN | — |
| WIT-08 | サービス停止復旧演習(D-1相当) | windows_exporterまたはIISサービスを停止 | 検知・復旧・正常化までの時間を記録 | NOT RUN | — |
| WIT-09 | backup restore | バックアップアーカイブを別ボリューム/別ホストへ復元 | 内容が一致 | NOT RUN | — |
| WIT-10 | 実ホストnetwork | [WNW-01〜09](09-network-validation-procedure.md)を実行 | 設計どおり | NOT RUN | [結果票テンプレート](../evidence/templates/network-host-validation-windows.md) |
| WIT-11 | 複数ターゲットscrape(フェーズ2) | Windowsホストをもう1台追加 | テンプレート変更なしでup=1が増える(BLOCKED: `app_node_exporter_targets` の汎用性の実演。WIT-03解消後に有効) | NOT RUN | — |

## セキュリティ試験

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| WST-01 | WinRM listener確認 | `winrm enumerate winrm/config/listener` | HTTPSのみ、Basic無効 | NOT RUN | — |
| WST-02 | RDP状態確認 | `Get-NetFirewallRule -DisplayGroup "リモート デスクトップ"` | 既定Disable | NOT RUN | — |
| WST-03 | サービスアカウント確認 | `Get-CimInstance Win32_Service` | StartNameを記録(現状LocalSystem、是正は残存課題) | NOT RUN | — |
| WST-04 | Firewall許可範囲確認 | `Get-NetFirewallRule \| Where Enabled` | 許可Portと送信元が設計と一致 | NOT RUN | — |
| WST-05 | 秘密値追跡確認 | `git ls-files` | 証明書秘密鍵・パスワード等の実値が追跡されていない | NOT RUN | — |
| WST-06 | Windows Defender状態確認 | `Get-MpComputerStatus` | リアルタイム保護が有効 | NOT RUN | — |

## ネットワーク実機検証

Linux版の[NW-01〜09](../build-package/09-network-validation-procedure.md)に対応するWindows版のIDです。詳しい手順は[ネットワーク実機検証手順](09-network-validation-procedure.md)を正本とし、本書はID・操作・期待結果の一覧だけを保持します。

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| WNW-01 | interface / IP / CIDR | `Get-NetIPAddress`, `Get-NetAdapter` | 設計IPアドレス(192.0.2.30)とCIDRがOS実装と一致 | NOT RUN | — |
| WNW-02 | route / gateway | `Get-NetRoute`, `Test-NetConnection -TraceRoute` | 既定gatewayへの経路が設計どおり | NOT RUN | — |
| WNW-03 | DNS | `Resolve-DnsName monitor-win.example.test` | 名前解決結果が設計値と一致(または名前解決不可であることを明示) | NOT RUN | — |
| WNW-04 | ICMP | `Test-Connection`(管理端末⇔対象、対象⇔中央host双方向) | 設計どおりの到達性(許可/拒否) | NOT RUN | — |
| WNW-05 | 待受port | `Get-NetTCPConnection -State Listen` | 5986/tcp, 80/tcp, 443/tcp, 9182/tcpが設計どおり待受、3389/tcpは既定Disable | NOT RUN | — |
| WNW-06 | TCP / HTTP | `Invoke-WebRequest` または `curl.exe`(WinRM 5986、IIS 80/443、windows_exporterの`/metrics`) | 各serviceが設計どおりの応答 | NOT RUN | — |
| WNW-07 | packet capture | `pktmon`(Windows組込) | ヘッダのみ採録、認証情報を含む本文は採録しない。想定パケットが確認できる | NOT RUN | — |
| WNW-08 | Windows Defender Firewall | `Get-NetFirewallProfile`, `Get-NetFirewallRule` | プロファイル(系統A: Public、系統B: Domain)と許可ルールが設計と一致 | NOT RUN | — |
| WNW-09 | end-to-end | 管理元CIDR以外からの接続試行 | 拒否されることを確認 | NOT RUN | — |

WNW-09には、Linux版のNW-09との非対称性があります。Linux版は単一ホスト完結の検証(loopback bindのUI/metricsへSSHトンネル越しに到達できることを確認する)が正本ですが、Windows版は最初から複数ホスト構成(管理端末・Windows Server・中央監視host)であり、WinRM(HTTPS)自体が通信を暗号化しているためLinux版のSSHトンネルに相当する追加トンネルは不要です。その代わりWindows版で正本となるのは、管理元CIDR以外からの接続がWindows Defender Firewall(WNW-08で確認したルール)によって拒否されることの実機確認であり、ネットワーク層のFirewallが最終防衛線になります。この違いを結果票にも明記してください。

## 終了判定

- フェーズ1必須ID: WUT-01, WUT-02, WUT-05, WIT-01, WIT-02, WIT-04, WIT-08, WIT-09, WIT-10, WST-01, WST-02, WST-03, WST-04, WST-05, WST-06, WNW-01〜09
- フェーズ2必須ID(「未実装」3点の解消後に必須化): WIT-03, WIT-05, WIT-06, WIT-07, WIT-11
- フェーズ1の必須IDに `FAIL` または `BLOCKED` が1件でもあれば、フェーズ1(ホスト単体構築)は完了としません。
- フェーズ1の必須IDに `NOT RUN` が残る場合も、フェーズ1は完了としません。
- フェーズ2の必須IDは、未解消の3点(Windows対応Ansible role、Dockerホスト↔対象Windowsホスト間の実L3到達性とwindows_exporter側Firewall許可(Dockerホストの実IP向け)、Windows Event Log / IISログをLokiへ送る経路)が解消するまで `BLOCKED` であることを前提とします。`BLOCKED` のままであること自体はフェーズ1の完了判定には影響しません。
- 未実装3点の解消後もフェーズ2必須IDが `NOT RUN` のまま残る場合は、フェーズ2(中央監視統合)は完了としません。
- 構築案件全体の完了は、フェーズ1の必須試験がすべて `PASS` し、かつフェーズ2が「未実装3点」の解消条件とともに `BLOCKED` として明記されている状態を指します。両方が揃って初めて[作業結果・引き渡し報告書](11-work-result-report.md)へ記載できます。
- 結果はこの原本を直接上書きせず、日付付きの証跡ファイルへコピーして保存します。命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせます。
