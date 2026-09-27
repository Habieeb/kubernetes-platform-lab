provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "kubernetes-platform-lab"
      Environment = "lab"
      ManagedBy   = "Terraform"
    }
  }
}
