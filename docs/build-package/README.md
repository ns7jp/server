# Linux サーバー構築案件パック

このディレクトリは `server-monitor` を一つの小規模サーバー構築案件と見立て、設計から引き渡しまでの成果物を工程順にまとめたものです。本文書にある「予定値」と、実機で取得した「結果」は分けて管理します。

## 最短レビュー順

1. [基本設計書](01-basic-design.md) — 目的、対象範囲、構成、非機能要件
2. [パラメータシート](03-parameter-sheet.md) — OS・SSH・FW・Docker・監視の設定値
3. [構築手順書](05-build-procedure.md) — Ubuntu 1 台を Ansible で構築する手順
4. [試験仕様書・結果票](06-test-specification.md) — 合否基準と実測結果の記入先
5. [検証証跡台帳](../evidence/README.md) — 実測済み・未実測の境界

## 成果物一覧

| 工程 | 成果物 | 状態 |
| --- | --- | --- |
| 要件・基本設計 | [01-basic-design.md](01-basic-design.md) | 作成済み |
| 詳細設計 | [02-detailed-design.md](02-detailed-design.md) | 作成済み |
| パラメータ設計 | [03-parameter-sheet.md](03-parameter-sheet.md) | 作成済み |
| ネットワーク設計 | [04-network-ip-plan.md](04-network-ip-plan.md) | 作成済み |
| 構築 | [05-build-procedure.md](05-build-procedure.md) | 手順作成済み・実機結果は証跡台帳で管理 |
| 試験 | [06-test-specification.md](06-test-specification.md) | 仕様作成済み・未実施欄は `NOT RUN` |
| 引き渡し | [07-handover-checklist.md](07-handover-checklist.md) | 作成済み |

## 検証環境

基準環境は Ubuntu Server 24.04 LTS の単一ホストです。構成コードは Ubuntu 22.04 LTS にも対応しますが、両バージョンでの実測を意味しません。AWS 構成は別の発展構成であり、実際の `apply / destroy` が記録されるまでは設計・コード実装済みとして扱います。

## 完了の定義

次をすべて満たした時点で「構築・試験完了」とします。

- `ansible/playbooks/site.yml` が `failed=0` で終了する
- 2 回目の適用が `changed=0` になる
- [試験仕様書](06-test-specification.md)の必須項目がすべて `PASS`
- Grafana、Loki、Alertmanager、D-1 復旧演習の証跡が commit SHA 付きで保存される
- 未解決事項、秘密値の受け渡し方法、ロールバック方法が引き渡し記録に残る

