# 2026-08-23 現行main CI再検証

## 目的

PR #76をmergeした現行`main`について、以前のcommitにしかなかったMolecule統合証跡と
Backup/RestoreのCI証跡を手動で再実行した。これはGitHub-hosted runner内の検証であり、
独立host、Slack実配信、AWS構築、D-2、再起動後72時間確認の代替ではない。

## 対象

| 項目 | 値 |
| --- | --- |
| commit SHA | `59aa88ed1c8ccb7ba188909f0e079b834e9126c7` |
| 実行日 | 2026-08-23 |
| 起動方法 | GitHub Actions `workflow_dispatch` |
| 実行環境 | GitHub-hosted runner |

## 結果

| Workflow / job | Run | 結果 | 実測範囲 |
| --- | --- | --- | --- |
| Ansible integration evidence / Molecule `common` | [32606763914](https://github.com/ns7jp/server-monitor/actions/runs/32606763914) | PASS | create → converge → idempotence → verify |
| Ansible integration evidence / Molecule `docker` | [32606763914](https://github.com/ns7jp/server-monitor/actions/runs/32606763914) | PASS | create → converge → idempotence → verify |
| Ansible integration evidence / Molecule `nginx` | [32606763914](https://github.com/ns7jp/server-monitor/actions/runs/32606763914) | PASS | create → converge → idempotence → verify |
| Ansible integration evidence / Molecule `monitoring` | [32606763914](https://github.com/ns7jp/server-monitor/actions/runs/32606763914) | PASS | create → converge → idempotence → verify |
| Backup verify / script syntax | [32606763827](https://github.com/ns7jp/server-monitor/actions/runs/32606763827) | PASS | template render、bash syntax、ShellCheck |
| Backup verify / archive smoke | [32606763827](https://github.com/ns7jp/server-monitor/actions/runs/32606763827) | PASS | fake Compose volumesのarchive作成・非空確認 |
| Backup verify / AWS recovery point age | [32606763827](https://github.com/ns7jp/server-monitor/actions/runs/32606763827) | SKIPPED | AWS Variable / OIDC role未設定のため。AWS PASSではない |

両runの`headSha`は上記commitと一致し、結論は`success`だった。AWS jobのskipを
AWS Backup、AWS apply、snapshot restoreの実績へ読み替えない。

## 境界

- Moleculeはrunner上のDocker検証であり、Docker未導入の独立Ubuntuホストではない。
- Backup smokeは同一runner上の一時volumeであり、別host復旧のD-2ではない。
- Slack Webhook、AWS credential、self-hosted runnerは設定されていない。
- 構成commit / 設定rollback rehearsalは本記録の対象外である。
