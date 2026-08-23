terraform {
  backend "s3" {
    # Values are supplied with `terraform init -backend-config=backend.hcl`.
    # Keep the staging state key separate from dev and prod.
  }
}
