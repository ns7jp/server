terraform {
  backend "s3" {
    # 値は `terraform init -backend-config=backend.hcl` で投入する。
  }
}
