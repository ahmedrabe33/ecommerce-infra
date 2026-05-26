# ================================================================
# main.tf — Root module
# Wires all child modules together.
# All inputs come from locals or other module outputs.
# ================================================================

# ── VPC: 3 AZs, public + private subnets, 3 NAT Gateways ────────
module "vpc" {
  source               = "./modules/vpc"
  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = local.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  environment          = var.environment
}

# ── EKS: cluster, OIDC provider, baseline Managed Node Group ────
module "eks" {
  source                      = "./modules/eks"
  cluster_name                = var.cluster_name
  cluster_version             = var.cluster_version
  vpc_id                      = module.vpc.vpc_id
  private_subnet_ids          = module.vpc.private_subnet_ids
  baseline_node_instance_type = var.baseline_node_instance_type
  baseline_node_desired       = var.baseline_node_desired
  baseline_node_min           = var.baseline_node_min
  baseline_node_max           = var.baseline_node_max
  environment                 = var.environment
  account_id                  = local.account_id
}

# ── IAM: IRSA roles for EBS CSI Driver and ALB Controller ───────
module "iam" {
  source            = "./modules/iam"
  cluster_name      = var.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  account_id        = local.account_id
  region            = local.region
  environment       = var.environment
}

# ── Karpenter: IAM role, SQS queue, EventBridge rules ───────────
module "karpenter" {
  source             = "./modules/karpenter"
  cluster_name       = var.cluster_name
  cluster_endpoint   = module.eks.cluster_endpoint
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url
  node_iam_role_name = module.eks.node_iam_role_name
  account_id         = local.account_id
  region             = local.region
  environment        = var.environment
}

# ── ECR: one private repository per microservice ─────────────────
module "ecr" {
  source      = "./modules/ecr"
  services    = var.ecr_services
  environment = var.environment
}

# ── Random Grafana admin password ────────────────────────────────
resource "random_password" "grafana" {
  length           = 20
  special          = true
  override_special = "!#%&*()-_=+[]{}:?"
}

# ================================================================
# Generated files — Terraform writes these into the GitOps repo
# after apply, so they contain real values (no placeholders).
# ================================================================

# ArgoCD Application manifest with real GitHub repo URL
resource "local_file" "argocd_app" {
  filename        = "${path.module}/../../ecommerce-k8s-gitops/argocd/ecommerce-prod-app.yaml"
  file_permission = "0644"
  content         = templatefile("${path.module}/templates/argocd-app.yaml.tpl", {
    github_username = var.github_username
    cluster_name    = var.cluster_name
    environment     = var.environment
  })
}

# Kustomize overlay with real ECR registry URL
resource "local_file" "kustomization" {
  filename        = "${path.module}/../../ecommerce-k8s-gitops/overlays/eks-prod/kustomization.yaml"
  file_permission = "0644"
  content         = templatefile("${path.module}/templates/kustomization.yaml.tpl", {
    ecr_registry = local.ecr_registry
    services     = var.ecr_services
  })
}

# Helm production values with real ECR registry
resource "local_file" "values_prod" {
  filename        = "${path.module}/../../ecommerce-k8s-gitops/overlays/eks-prod/values-prod.yaml"
  file_permission = "0644"
  content         = templatefile("${path.module}/templates/values-prod.yaml.tpl", {
    ecr_registry = local.ecr_registry
    environment  = var.environment
  })
}

# Karpenter EC2NodeClass with real cluster name and node role
resource "local_file" "ec2nodeclass" {
  filename        = "${path.module}/../../ecommerce-k8s-gitops/karpenter/ec2nodeclass.yaml"
  file_permission = "0644"
  content         = templatefile("${path.module}/templates/ec2nodeclass.yaml.tpl", {
    cluster_name            = var.cluster_name
    karpenter_node_role_name = module.karpenter.karpenter_node_role_name
  })
}
