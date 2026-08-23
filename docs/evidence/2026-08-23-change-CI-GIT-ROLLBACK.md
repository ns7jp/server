# 2026-08-23 CI Git-mode 構成commitロールバック実測

## 目的と結論

GitHub-hostedの使い捨てUbuntu runnerに、候補commitをimmutableな40桁SHA指定の
`git` modeで配備し、変更前commitへ戻して再検証した。結果は **PASS** だった。

これはremote fetchを含むGit-mode配備・ロールバック手順のCI実測である。永続host、
staging / production、AWS復旧、D-2、Slack実配信、再起動後24h / 72h確認の実績ではない。

## 実行情報

| 項目 | 値 |
| --- | --- |
| 結果 | **PASS** / `GIT_MODE_ROLLBACK_REHEARSAL=PASS` |
| Actions run | [Full-stack Ansible E2E run 32611251044 / attempt 1](https://github.com/ns7jp/server-monitor/actions/runs/32611251044) |
| PR / event | [PR #77](https://github.com/ns7jp/server-monitor/pull/77) / `pull_request` |
| branch | `codex/execute-remaining-evidence-20260823` |
| head / candidate SHA | `84e149254d463a8a27a4cabcd09efa4504d1b47e` |
| candidate commit | `test: tolerate terraform formatter alignment` |
| rollback SHA | `59aa88ed1c8ccb7ba188909f0e079b834e9126c7` |
| requested base SHA | `59aa88ed1c8ccb7ba188909f0e079b834e9126c7`（選択結果と一致） |
| workflow checkout SHA | `1a8b424817ba1fff7eb75b0651a7e8bb41f9a965`（PR検証用merge SHA。配備対象ではない） |
| job実行時刻 | 2026-08-23 10:50:06〜10:56:42 JST（01:50:06〜01:56:42 UTC）、6分36秒 |
| rollback rehearsal step | 2026-08-23 10:54:07〜10:56:36 JST（01:54:07〜01:56:36 UTC）、2分29秒 |
| 対象 | GitHub-hosted Ubuntu 24.04.4 LTS / `/opt/server-monitor` |
| source mode | remote repositoryから取得するimmutable `git` SHA |
| tools | Python 3.12.14 / ansible-core 2.18.19 / Docker 28.0.4 / Compose v5.5.0 |
| artifact | `full-stack-e2e-32611251044-1` / ID `9485671697` / 50,498 bytes |
| artifact digest | `sha256:9b0846bbef8242a8c9db5b542d181f4c23b10c14c08f15f3c2758555732f515a` |
| artifact保存期限 | 2026-09-22 01:56:40 UTC |

`workflow-context.txt`の`source_sha`とGitHub runの`headSha`はいずれもcandidate SHAと一致した。
`change-context.txt`ではrollback rehearsal開始時刻、candidate / rollback SHA、配備先、
source modeを採録している。

## 実行方法

`.github/workflows/full-stack-e2e.yml`が、PR head SHAをcandidate、base SHAをrollback候補として
`scripts/e2e/select_rollback_sha.py`で安全な祖先commitを確定し、次を実行した。

```bash
bash scripts/e2e/run-git-rollback-rehearsal.sh \
  --confirm-disposable-host \
  --candidate-sha "$CANDIDATE_SHA" \
  --rollback-sha "$rollback_sha" \
  --requested-rollback-sha "$REQUESTED_ROLLBACK_SHA" \
  --git-repo-url "$GIT_REPO_URL" \
  --evidence-dir "$GITHUB_WORKSPACE/.artifacts/full-stack-e2e/current"
```

scriptは、使い捨てhostの明示確認、安全な`/opt`または`/srv`配下、credentialを埋め込んで
いないURL、40桁SHA、rollback SHAがcandidate SHAの祖先であることを確認してから変更した。

## 判定結果

| Gate | 結果 | 一次資料 / 実測値 |
| --- | --- | --- |
| candidate `--check --diff` | **PASS** | `candidate-check.log`: `ok=33 / changed=2 / failed=0` |
| candidate deploy | **PASS** | `candidate-deploy.log`: `ok=41 / changed=3 / failed=0` |
| candidate runtime verify | **PASS** | `candidate-verify.log`: `ok=12 / changed=0 / failed=0` |
| candidate revision marker | **PASS** | `candidate-revision.txt` = `84e149254d463a8a27a4cabcd09efa4504d1b47e` |
| candidate runtime content | **PASS** | expected / running-container manifest一致、`candidate-runtime-manifest.diff`は0 byte |
| rollback `--check --diff` | **PASS** | `rollback-check.log`: `ok=33 / changed=3 / failed=0` |
| rollback deploy | **PASS** | `rollback-deploy.log`: `ok=41 / changed=4 / failed=0` |
| rollback runtime verify | **PASS** | `rollback-verify.log`: `ok=12 / changed=0 / failed=0` |
| rollback revision marker | **PASS** | `rollback-revision.txt` = `59aa88ed1c8ccb7ba188909f0e079b834e9126c7` |
| rollback runtime content | **PASS** | expected / running-container manifest一致、`rollback-runtime-manifest.diff`は0 byte |
| app container再作成 | **PASS** | app container IDが`a50d454ac89d...`から`726f3da1911b...`へ変化 |
| stale file除去 | **PASS** | rollback diffに`*deleting .rollback-rehearsal-stale`を採録し、残存検査も成功 |
| loopback bind | **PASS** | `LOOPBACK_LISTENERS=PASS`。管理port `8080 / 9090 / 9093 / 3000 / 3100`は`127.0.0.1`のみ |
| rollback後Loki到達 | **PASS** | 固有path `/rollback-rehearsal-1787450194-18166`のNginx logをLogQLで1件取得 |
| 最終gate | **PASS** | `change-rollback-run.log`: `GIT_MODE_ROLLBACK_REHEARSAL=PASS` |

app image IDはcandidate / rollbackとも
`sha256:a8edc7f77f41f37ebf064fbc75d9ebbefe055820d03256fc6a0ca5a3628cf8c9`
だったが、container IDは異なる。したがって、同じアプリ内容のcommit間でも
force rebuild / recreate gateが実際にcontainerを置き換えたことを確認できる。

## 保存された一次資料

| ファイル | 判定に使った内容 |
| --- | --- |
| `change-rollback-summary.md` / `change-context.txt` | 最終結果、対象SHA、開始・完了時刻、scope |
| `candidate-*.log` / `rollback-*.log` | check、deploy、verifyのPLAY RECAP |
| `candidate-revision.txt` / `rollback-revision.txt` | 配備完了後のrevision marker |
| `*-expected-runtime-manifest.sha256` / `*-actual-runtime-manifest.sha256` | 各checkoutとrunning containerの5ファイルSHA256 |
| `*-runtime-manifest.diff` | candidate / rollbackとも0 byte |
| `*-app-container-id.txt` / `*-app-image-id.txt` | container置換とimage識別子 |
| `rollback-compose-ps.txt` / `rollback-listeners.txt` | 11 containersと管理portのloopback bind |
| `rollback-loki-query.json` | rollback後の固有Nginx log取得 |
| `change-rollback-run.log` | 全工程と最終PASS marker |

artifactにはcredential、token、Slack Webhook値を記録していない。artifact保存期限後も判定根拠が
失われないよう、対象SHA、時刻、主要gate、境界を本書へ転記した。

## 証跡境界

次の項目は、このPASSへ読み替えない。

- 永続host / staging / productionへの変更適用とロールバック: **NOT RUN**
- 実hostの再起動、24時間・72時間継続確認: **NOT RUN**
- AWS `terraform apply / destroy`、AWS Backup restore、D-2: **NOT RUN**
- AlertmanagerからSlackへの実配信: **NOT RUN**
- 独立した管理端末、組織DNS、cloud firewallを含むproduction network試験: **NOT RUN**

同じrun内のFull-stack E2E 23 IDも成功しているが、本書の新規実績は使い捨てrunner上の
Git-mode構成commitロールバックに限定する。既存のD-1 / volume restoreをD-2へ読み替えない。
