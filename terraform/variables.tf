# ================================================================
# variables.tf
#
# Only ONE variable requires user input: github_username
# Set it once: export TF_VAR_github_username=your-github-username
#
# Everything else (account ID, region, ECR URLs, ALB DNS) is
# resolved automatically from AWS at runtime.
# ================================================================

variable "github_username" {
  description = "Your GitHub username — used in ArgoCD Application manifest"
  type        = string
  # No default: terraform will prompt if not set via env var
  # Recommended: export TF_VAR_github_username=ahmedrabe33
}

variable "environment" {
  description = "Deployment environment label"
  type        = string
  default     = "prod"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "ecommerce-eks-prod"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.29"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_suffixes" {
  description = "AZ letter suffixes — appended to current region automatically"
  type        = list(string)
  default     = ["a", "b", "c"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs — one per AZ, for worker nodes"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs — one per AZ, for ALB and NAT Gateways"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "baseline_node_instance_type" {
  description = "Instance type for the baseline Managed Node Group (system workloads)"
  type        = string
  default     = "m5.large"
}

variable "baseline_node_desired" {
  description = "Desired node count for baseline MNG"
  type        = number
  default     = 3
}

variable "baseline_node_min" {
  description = "Minimum node count for baseline MNG"
  type        = number
  default     = 3
}

variable "baseline_node_max" {
  description = "Maximum node count for baseline MNG"
  type        = number
  default     = 6
}

variable "ecr_services" {
  description = "List of microservices — one ECR repository created per service"
  type        = list(string)
  default = [
    "ecommerce-frontend",
    "ecommerce-admin",
    "ecommerce-gateway",
    "ecommerce-user-auth",
    "ecommerce-catalog",
    "ecommerce-shopping",
    "ecommerce-inventory",
    "ecommerce-order-payment",
    "ecommerce-fulfillment",
    "ecommerce-platform"
  ]
}
