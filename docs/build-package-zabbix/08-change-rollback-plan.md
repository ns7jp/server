# 変更・ロールバック計画兼記録票

> 💡 **初めて読む方へ**: この文書は設定を変更するとき、「失敗したらどう戻すか」を先に決めておく文書です。案件パック全体の地図は[初心者ガイド](beginner-guide.md#08-変更ロールバック計画兼記録票)を参照してください。

## 1. 位置づけ

一般的な変更区分と PR 運用は [`docs/change-management.md`](../change-management.md)を正本とします。本書はこの構築案件（案件ID `SM-ZBX-001`、対象ホスト `zbx-01`）で「どの版からどの版へ変更し、どの条件で戻したか」を引き渡せる形で記録する案件固有の計画兼結果票です。

[Linux版変更・ロールバック計画](../build-package/08-change-rollback-plan.md)はGitのcommit SHAを基準にAnsibleで再配備するロールバックですが、本パックには専用Ansible role（`ansible/roles/zabbix_agent`相当）が無く、[要件定義書](00-requirements.md)の実装区分でいう「済(自動)」は`compose.zabbix.yaml`による`docker compose up -d`止まりです。そのため本書は、変更対象を次の3区分に分けて扱います。

1. **compose設定・Agent2設定（コード）**: `compose.zabbix.yaml`、`deploy/zabbix/`、`scripts/ops/zabbix-backup.sh`などGit管理下のファイル。commit SHAを基準に、6節のとおりgitと`docker compose`で戻せます。
2. **Frontend設定（Host / Template / Trigger / Action）**: Zabbix Frontend上の手動操作（済(手動)）で、Gitには残りません。変更前に標準のexport機能でXML化しておき、6節の手順で再importするか、7節のDB復元で戻します。
3. **DBデータ（PostgreSQL）**: 上記いずれの設定変更も最終的にはこのDBへ保存されます。設定を戻すだけではデータ破損を解消できない場合や、XML exportを取り忘れた場合は、7節の`pg_restore`手順を使います。

この原本の実施欄は初期状態では `NOT RUN` です。実作業では `docs/evidence/YYYY-MM-DD-change-<ID>.md` へコピーし、実際の値と出力を記録します。命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせます。

`zbx-01`に相当する実ホストの構築そのものがまだ行われていないため、本書に対応する日付付きevidenceは現時点で1件もありません。`compose.zabbix.yaml`の構文はCI（ZUT-01）で検証済みですが、これは変更・ロールバックの実測ではありません。以下の空欄は次の変更で再利用する原本であり、実ホストでの変更・ロールバックは現在も`NOT RUN`です。

## 2. 変更票

| 項目 | 計画・実績 |
| --- | --- |
| Change ID / 関連 Issue | `NOT SET` |
| 対象環境・ホスト | `NOT SET` |
| 変更対象区分（compose設定 / Agent2設定 / Frontend設定 / DBデータ） | `NOT SET` |
| 作業者 / 確認者 | `NOT SET` |
| 予定時間 / 実施時間 | `NOT SET` |
| 変更前 commit SHA | `NOT SET` |
| 変更後 commit SHA | `NOT SET` |
| 変更目的 | `NOT SET` |
| 影響を受ける service / port / data | `NOT SET` |
| 停止見込み | `NOT SET` |
| 直前バックアップ ID（`pg_dump`のtimestamp） | `NOT SET` |
| ロールバック判断期限 | `NOT SET` |
| 最終結果 | `NOT RUN` |

## 3. Go / No-Go 条件

次のどれかを満たさなければ実適用を開始しません。

- [ ] 対象ホスト（`zbx-01`）、変更対象区分（compose設定 / Agent2設定 / Frontend設定 / DBデータ）、変更前後の commit SHA を相互確認した
- [ ] 秘密値（DBパスワード、Slack bot token）、公開 IP が diff や採録ログへ出ないことを確認した
- [ ] `docker compose -f compose.zabbix.yaml config --quiet`が成功し、意図しないport / volume変更が無いことをdiffで確認した（ZUT-01相当）
- [ ] Frontend設定（Host / Template / Trigger / Action）を変更する場合、変更前の設定をZabbix標準のexport機能（Data collection > Templates等のExport）でXMLとして保存した
- [ ] 変更対象に対応する単体試験（`ZUT-01`〜`03`のうち該当するもの）が成功した
- [ ] データ変更を伴う場合、直前の`pg_dump`（`zabbix-backup.sh`）の作成時刻と`.dump` / `.sha256` / `.counts`ファイルの存在を確認した
- [ ] 変更前 commit を別 checkout から再配備できる
- [ ] ロールバック判断者、判断期限、サービス停止許容時間が決まっている

確認コマンド例です。出力には秘密値を含めません。

```bash
BEFORE_SHA='replace-with-the-full-current-commit-sha'
AFTER_SHA='replace-with-the-full-candidate-commit-sha'
git rev-parse HEAD
git diff --stat "$BEFORE_SHA..$AFTER_SHA" -- \
  compose.zabbix.yaml deploy/zabbix deploy/secrets scripts/ops/zabbix-backup.sh
docker compose -f compose.zabbix.yaml config --quiet
ls -la /var/backups/zabbix | tail -5
```

## 4. 変更手順

1. 変更開始時刻と、`docker compose -f compose.zabbix.yaml ps`によるZabbix Server / Web / Postgresの事前状態を記録します。
2. データ変更を伴う場合は`scripts/ops/zabbix-backup.sh`を`zbx-01`で実行し、終了状態と生成された`.dump` / `.dump.sha256` / `.dump.counts`のパスを記録します。
3. Frontend設定（Host / Template / Trigger / Action）を変更する場合は、変更前の設定をXML exportとして保存してから、Frontend上で変更を適用します。
4. compose設定・Agent2設定（コード）を変更する場合は、変更後commitをcheckoutした`zbx-01`上で`docker compose -f compose.zabbix.yaml up -d`を再適用します。
5. [試験仕様書](06-test-specification.md)の影響範囲（該当する`ZUT` / `ZIT` / `ZST` ID）を再実行します。
6. Zabbix Frontend上のProblem一覧、`docker compose ps`のhealthy状態、`docker compose logs`に新規異常がないことを確認します。
7. 監視時間を終えてから、継続またはロールバックを判定します。

```bash
cd /opt/zabbix-lab   # zbx-01での配備先(実機決定時に05-build-procedure.mdへ記録)
git fetch --all
git checkout "$AFTER_SHA"
docker compose -f compose.zabbix.yaml config --quiet
docker compose -f compose.zabbix.yaml up -d
docker compose -f compose.zabbix.yaml ps
docker compose -f compose.zabbix.yaml logs --tail 100 zabbix-server zabbix-web
```

## 5. ロールバック開始条件

次のいずれかが発生し、判断期限までに安全に解消できない場合は変更を継続せず戻します。

- `docker compose -f compose.zabbix.yaml up -d`後にいずれかのコンテナが`healthy` / `running`にならない
- Zabbix Frontendが規定時間内に200を返さない、または既定管理者（`Admin`/`zabbix`）のままログインできてしまう
- `monitor-01`のitemのlast dataが規定interval以内に更新されない（trapper受信不可）
- Frontendの認証が回避できる、または`127.0.0.1`以外へ公開される
- 新しい重大Problem（Severity: Disaster / High）、データ欠損、継続的なerror logが発生する
- compose適用が途中で失敗し、`zbx-01`の状態を確定できない
- 実測した復旧見込みが許容停止時間を超える

## 6. コード・設定のロールバック

作業中の checkout を `git reset --hard` で戻しません。Linux版と同じく、変更前 commit を別の一時 checkout に展開し、対象版が明確な状態で再適用します。旧SHAがremote repositoryに存在することをGo条件で確認します。

```bash
set -euo pipefail
ROLLBACK_SHA='replace-with-the-full-last-known-good-commit-sha'
ACTIVE_ENV='/opt/zabbix-lab/.env'
ACTIVE_DB_SECRET='/opt/zabbix-lab/deploy/secrets/zabbix_db_password.txt'
ACTIVE_SLACK_SECRET='/opt/zabbix-lab/deploy/secrets/zabbix_slack_bot_token.txt'
REPO_ROOT="$(git rev-parse --show-toplevel)"
ROLLBACK_WORKTREE="$(dirname "$REPO_ROOT")/zabbix-lab-rollback"
[[ "$ROLLBACK_SHA" =~ ^[0-9a-f]{40}$ ]]
test "$(git -C "$REPO_ROOT" rev-parse --verify "${ROLLBACK_SHA}^{commit}")" = "$ROLLBACK_SHA"
test ! -e "$ROLLBACK_WORKTREE"
test ! -L "$ROLLBACK_WORKTREE"
test -f "$ACTIVE_ENV"
test -f "$ACTIVE_DB_SECRET"
git -C "$REPO_ROOT" worktree add --detach "$ROLLBACK_WORKTREE" "$ROLLBACK_SHA"
```

`.env`と`deploy/secrets/*.txt`はGit管理外(gitignore対象)のため、`git worktree add`が作る新しいworktreeには含まれません。`compose.zabbix.yaml`が参照できるよう、稼働中の`/opt/zabbix-lab`から明示的にコピーします。

```bash
install -m 644 "$ACTIVE_ENV" "$ROLLBACK_WORKTREE/.env"
install -d -m 700 "$ROLLBACK_WORKTREE/deploy/secrets"
install -m 644 "$ACTIVE_DB_SECRET" "$ROLLBACK_WORKTREE/deploy/secrets/zabbix_db_password.txt"
if [[ -f "$ACTIVE_SLACK_SECRET" ]]; then
  install -m 644 "$ACTIVE_SLACK_SECRET" "$ROLLBACK_WORKTREE/deploy/secrets/zabbix_slack_bot_token.txt"
fi

cd "$ROLLBACK_WORKTREE"
docker compose -f compose.zabbix.yaml config --quiet
docker compose -f compose.zabbix.yaml up -d --force-recreate
docker compose -f compose.zabbix.yaml ps
```

`.env`をコピーし忘れると、`ZABBIX_SERVER_BIND_ADDRESS`が既定値の`127.0.0.1`へ戻ってtrapperが`monitor-01`から到達不能になります(エラーにならず静かに壊れるため、ロールバック後の疎通確認が必須です)。`deploy/secrets/zabbix_db_password.txt`をコピーし忘れると、`docker compose up`はsecretファイル不在でそのまま失敗します。

**バックアップtimerを忘れないこと**: `zabbix-backup.service`の`ExecStart`/`WorkingDirectory`は`/opt/zabbix-lab`を指したままです。ロールバックの原因が`scripts/ops/zabbix-backup.sh`自体やcompose構成にある場合、`/opt/zabbix-lab`を更新しない限りtimerの次回実行は変更後(ロールバック対象)のコードのまま動き続けます。ロールバック対象がバックアップ関連である場合は、unitをworktree側へ向け直します。

```bash
sudo systemctl stop zabbix-backup.timer
sudo sed -e "s#/opt/zabbix-lab#${ROLLBACK_WORKTREE}#g" \
  "$ROLLBACK_WORKTREE/deploy/systemd/zabbix-backup.service" \
  | sudo tee /etc/systemd/system/zabbix-backup.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl start zabbix-backup.timer
```

恒久対応としては、`/opt/zabbix-lab`自体を`$ROLLBACK_SHA`のcheckoutへ置き換えて(または通常の`git checkout`で戻して)worktreeを解消し、unitの参照先を`/opt/zabbix-lab`へ戻すことを推奨します。それまでの間、`$ROLLBACK_WORKTREE`が実質的な配備先になっていることをチームへ共有してください。

Frontend設定（Host / Template / Trigger / Action）は、上記のコードロールバックでは戻りません。3節のGo / No-Go確認時点でexportしたXMLを、Frontendの「Import」機能から再取込みします。XMLを保存していなかった場合は、7節の`pg_restore`でDBごと戻します。Zabbixの設定はコードではなくDBに保存されるという前提が、Linux版のAnsible再配備と最も異なる点です。

`docker compose ps`のhealthy状態と、Frontend上のHost / Template / Trigger / Actionが変更前の内容と一致することを確認します。ロールバック後も、認証、bind address、trapperの許可送信元、`monitor-01`からのitem last dataを再試験します。不要になった一時worktreeの削除は、証跡を保存し対象pathを確認した後に別作業として行います。

## 7. データのロールバック（`pg_restore`による復元手順）

設定を戻すだけではデータ破損を解消できない場合、またはFrontend設定のXML exportを取得し忘れていた場合に、`scripts/ops/zabbix-backup.sh`が生成した`pg_dump`（custom format）から`pg_restore`で復元します。[バックアップ・復旧設計](../backup-restore.md)と同じ「別volume / 別DBへ復元して内容を確認してから切り替える」考え方に従い、稼働中のDBへ直接`--clean`で上書きしません。

- 破損した`zabbix_db_data` volumeを直ちに削除せず、調査用に識別・隔離します。
- 復元元dumpの日時とファイル名（`zabbix-<UTC_TIMESTAMP>.dump`）、`sha256sum -c`によるcheck結果を記録します。
- 別volume / 別コンテナへ復元し、`scripts/ops/zabbix-backup.sh`がdumpと同時に記録した`<DUMP_FILE>.counts`（バックアップ時点のhost数・item数）と比較してから切り替えます（ZIT-08と同じ検証）。稼働中DBは今回の障害で既に破損している可能性があるため比較対象にしません。
- 秘密値（DBパスワード）はバックアップアーカイブではなく、`deploy/secrets/zabbix_db_password.txt`の受け渡し元（承認された秘密管理先）から復元します。
- ZIT-08の実測証跡がない間は、DB障害からの復元を「検証済み」と記載しません。

```bash
set -euo pipefail
DUMP_FILE='/var/backups/zabbix/zabbix-<UTC_TIMESTAMP>.dump'
# scripts/ops/zabbix-backup.sh は .sha256 ファイルへ basename だけを記録するため、
# sha256sum -c はそのファイルがあるディレクトリで実行する(別ディレクトリから実行すると
# 「No such file or directory」でFAILし、set -euoにより以降の復元処理が中断する)。
( cd -- "$(dirname -- "${DUMP_FILE}")" && sha256sum -c "$(basename -- "${DUMP_FILE}").sha256" )

# 検証用の別volume/別コンテナへ復元する(稼働中のzabbix_db_dataは直接上書きしない)
docker volume create zabbix_db_data_restore_check
docker run -d --name zabbix-restore-check \
  -e POSTGRES_DB=zabbix -e POSTGRES_USER=zabbix \
  -e POSTGRES_PASSWORD_FILE=/run/secrets/zabbix_db_password \
  -v zabbix_db_data_restore_check:/var/lib/postgresql/data \
  -v "$(pwd)/deploy/secrets/zabbix_db_password.txt:/run/secrets/zabbix_db_password:ro" \
  postgres:16-alpine
# 起動しない/secretが読めない等でpg_isreadyが永遠にFAILし続けないよう、上限(60秒)を設ける。
READY=0
for _ in $(seq 1 60); do
  if docker exec zabbix-restore-check pg_isready -U zabbix >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 1
done
if [[ "${READY}" -ne 1 ]]; then
  echo "zabbix-restore-check did not become ready within 60s; container status/logs:" >&2
  docker ps -a --filter name=zabbix-restore-check >&2
  docker logs zabbix-restore-check >&2
  exit 1
fi
docker exec -i zabbix-restore-check pg_restore -U zabbix -d zabbix --clean --if-exists < "${DUMP_FILE}"

# host数・item数を比較する(ZIT-08)。稼働中DBは今回の障害で既に破損している可能性がある
# ため比較対象にせず、バックアップ時点の記録( "${DUMP_FILE}.counts" )と比較する。
cat "${DUMP_FILE}.counts"
docker exec zabbix-restore-check psql -U zabbix -d zabbix -Atc 'select count(*) from hosts;'
docker exec zabbix-restore-check psql -U zabbix -d zabbix -Atc 'select count(*) from items;'

# 検証用リソースの後始末(本番へ切り替えない場合)
docker rm -f zabbix-restore-check
docker volume rm zabbix_db_data_restore_check
```

`<DUMP_FILE>.counts`は`pg_dump`と別接続で読んだ値のため、バックアップ実行中にhosts/itemsが変更されていた場合はdump内容とわずかに食い違うことがあります。この比較は復元が明らかに壊れていないかを確認する目安であり、完全な整合性の証明ではありません。件数が一致し、かつFrontend上のHost / Template / Trigger / Actionの内容も想定どおりであることを確認できたら、本番へ切り替えます。件数がわずかに異なる場合は、Frontend上の内容確認を優先し、直近の意図した変更（Host/Item追加・削除）で説明がつくかを確認してください。切り替えは`docker compose -f compose.zabbix.yaml stop zabbix-server zabbix-web`の後、稼働中の`zabbix_db_data`に対して同じ`pg_restore --clean --if-exists`を実行し、`docker compose -f compose.zabbix.yaml up -d`で再開する手順です。

## 8. 実施結果

| 時刻 | 操作 / 判断 | コマンドまたは証跡 | 結果 |
| --- | --- | --- | --- |
| `NOT RUN` | 変更前確認 | — | NOT RUN |
| `NOT RUN` | 変更適用 | — | NOT RUN |
| `NOT RUN` | 適用後試験 | — | NOT RUN |
| `NOT RUN` | 継続 / ロールバック判断 | — | NOT RUN |
| `NOT RUN` | ロールバック（必要時） | — | NOT RUN |

## 9. 終了条件

- [ ] 変更後またはロールバック後の commit SHA と `docker compose -f compose.zabbix.yaml ps` の稼働状態が一致する
- [ ] 必須 smoke test と影響範囲の再試験（該当する `ZUT` / `ZIT` / `ZST`）が `PASS`
- [ ] 変更前後の時刻、実出力、判断理由を evidence へ保存した
- [ ] 残存リスク、暫定対応、恒久対応の Issue を記録した
- [ ] 一時的な UFW 許可、`DOCKER-USER` iptables chainの一時ルール（trapper送信元の緩和など）、試験データ、保守モードを解除した
