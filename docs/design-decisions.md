# 設計判断記録（ADR要約）

この文書は「何を実装したか」ではなく、比較した案、採用理由、欠点、見直し条件を示す。
個人学習ラボの判断であり、あらゆる本番環境の正解を主張しない。

> **ADRとは**: Architecture Decision Record の略。設計判断を「比較案・採用理由・欠点・
> 見直し条件」の形で残す記録方法で、決定した内容だけでなく、なぜ他の案を選ばなかったかを
> 残すことで後から見直す判断基準になる。用語の詳細は
> [サーバー構築キーワード集](server-building-keywords.md#adrarchitecture-decision-record)を参照。

## ADR-001: 入門環境はKubernetesではなくDocker Composeにする

- **背景**: 1台のLinux VMで通信、volume、監視を観察できることを優先する。
- **比較**: native systemd、Docker Compose、Kubernetes。
- **判断**: Composeを採用する。複数サービスを宣言的かつ少ない前提で再現できる。
- **欠点**: 複数host scheduling、無停止更新、self-healingの制御面は提供しない。
- **見直し条件**: 複数host、高可用性、autoscalingが要件になったとき。

## ADR-002: TerraformとAnsibleの責務を分ける

- **背景**: cloud resourceとguest OS設定では、変更単位と確認方法が異なる。
- **判断**: TerraformはVPC/EC2/ALB等、AnsibleはOS/Docker/application設定を担当する。
- **代替案**: Terraform provisionerだけでOS設定、またはAnsibleだけでAWS APIを操作する。
- **欠点**: stateとinventoryの受け渡しが増え、二つのtoolを学ぶ必要がある。
- **見直し条件**: image bakingへ全面移行する、またはcloud resourceが不要になるとき。

## ADR-003: 管理portは既定でloopbackだけに公開する

- **背景**: Grafana、Prometheus、Loki等を誤ってLAN/Internetへ露出させたくない。
- **判断**: Composeのpublished portを`127.0.0.1`へbindし、管理者はSSH tunnelを使う。
- **代替案**: `0.0.0.0`公開とfirewallだけ、VPN、identity-aware proxy。
- **欠点**: remote accessにSSH tunnelの理解が必要。
- **見直し条件**: 組織SSO、VPN、reverse proxyの認可を含む管理面が用意されたとき。

## ADR-004: 学習用UIはBasic認証、metricsはBearer tokenを使う

- **背景**: 人が見るUIとcollectorが読むendpointの資格情報を分離する。
- **判断**: UI/APIはBasic、`/metrics`はBearer token、秘密値未設定時はfail closedとする。
- **欠点**: Basic認証単体にはMFA、session失効、利用者別監査がない。TLSなしでは使わない。
- **見直し条件**: 複数利用者、退職者管理、MFA、SSOが要件になったとき。

## ADR-005: local labでは監視stackを対象hostへ同居させる

- **背景**: 1台でmetrics/logs/dashboardの経路を学べることを優先する。
- **判断**: Prometheus/Loki/Grafanaを同居させるが、同じhostの停止を外形監視できるとは主張しない。
- **欠点**: host故障時に監視と履歴も同時に失う。複数hostの履歴も統合されない。
- **見直し条件**: availability/SLOを外部から測るときは、外部probeと中央telemetryへ分離する。

## ADR-006: 正常系だけでなく障害注入と復元を受け入れ条件にする

- **背景**: 起動成功だけでは、検知、切り分け、復旧可能性を示せない。
- **判断**: D-1、network fault、backup restoreを再実行可能な演習として持つ。
- **欠点**: 誤った対象で実行すると停止・データ消失を招くため、破棄可能環境と事前baselineが必須。
- **見直し条件**: productionで行う場合は承認、maintenance window、blast radius制御を追加する。

## ADR-007: 実装状態と実測状態を分離する

- **背景**: IaCやrunbookが存在しても、対象環境で成功したとは限らない。
- **判断**: `PASS / FAIL / BLOCKED / NOT RUN` と日付付きevidenceを使い、原本を上書きしない。
- **欠点**: 文書更新の手間と、commitごとの証跡管理が増える。
- **見直し条件**: 廃止しない。自動化する場合も環境、時刻、revision、raw resultを保持する。

## ADR-008: 監視stackのimage版を固定し、見直しを計画して行う

2026-09-28に追加。Prometheus `v2.55.1`、Alertmanager `v0.27.0`、Grafana `11.2.2`、Loki `2.9.0`
（[パラメータシート](build-package/03-parameter-sheet.md#コンテナアプリのversion基準)）を固定したまま
残している理由と、見直しの方針を記録する。

- **背景**: 版を`latest`にせず固定しているのは、CI（`python-check.yml`の`promtool`・Loki設定検査）、
  Full-stack E2E、2026-09-08のlab-base01実習の結果を「どの版で確かめたか」と結び付けるためである。
  一方で、これらはいずれも最新ではなく、次の大きな版（Prometheus 3系、Loki 3系、Grafana 12系）が
  既に出ている。このラボでは Promtail の EOL（2026-03-02）により収集エージェントを Alloy へ
  移行している（[プロジェクト資料](project-reference.md)）。同じことが監視stackの各imageにも起こり得るため、
  「固定したまま理由も更新方針も無い」状態を改める。
- **判断**: 当面は現在の版を固定したまま残し、更新は次の手順で1つずつ行う。
  1. 更新前に、対象の公式リリースノートと移行ガイドで、互換性のない変更と保守状況を確認する。
  2. 1つのimageだけを上げ、CI（`promtool check config / rules`、Loki設定検査）と
     Full-stack E2Eを再実行する。複数を同時に上げない。
  3. 結果を日付付きevidenceに残し、[パラメータシート](build-package/03-parameter-sheet.md)と
     CIのimage指定（`.github/workflows/python-check.yml`）を同じ変更で更新する。
- **既知の制約（更新時に壊れるもの）**:
  - **Loki 2.9 → 3系**: `deploy/loki/loki-config.yml`は`store: boltdb-shipper`・`schema: v12`で、
    compactorに`shared_store: filesystem`を指定している。Loki 3系では`shared_store`が廃止されるため、
    このままでは起動しない。`schema_config`に新しい期間（`from`は更新日より後の日付）を追加して
    `store: tsdb`・`schema: v13`へ移し、compactorは`delete_request_store`を指定する形へ書き換える
    必要がある。既存のログは旧期間の設定で読み続ける。
  - **Prometheus 2 → 3系**: 設定項目・PromQL・既定値の一部に互換性のない変更がある。
    `deploy/prometheus/`の設定とルールを新しい版の`promtool`で検査してから上げる。
  - **Grafana 11 → 12系、Alertmanager**: provisioning（`deploy/grafana/`）とダッシュボードJSON、
    `alertmanager.yml`が新しい版で読み込めるかを確認する。
  - Dependabotの`docker`監視は`Dockerfile`だけが対象で、`compose.yaml`のimageは自動更新の
    対象外である。更新に気づく手段は、現状では手動の確認だけである。
- **欠点**: 固定している間は、上流の不具合修正やセキュリティ修正が自動では入らない。
- **見直し条件**: 次のいずれかが起きたとき、上の手順で更新を検討する。
  - 固定している版に、影響のあるセキュリティ修正が出た。
  - 固定している系列の保守終了が公式に告知された、または確認した。
  - 四半期に1回の定期確認（リリースノートと保守状況の確認）の時期になった。
- **状態**: 2026-09-28時点で、どの更新も実施・検証していない（`NOT RUN`）。
