# AWS / Terraform アーキテクチャ

オンプレ / 単一 VM 構成だった server-monitor を AWS 上に IaC で再構築するため、
v2.0 で Terraform 化した。Ansible（v1.2）は EC2 内部の設定担当として残し、
Terraform は VPC からモニタリング基盤までを宣言的に管理する。

## 全体構成

```mermaid
flowchart TB
    User[運用者 / 監視 SRE] -->|HTTPS:443| ALB[Application Load Balancer]

    subgraph VPC[VPC 10.0.0.0/16]
        direction TB
        subgraph Public_a[Public Subnet AZ-1a]
            ALB
            NAT[NAT Gateway<br/>単一 AZ・コスト優先]
        end
        subgraph Public_c[Public Subnet AZ-1c]
        end
        subgraph Private_a[Private Subnet AZ-1a]
            EC2_a[EC2 t3.small<br/>compose スタック]
        end
        subgraph Private_c[Private Subnet AZ-1c]
            EC2_c[EC2 t3.small<br/>compose スタック]
        end

        ALB --> EC2_a
        ALB --> EC2_c
        EC2_a --> NAT
        EC2_c --> NAT
    end

    NAT --> IGW[Internet Gateway]
    IGW --> Internet[Internet]

    EC2_a -.metrics + logs.-> CW[CloudWatch]
    EC2_c -.metrics + logs.-> CW

    CW --> SNS[SNS topic]
    SNS --> Email[アラート通知先メール]

    EC2_a -.snapshot.-> Backup[AWS Backup Vault<br/>KMS 暗号化]
    EC2_c -.snapshot.-> Backup

    CT[CloudTrail<br/>全リージョン] --> S3CT[(S3 bucket<br/>CloudTrail logs)]
    GD[GuardDuty]

    Budgets[AWS Budgets<br/>3,000 円 / 月] --> SNS
```

## モジュール責務

| モジュール | 担当範囲 | 主リソース |
| --- | --- | --- |
| `network` | VPC、Subnet、IGW、NAT、Route Table、VPC Flow Logs | `aws_vpc` / `aws_subnet` / `aws_nat_gateway` / `aws_flow_log` |
| `compute` | EC2、IMDSv2、IAM、EBS（KMS 暗号化）、夜間停止スケジュール | `aws_instance` / `aws_kms_key.ebs` / `aws_scheduler_schedule` |
| `alb` | ALB、Target Group、Listener、ACM、アクセスログ S3 | `aws_lb` / `aws_lb_listener` / `aws_lb_target_group` / `aws_s3_bucket.access_logs` |
| `monitoring` | CloudWatch アラーム、SNS、CloudTrail、GuardDuty、AWS Budgets | `aws_cloudwatch_metric_alarm` / `aws_sns_topic` / `aws_cloudtrail` / `aws_guardduty_detector` / `aws_budgets_budget` |
| `backup` | AWS Backup Vault、Plan、Selection、長期アーカイブ S3 | `aws_backup_vault` / `aws_backup_plan` / `aws_s3_bucket.archive` |

ALB と Compute の **循環依存** を避けるため、`aws_lb_target_group_attachment` は
モジュール内ではなく `environments/<env>/main.tf` で配線する。

## セキュリティ設計

| 領域 | 実装 |
| --- | --- |
| 公開範囲 | EC2 はプライベートサブネットのみ。インターネットへの egress は NAT 経由。ALB のみパブリック |
| ALB ingress | `allowed_ingress_cidrs` で制限。prod は validation で 1 件以上必須 |
| ALB TLS | `ELBSecurityPolicy-TLS13-1-2-2021-06`、prod は `certificate_arn` 必須 |
| EC2 認証 | SSH は既定で閉じ、SSM Session Manager のみ。インスタンスプロファイルで SSM 権限付与 |
| IMDS | v2 強制（`http_tokens = "required"`） |
| EBS | gp3、暗号化（顧客管理 KMS）、ルートも含めて all encrypted |
| S3 | アクセスログ用バケットは AES256（ALB の仕様）、CloudTrail / Archive は KMS。すべて Public Access Block 有効、Versioning 有効、`aws:SecureTransport=false` 拒否 |
| KMS | EBS / Flow Logs / 監査ログ / Backup の 4 系統で分離。すべて自動ローテーション有効 |
| 監査 | CloudTrail（全リージョン、ログ検証、KMS 暗号化、CloudWatch Logs 連携）+ GuardDuty + VPC Flow Logs |
| デフォルト SG | `aws_default_security_group` を空ルールでロックし、誤って使われないようにする |

## Ansible との接続

EC2 は `Application=server-monitor` タグと `AnsibleHost=true` タグを持つ。
Ansible 側は `ansible/inventory/aws_ec2.yml.example` の動的インベントリで
これらのタグから対象ホストを集める。

```bash
cd ansible
ansible-galaxy collection install amazon.aws
ansible-inventory -i inventory/aws_ec2.yml --graph
ansible-playbook -i inventory/aws_ec2.yml playbooks/site.yml
```

SSH ではなく SSM Session Manager 経由で接続する場合は `ansible_connection: aws_ssm`
を使う。`amazon.aws.aws_ssm` connection plugin を導入し、IAM 上で `ssm:StartSession`
を許可した踏み台ユーザーで実行する。

## トラフィック経路

| 区間 | プロトコル | 補足 |
| --- | --- | --- |
| User → ALB | HTTPS (TLS 1.2/1.3) | ACM 証明書、`drop_invalid_header_fields` |
| ALB → EC2 | HTTP 8080 | EC2 SG が ALB SG のみ許可。VPC 内 |
| EC2 → 外部 | HTTPS / HTTP（NAT 経由） | apt、Docker Hub、SSM、CloudWatch エンドポイント |
| EC2 → NTP | UDP 123 (169.254.169.123) | Amazon Time Sync Service |
| Prometheus → EC2 内 `/metrics` | HTTP（Bearer token） | Compose 内ネットワーク内 |

## 障害設計

| 障害想定 | 期待動作 | 検出 |
| --- | --- | --- |
| EC2 1 台故障 | ALB が他 AZ EC2 に振り分け継続 | `UnHealthyHostCount` アラーム |
| EC2 全台異常 | ALB 5xx 急増 → アラート、運用者が確認 | `HTTPCode_ELB_5XX_Count` アラーム |
| EBS 故障 | AWS Backup の最新スナップショットから復元 | EC2 ステータスチェック失敗アラーム |
| 設定誤りで EC2 停止 | EC2 ステータスチェック failed → 通知 → 復旧 | `StatusCheckFailed` アラーム |
| 予期せぬ課金 | Budgets 80% / 100% で SNS 通知 | `aws_budgets_budget` |
| 不審 API コール | GuardDuty findings | GuardDuty + 後続のレビュー |

## 拡張余地

- `single_nat_gateway = false` で NAT を AZ ごとに作り、NAT 障害時の冗長性を確保する
- EC2 を Auto Scaling Group + Launch Template に置き換え、Self-healing を導入する
- Prometheus の long-term storage を `remote_write` で AWS Managed Prometheus (AMP) に転送する
- Route 53 + ACM で公開 FQDN を構成する
- WAF を ALB の前段に追加し、SQL injection / XSS の基本的な保護を入れる
