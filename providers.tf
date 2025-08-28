# providers.tf - Configuración del proveedor

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.5.0"
}

provider "aws" {
  region = var.aws_region
}


# Provider Random para generar sufijos únicos
provider "random" {}

# Data sources adicionales
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}