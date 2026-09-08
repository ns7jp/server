# lab-base01：Docker最小構成の起動・認証・停止再開（2026-09-08）

## 結果と範囲

本人のHyper-V VMでメモリの見直しとLVM/ext4拡張を行い、Docker Engine・Composeを導入。
教材のPythonテスト167件、app/nginxの2サービス起動、HTTP認証、Nginxの計画停止・手動再開、
終了時のコンテナ・ネットワーク撤去を確認した。

**これは最小2サービスの実測であり、監視全体・Ansible・自動復旧D-1・AWSの実績ではない。**
前段の[初期構築記録](2026-09-08-lab-base01-initial-build.md)に続く別の演習で、
過去の167件以外のテスト件数やCI結果と合算しない。

## 来歴と実行環境

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIの案内を受けてVM・Windowsを操作し、出力の画像を提供 |
| 実施日 | 2026-09-08 JST（対話の日付）。各操作の厳密な開始・終了時刻は未採録 |
| 対象 | 既存の個人学習用Hyper-V VM `lab-base01`、Ubuntu Server 24.04.4 LTS、`opsadmin` |
| 教材・試験対象SHA | `1e5b3335cdf0d8ca7d0726b4411792be9f38c73a`（[E08]）。[この版の学習ガイド](https://github.com/ns7jp/server/blob/1e5b3335cdf0d8ca7d0726b4411792be9f38c73a/docs/beginner-learning-guide.md) |
| SHAの意味 | clone時のHEADを画像で採録し、後続操作は同じ作業ツリーで実施。終了時のSHA再採録、イメージへのrevision label照合は未実施 |
| 記録追加の基点 | `9431da08629556e95f1f27a6840e7f24ca9a294d`。記録を追加するmainのSHAであり、今回のVMで試験したSHAではない |
| Python | 3.12.3、`~/server/.venv`（[E08]） |
| Docker | Client/Server 29.8.0、Compose v5.5.1、linux/amd64（[E06]） |
| 画像 | 本人提供の[無加工の原画像17枚](screenshots/2026-09-08-lab-base01-compose/README.md)。ハッシュ・元ファイル名付き |
| 証拠の限界 | 連続terminal log、全パッケージのlock/freeze、Docker設定の全量は未採録。AIによるVM再実行ではない |

## 構築前の調整

| 調整 | 変更前 | 観測した変更後 | 限界 |
| --- | --- | --- | --- |
| メモリ | `free -h`で合計658MiB、available301MiB（[E01]） | Hyper-Vを2048MB固定にする手順の後、合計1.9GiB・available1.5GiB（[E02]） | Hyper-Vの設定画面は未提供。元の不足原因が動的メモリだったとは断定しない |
| LVM/ext4 | VG約17.32GiB、LV10GiB、VG未割当約7.32GiB（[E03]） | `lvextend -l +100%FREE -r /dev/ubuntu-vg/ubuntu-lv`で終了0、LV約17.32GiB・VFree0、dfで17G/空き12G（[E04]） | 仮想ディスク自体の拡張・新規PV追加ではない。変更前チェックポイントは案内済みだが作成完了画像・申告は未採録 |

メモリ2GiBは今回の最小構成で使用した値で、監視全体の十分条件ではない。
未割当VG領域を使ってOS領域を広げたため、今後別LVを作る際は残容量を再確認する。

## 試験結果

以下のCP番号は本記録専用の観点ID。前段のT-01〜21や監視案件の受け入れIDではない。

| ID | 観点 | 判定 | 画像と実測結果 |
| --- | --- | --- | --- |
| CP-01 | Docker配布元の登録 | PASS | `download.docker.com/linux/ubuntu noble`のInReleaseとamd64 Packagesを取得、表示範囲に署名エラーなし（[E05]） |
| CP-02 | Docker導入・起動 | PASS | service active、Client/Server/Composeの版数表示（[E06]） |
| CP-03 | コンテナの取得・実行 | PASS | `docker run --rm hello-world`でHello from Docker、終了0（[E07]）。テスト用イメージの削除は対象外 |
| CP-04 | 教材取得とvenv | PASS | main/リモート追跡表示、変更行なし、HEAD採録、Python3.12.3、venv有効（[E08]） |
| CP-05 | Pythonテスト | PASS | `python -m pytest -q`で167 passed in 4.08s、終了0（[E09]）。文書・設定の整合検査も含む |
| CP-06 | Docker操作権限 | PASS | opsadminのグループにdocker、sudoなしのdocker psが成功（[E10]） |
| CP-07 | 秘密値準備とGit除外 | PASS | 生成ブロック終了0、check-ignoreが4パス、git ls-filesとgit statusに行なし（[E11]） |
| CP-08 | app/nginxの起動 | PASS | build/up終了0、app Up/healthy、nginx Up、127.0.0.1:8080への公開（[E12]） |
| CP-09 | 応答と未認証アクセス | PASS | healthz200、画面401、metrics401（[E13]） |
| CP-10 | 正しい認証付きAPI | PASS | monitorのBasic認証でapi/stats200（[E14]）。Python標準ライブラリで秘密値ファイルを読み、HTTPコードだけ表示 |
| CP-11 | Nginx計画停止 | PASS | appはhealthyを維持、nginx Exited、curl接続エラー(7)と000（[E15]） |
| CP-12 | Nginx手動再開 | PASS | nginx Up、healthz200へ復帰（[E16]）。自動復旧・RTO測定ではない |
| CP-13 | 終了と撤去 | PASS | compose downで2コンテナと3ネットワーク削除、psは見出しのみ、deactivate後venv表示なし（[E17]） |

## 構成と認証の扱い

利用者の要求はUbuntu VMの`127.0.0.1:8080`からNginxを経てappへ届く。
appの`5000/tcp`表示はコンテナ側のポートで、ホストへの公開を示すものではない。
確認はUbuntu上から実施し、WindowsブラウザやSSHトンネル経由の画面確認は **NOT RUN**。

作成された3つのDockerネットワーク（frontend / host-access / monitoring）が存在しても、
PrometheusやGrafanaを起動した証明にはならない。今回起動したサービスはappとnginxのみ。

Docker操作権限のためopsadminをdockerグループへ追加した。これはroot相当の強い権限を
与える変更で、前段の「sudoにパスワードが必要」という試験結果を、
Dockerを含むすべての管理操作にパスワードが必要という意味には拡張しない。

`.env`と3つの秘密値ファイルを作成。秘密値ファイルの親ディレクトリは700、ファイルは
コンテナ内の別UIDから読み取れるよう644とする手順を実行した（[E11]）。
Git除外と追跡なしを確認し、本文・画像にパスワード本文やAuthorizationの値は掲載しない。
終了時のcompose downではこれらを削除・再生成しておらず、次回も同じ値を使用する方針。
終了後に各ファイルの存在を再検査した画像は未採録。

## 学習上の変更と失敗の扱い

- ランダムなパスワードを覚えることが難しいという相談を受け、手入力curlの代わりに
  `Path.read_text()`と`urllib.request`でファイルから読み、HTTPコードだけ表示する手順を案内。
  認証付き200を確認した。パスワードの暗記・値の公開を学習の前提にしない。
- Nginx停止中の000はHTTPステータスではなく「応答を取得できなかった」表示である。
  appがhealthyでも利用者の入口が停止すればアクセスできないことを前後画像で確認した。
- 停止表示0.7秒や再開表示0.4秒等はDocker CLIの表示で、利用者視点のRTOや自動復旧時間ではない。
- 「なぜappがhealthyでもアクセスできないか」の質問には、本人が「わかりません」と回答し、
  AIが入口とアプリの関係を説明した。**その後の本人による自分の言葉での説明は未確認**。
  操作結果の成功と理解・独力での再現を同一視しない。

## 未実施・未採録

- `compileall`は案内したが結果画像がない。構文チェック単独の終了0は未採録。
- Compose config --quietの独立した実行結果は未採録。upの成功をその記録として代用しない。
- HTTPテストは上記の4観点。誤ったBasic認証、正しいmetricsトークン、全APIの機能試験は未実施。
- Docker導入後のUFWとの相互作用を含む外部端末からの到達性再試験、再起動後のDocker自動起動、
  コンテナのログ保管・長期稼働・性能・再構築の再現性試験は **NOT RUN**。
- Prometheus / Grafana / Alloy / Loki / Alertmanagerの実起動・収集・表示・通知、
  全10サービスの前提診断結果、Ansible適用、D-1、AWSは **NOT RUN**。
- 手元VMの結果は指定SHAでのこの実行範囲に限る。最新mainやこのPRのCI成功をVM実測へ読み替えない。

## 次の作業

最小構成は撤去済み。次は同じclone・秘密値を使い、監視全体の前提診断を実行して
メモリ・空き容量を確認する段階。診断結果はまだ提供されていないため、監視は未着手として扱う。
独力の説明と再実行は別途記録する。

今回のPR作成で行うリンク・画像ハッシュ・差分検査は文書検査であり、上記のVM試験を再実行しない。

- [検証証跡台帳](README.md)
- [前段：初期構築・復旧演習](2026-09-08-lab-base01-initial-build.md)
- [画像・ハッシュ一覧](screenshots/2026-09-08-lab-base01-compose/README.md)

[E01]: screenshots/2026-09-08-lab-base01-compose/E01-memory-before.png
[E02]: screenshots/2026-09-08-lab-base01-compose/E02-memory-after.png
[E03]: screenshots/2026-09-08-lab-base01-compose/E03-lvm-before.png
[E04]: screenshots/2026-09-08-lab-base01-compose/E04-lvm-after.png
[E05]: screenshots/2026-09-08-lab-base01-compose/E05-docker-repository.png
[E06]: screenshots/2026-09-08-lab-base01-compose/E06-docker-versions.png
[E07]: screenshots/2026-09-08-lab-base01-compose/E07-hello-world.png
[E08]: screenshots/2026-09-08-lab-base01-compose/E08-source-version.png
[E09]: screenshots/2026-09-08-lab-base01-compose/E09-pytest.png
[E10]: screenshots/2026-09-08-lab-base01-compose/E10-docker-permission.png
[E11]: screenshots/2026-09-08-lab-base01-compose/E11-secret-exclusion.png
[E12]: screenshots/2026-09-08-lab-base01-compose/E12-compose-start.png
[E13]: screenshots/2026-09-08-lab-base01-compose/E13-http-unauthenticated.png
[E14]: screenshots/2026-09-08-lab-base01-compose/E14-http-authenticated.png
[E15]: screenshots/2026-09-08-lab-base01-compose/E15-nginx-stopped.png
[E16]: screenshots/2026-09-08-lab-base01-compose/E16-nginx-restarted.png
[E17]: screenshots/2026-09-08-lab-base01-compose/E17-compose-cleanup.png
