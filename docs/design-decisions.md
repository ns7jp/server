# 設計判断記録（ADR要約）

この文書は「何を実装したか」ではなく、比較した案、採用理由、欠点、見直し条件を示す。
個人学習ラボの判断であり、あらゆる本番環境の正解を主張しない。

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
