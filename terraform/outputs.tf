# ================================================================
# outputs.tf
# All values are fetched from AWS — nothing is hardcoded.
# Run "terraform output" after apply to see all values.
# ================================================================

output "account_id" {
  description = "AWS Account ID (auto-detected)"
  value       = local.account_id
}

output "region" {
  description = "AWS Region (auto-detected)"
  value       = local.region
}

output "ecr_registry" {
  description = "ECR registry base URL — use in Dockerfiles and CI pipeline"
  value       = local.ecr_registry
}

output "ecr_repository_urls" {
  description = "Full ECR URL per service — map of service-name → URL"
  value       = module.ecr.repository_urls
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN — used for IRSA role bindings"
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs — worker nodes run here"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs — ALB and NAT Gateways"
  value       = module.vpc.public_subnet_ids
}

output "ebs_csi_role_arn" {
  description = "IAM role ARN for EBS CSI Driver"
  value       = module.iam.ebs_csi_role_arn
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = module.iam.alb_controller_role_arn
}

output "karpenter_controller_role_arn" {
  description = "IAM role ARN for Karpenter controller"
  value       = module.karpenter.karpenter_role_arn
}

output "karpenter_sqs_queue_name" {
  description = "SQS queue name for Karpenter Spot interruption handling"
  value       = module.karpenter.sqs_queue_name
}

output "grafana_admin_password" {
  description = "Grafana admin password — auto-generated, never hardcoded"
  value       = random_password.grafana.result
  sensitive   = true
  # Retrieve: terraform output -raw grafana_admin_password
}

output "kubeconfig_command" {
  description = "Run this command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${local.region} --name ${var.cluster_name}"
}

output "next_steps" {
  description = "What to do after terraform apply"
  value = <<-MSG

  ╔══════════════════════════════════════════════════════════════════╗
  ║  Terraform apply complete!                                      ║
  ╠══════════════════════════════════════════════════════════════════╣
  ║                                                                  ║
  ║  Step 1 — Configure kubectl:                                    ║
  ║    aws eks update-kubeconfig \                                  ║
  ║      --region ${local.region} \                                 ║
  ║      --name ${var.cluster_name}                                 ║
  ║                                                                  ║
  ║  Step 2 — Install cluster components:                           ║
  ║    cd ../../ecommerce-k8s-gitops                                ║
  ║    make bootstrap                                               ║
  ║                                                                  ║
  ║  Step 3 — Get Grafana password:                                 ║
  ║    terraform output -raw grafana_admin_password                 ║
  ║                                                                  ║
  ║  Step 4 — Get your app URL (after first deploy):                ║
  ║    kubectl get ingress -n ecommerce-prod                        ║
  ║    (copy the ADDRESS column — that is your ALB DNS URL)         ║
  ║                                                                  ║
  ╚══════════════════════════════════════════════════════════════════╝
  MSG
}
