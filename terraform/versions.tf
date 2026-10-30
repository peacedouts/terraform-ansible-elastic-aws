terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 7.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4"
    }
  }

  # Remote state is recommended. Copy backend.tf.example to backend.tf and fill it in.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = merge(
      {
        Project   = var.name_prefix
        ManagedBy = "terraform"
      },
      var.extra_tags,
    )
  }
}
