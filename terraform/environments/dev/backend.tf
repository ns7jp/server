terraform {
  backend "s3" {
    # 値は `terraform init -backend-config=backend.hcl` で投入する。
    # backend.hcl.example をコピーして実値を入れる運用。
  }
}
