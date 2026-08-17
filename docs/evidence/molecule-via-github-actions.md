# Molecule を GitHub Actions で実行して証跡にする

`ansible-integration.yml` は `workflow_dispatch` で定義済みのため、**手元に Linux も Docker も
用意せず、ブラウザだけで Ansible ロールの結合検証を実行できる**。所要 15 分・0 円。

> **状態（2026-08-17 時点）**: このワークフローは **一度も実行されていない**（実行履歴 0 件）。
> [証跡採録チェックリスト](https://github.com/ns7jp/ns7jp/blob/main/docs/evidence-capture-checklist.md)
> の優先 1 に対応する。最も着手コストが低い実行証跡である。

---

## 何が検証されるか

`common` / `docker` / `nginx` / `monitoring` の 4 ロールについて、
Molecule が使い捨てコンテナを立てて次を順に実行する。

| フェーズ | 内容 | 意味 |
| --- | --- | --- |
| converge | ロールを実際に適用する | **設定が本当に適用できるか**（構文検査では分からない） |
| verify | 適用結果を検証する | サービス起動・ファイル配置・権限が期待どおりか |
| idempotence | もう一度適用して `changed=0` を確認する | **冪等性**。運用で最も重要な性質 |

`ansible-check.yml`（lint / syntax-check）との差はここにある。lint は「書き方が正しいか」しか
見ないが、Molecule は「**適用して、動いて、2 回目は変化しない**」ところまで見る。

---

## 実行手順

1. GitHub で `ns7jp/server-monitor` を開く。
2. **Actions** タブをクリックする。
3. 左サイドバーの一覧から **Ansible integration evidence** を選ぶ。
4. 右側に表示される **Run workflow** ボタンをクリックする。
5. Branch は `main` のまま **Run workflow** を押す。
6. 4 つのジョブ（`Molecule test (common)` など）が並列で走る。完了まで 10〜15 分。

---

## 採録する内容

各ジョブのログから次を控え、`docs/evidence/YYYY-MM-DD-molecule.md` に記録する
（雛形は [templates/molecule.md](templates/molecule.md)）。

| 項目 | 取得元 |
| --- | --- |
| 実行日時（JST） | 実行ページ上部 |
| 対象 commit SHA | 実行ページ上部の commit リンク |
| 実行 URL | ブラウザのアドレスバー（**第三者が再確認できる一次情報**） |
| ロールごとの結果 | 各ジョブの成否 |
| `PLAY RECAP` | ログ末尾の `ok=` `changed=` `failed=` の行 |
| idempotence の結果 | 2 回目適用が `changed=0` だったか |
| 所要時間 | 実行ページに表示される |

> ログをそのまま全文コピーする必要はない。**`PLAY RECAP` の行と、失敗した task の
> 抜粋があれば十分**。分量より、実行 URL と commit SHA が残っていることが重要。

---

## 失敗した場合

**失敗しても必ず採録する。** むしろ、そちらのほうが証跡としての価値が高い。

```text
症状: idempotence フェーズで changed=2 となり FAILED
原因: <どの task が 2 回目も changed になったか>
対処: <どう直したか>
学び: <なぜ最初に気づけなかったか>
```

この 4 点セットで [LEARNINGS.md](https://github.com/ns7jp/ns7jp/blob/main/LEARNINGS.md) に
追記する。「成功ログだけを並べたポートフォリオ」より、
「壊れて、原因を特定して、直した記録があるポートフォリオ」のほうが、
運用職の選考では明確に強い。

再実行は同じ手順で何度でもできる（無料）。**修正 → 再実行 → 緑になるまでの
過程そのものが、変更管理を回せることの証明になる。**

---

## この証跡の限界（明記すること）

Molecule はコンテナ上でロールを適用する。したがって次は**検証されない**。

- 実 VM / ベアメタルでのカーネル・systemd 依存の挙動
- 複数ホストにまたがる疎通、ファイアウォール、名前解決
- 監視スタック全体を起動したときの実際の動作（Grafana 表示、アラート発火、ログ収集）
- 障害からの復旧時間（RTO）

これらは [ローカル証跡採録ガイド](local-evidence-quickstart.md) の手順で、
Linux + Docker 環境を用意して別途採録する。**Molecule が通ったことを
「サーバー構築ができた」と表現しない。**

---

## 関連

- [検証証跡台帳](README.md)
- [ローカル証跡採録ガイド](local-evidence-quickstart.md)
- [採録テンプレート](templates/molecule.md)
- [02 Ansible 構成管理](https://github.com/ns7jp/ns7jp/blob/main/docs/server-monitor-improvements/02-ansible-automation.md)
