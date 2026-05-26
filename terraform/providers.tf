terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# ── AWS provider ─────────────────────────────────────────────────
# Region is read automatically from:
#   1. AWS_REGION environment variable
#   2. ~/.aws/config default region
# Nothing is hardcoded here.
provider "aws" {
  default_tags {
    tags = {
      Project     = "ecommerce-platform"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ── Data sources: resolve account + region at runtime ────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Kubernetes + Helm providers fed from EKS module ──────────────
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}
