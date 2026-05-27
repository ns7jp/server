provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "server-monitor"
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "dev"
    }
  }
}
