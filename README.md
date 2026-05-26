# ecommerce-infra

> **Production-grade AWS infrastructure for an ecommerce microservices platform.**
> Terraform + Ansible. Zero hardcoded values. Fully automated.

---

## What This Repo Provisions

| Layer | What Gets Created |
|---|---|
| **Network** | VPC across 3 AZs · 3 public subnets · 3 private subnets · Internet Gateway · 3 NAT Gateways · Route tables |
| **Compute** | EKS cluster (v1.29) · Managed Node Group (system baseline) · OIDC provider |
| **Autoscaling** | Karpenter IAM role · SQS interruption queue · EventBridge rules for Spot |
| **Storage** | EBS CSI Driver IAM role + EKS addon |
| **Networking** | ALB Controller IAM role + policy |
| **Registry** | 10 ECR repositories (one per microservice) with lifecycle policies |
| **State** | S3 bucket (versioned, encrypted) · DynamoDB lock table |
| **Generated** | ArgoCD Application manifest · Kustomize overlay · Helm values · EC2NodeClass |

---

## Architecture Overview

```
Internet
    │
    ▼
AWS ALB  ◄── provisioned by ALB Controller (runs inside EKS)
    │         sits in PUBLIC subnets
    │
    ▼  HTTP only (ALB DNS name — no custom domain needed)
gateway pod  ◄── only service exposed to ALB
    │
    ▼  ClusterIP (internal only)
┌─────────────────────────────────────────────┐
│            EKS Cluster  (private subnets)   │
│                                             │
│  Managed Node Group (system workloads)      │
│  ├── Karpenter                              │
│  ├── Argo CD                                │
│  ├── ALB Controller                         │
│  ├── EBS CSI Driver                         │
│  └── Prometheus + Grafana                   │
│                                             │
│  Karpenter Nodes (app workloads)            │
│  ├── frontend, admin, gateway               │
│  ├── user-auth, catalog, shopping           │
│  ├── inventory, order-payment               │
│  ├── fulfillment, platform                  │
│  └── postgres, redis, rabbitmq (StatefulSet)│
└─────────────────────────────────────────────┘
         │  outbound only via NAT Gateways
         ▼
    Internet (ECR pulls, AWS API calls)
```

### Why 3 Availability Zones?

- **Fault tolerance** — if one AZ fails, 2 AZs keep serving traffic
- **Quorum** — RabbitMQ and other consensus systems need an odd number (3) to elect a leader without split-brain. With 2 replicas a single failure loses majority.
- **EKS SLA** — the EKS control plane itself spans 3 AZs; your workers should too

### Two-Tier Node Design

| Tier | Who runs here | How it scales |
|---|---|---|
| **Managed Node Group** (3 nodes, always on) | Karpenter, ArgoCD, ALB Controller, EBS CSI, Prometheus | Manual (you control the min/max) |
| **Karpenter Nodes** (0 → many) | All application workloads | Fully automatic based on pending pods |

Karpenter nodes cannot run Karpenter itself — that would be a chicken-and-egg problem. The Managed Node Group solves this by providing a stable baseline that always exists.

---

## Prerequisites

You need these on your local machine before starting:

```bash
# Check all required tools are installed
aws --version          # AWS CLI v2
terraform --version    # >= 1.7.0
git --version
```

You need AWS credentials configured:

```bash
aws configure
# OR
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=us-east-1
```

Your IAM user/role needs these permissions:
- `AdministratorAccess` (for initial setup) **or** the following policies:
  - `AmazonEKSClusterPolicy`
  - `AmazonVPCFullAccess`
  - `IAMFullAccess`
  - `AmazonEC2FullAccess`
  - `AmazonSQSFullAccess`
  - `AmazonECRFullAccess`
  - `AmazonDynamoDBFullAccess`
  - `AmazonS3FullAccess`

---

## Deploy — Step by Step

### Step 1 — Clone and enter the repo

```bash
git clone https://github.com/YOUR_USERNAME/ecommerce-infra.git
cd ecommerce-infra
```

### Step 2 — Bootstrap the Terraform state backend

This creates the S3 bucket and DynamoDB table for remote state. Run **once only**.

```bash
cd scripts
bash bootstrap-backend.sh
cd ..
```

What it does:
- Creates `ecommerce-tfstate-<YOUR_ACCOUNT_ID>` S3 bucket (unique per account)
- Enables versioning and encryption on the bucket
- Creates `ecommerce-tfstate-lock` DynamoDB table
- Writes `terraform/backend.hcl` with your real values

### Step 3 — Set your GitHub username

This is the only value you need to provide. It is used to write the ArgoCD Application manifest with your real GitOps repo URL.

```bash
export TF_VAR_github_username=YOUR_GITHUB_USERNAME
```

> **Tip:** Add this to your `~/.bashrc` or `~/.zshrc` so you don't need to set it every time.

### Step 4 — Initialize Terraform

```bash
cd terraform
terraform init -backend-config=backend.hcl
```

Expected output:
```
Initializing the backend...
Successfully configured the backend "s3"!
Initializing provider plugins...
Terraform has been successfully initialized!
```

### Step 5 — Review the plan

```bash
terraform plan
```

Review what will be created. Key resources to look for:
- `aws_vpc.main` — your VPC
- `aws_eks_cluster.main` — EKS cluster
- `aws_eks_node_group.baseline` — 3 system nodes
- `aws_ecr_repository.services["ecommerce-*"]` — 10 ECR repos
- `aws_sqs_queue.interruption` — Karpenter Spot queue
- `aws_iam_role.*` — all IRSA roles
- `local_file.*` — generated files written to GitOps repo

### Step 6 — Apply

```bash
terraform apply
```

Type `yes` when prompted.

⏱ **Expected duration: 15–20 minutes** (EKS cluster creation takes the most time)

### Step 7 — Read the output

After apply completes, Terraform prints:

```
Outputs:

account_id              = "123456789012"
region                  = "us-east-1"
cluster_name            = "ecommerce-eks-prod"
ecr_registry            = "123456789012.dkr.ecr.us-east-1.amazonaws.com"
ecr_repository_urls     = { ... }
alb_controller_role_arn = "arn:aws:iam::..."
karpenter_sqs_queue_name = "ecommerce-eks-prod-karpenter-interruption"
kubeconfig_command      = "aws eks update-kubeconfig --region us-east-1 --name ecommerce-eks-prod"
next_steps              = ...
grafana_admin_password  = <sensitive>  # see below
```

### Step 8 — Configure kubectl

```bash
aws eks update-kubeconfig --region $(aws configure get region) --name ecommerce-eks-prod
```

Verify:
```bash
kubectl get nodes
# Should show 3 nodes in Running state
```

### Step 9 — Get the Grafana password

```bash
terraform output -raw grafana_admin_password
# Copy this — you need it to log in to Grafana
```

---

## What Terraform Generates Automatically

After `terraform apply`, these files are written into the `ecommerce-k8s-gitops` repo (if it exists as a sibling directory):

| Generated File | Contains |
|---|---|
| `ecommerce-k8s-gitops/argocd/ecommerce-prod-app.yaml` | ArgoCD Application pointing to your GitHub repo |
| `ecommerce-k8s-gitops/overlays/eks-prod/kustomization.yaml` | Image overrides with real ECR URLs |
| `ecommerce-k8s-gitops/overlays/eks-prod/values-prod.yaml` | Helm values with real ECR registry |
| `ecommerce-k8s-gitops/karpenter/ec2nodeclass.yaml` | Karpenter config with real cluster name and node role |

If the GitOps repo does not exist yet, the files are written to `terraform/generated/` instead. Commit them to the GitOps repo manually.

---

## Directory Structure

```
ecommerce-infra/
│
├── scripts/
│   └── bootstrap-backend.sh        # Run ONCE before terraform init
│
├── terraform/
│   ├── backend.tf                  # Backend config (partial — filled by backend.hcl)
│   ├── backend.hcl.template        # Template showing backend.hcl format
│   ├── providers.tf                # AWS, Kubernetes, Helm, Random providers
│   ├── variables.tf                # All variables (only github_username requires input)
│   ├── locals.tf                   # Derived values from AWS data sources
│   ├── main.tf                     # Root module — wires all modules + generates files
│   ├── outputs.tf                  # All outputs including next_steps guide
│   │
│   ├── modules/
│   │   ├── vpc/                    # VPC, subnets, IGW, NAT GWs, route tables
│   │   ├── eks/                    # EKS cluster, OIDC, Managed Node Group
│   │   ├── iam/                    # EBS CSI + ALB Controller IRSA roles
│   │   ├── karpenter/              # Karpenter IAM, SQS, EventBridge
│   │   └── ecr/                    # ECR repos + lifecycle policies
│   │
│   └── templates/
│       ├── argocd-app.yaml.tpl     # ArgoCD Application template
│       ├── kustomization.yaml.tpl  # Kustomize overlay template
│       ├── values-prod.yaml.tpl    # Helm values template
│       └── ec2nodeclass.yaml.tpl   # Karpenter EC2NodeClass template
│
└── ansible/
    ├── inventory/
    │   └── hosts.ini               # Jenkins + admin machine IPs
    └── playbooks/
        ├── jenkins-setup.yml       # Install Jenkins, Docker, Trivy, kubectl
        └── admin-tools.yml         # Install kubectl, helm, terraform, argocd CLI
```

---

## Configure Servers with Ansible (Optional)

If you are running Jenkins on an EC2 instance:

```bash
# 1. Fill in EC2 IPs in ansible/inventory/hosts.ini

# 2. Install Jenkins + Docker + Trivy on your CI server
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/jenkins-setup.yml

# 3. Install kubectl, helm, terraform on your admin machine
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/admin-tools.yml
```

---

## Verification Commands

Run these after `terraform apply` and `kubectl` is configured:

```bash
# Cluster is healthy
kubectl get nodes -L topology.kubernetes.io/zone

# System pods are running on baseline nodes
kubectl get pods -n kube-system -o wide

# EKS addons are active
aws eks list-addons --cluster-name ecommerce-eks-prod

# ECR repos exist
aws ecr describe-repositories --query 'repositories[*].repositoryName' --output table

# Karpenter SQS queue exists
aws sqs get-queue-url --queue-name ecommerce-eks-prod-karpenter-interruption

# IAM roles created
aws iam list-roles --query 'Roles[?contains(RoleName,`ecommerce`)].RoleName' --output table
```

---

## Outputs Reference

| Output | Description | How to use |
|---|---|---|
| `account_id` | AWS Account ID | Reference in scripts |
| `region` | AWS Region | Reference in scripts |
| `ecr_registry` | ECR base URL | Set in Jenkinsfile |
| `ecr_repository_urls` | Full URL per service | Map: service → URL |
| `cluster_name` | EKS cluster name | `kubectl`, `aws eks` commands |
| `kubeconfig_command` | Ready-to-run `aws eks` command | Configure kubectl |
| `alb_controller_role_arn` | IAM role for ALB Controller Helm install | Helm `--set` flag |
| `karpenter_sqs_queue_name` | SQS queue for Karpenter | Karpenter Helm install |
| `grafana_admin_password` | Grafana login password | Grafana UI |
| `next_steps` | Full step-by-step guide | Printed after apply |

To get sensitive outputs:
```bash
terraform output -raw grafana_admin_password
terraform output -raw cluster_endpoint
```

---

## Tear Down

```bash
cd terraform

# Destroy all AWS resources
terraform destroy

# Then manually delete the S3 bucket (Terraform cannot delete non-empty buckets)
aws s3 rm s3://ecommerce-tfstate-$(aws sts get-caller-identity --query Account --output text) --recursive
aws s3 rb s3://ecommerce-tfstate-$(aws sts get-caller-identity --query Account --output text)
aws dynamodb delete-table --table-name ecommerce-tfstate-lock
```

> ⚠️ `terraform destroy` will delete the EKS cluster, all nodes, all ECR repos, the VPC, and all IAM roles. Make sure you have backed up any important data first.

---

## Security Notes

| Control | Implementation |
|---|---|
| Worker nodes in private subnets | Nodes have no public IPs — outbound via NAT only |
| ALB is the only public entry | Only the gateway service is reachable from the internet |
| IRSA (no static credentials) | Pods get AWS permissions via IAM role — no access keys in pods |
| ECR scan on push | Every image scanned for CVEs on push |
| EBS volumes encrypted | `encrypted: true` in StorageClass and EC2NodeClass |
| State encrypted | S3 bucket uses AES256 encryption |
| State locked | DynamoDB prevents concurrent applies |

**What is NOT production-ready in this repo (and why):**

- Kubernetes Secrets are base64 only — not encrypted at rest. Production option: [External Secrets Operator](https://external-secrets.io/) + AWS Secrets Manager.
- EKS API endpoint is public (`endpoint_public_access = true`). For strict production: set to `false` and access via VPN or bastion only.
- Single Grafana password shared. Production: use SSO/OIDC with Grafana.

---

## Troubleshooting

**`terraform init` fails with "bucket does not exist"**
```bash
# You forgot to run the bootstrap script first
cd scripts && bash bootstrap-backend.sh
```

**EKS nodes not joining the cluster**
```bash
# Check the node group status
aws eks describe-nodegroup --cluster-name ecommerce-eks-prod --nodegroup-name ecommerce-eks-prod-baseline

# Check node group events
kubectl get events -n kube-system --sort-by='.lastTimestamp'
```

**`terraform apply` fails on `aws_eks_access_entry`**
```bash
# This can fail if the Karpenter node role doesn't exist yet.
# Apply in two steps:
terraform apply -target=module.karpenter
terraform apply
```

**kubectl can't connect**
```bash
# Re-run the kubeconfig command
aws eks update-kubeconfig --region $(aws configure get region) --name ecommerce-eks-prod

# Verify your identity
aws sts get-caller-identity
```

---

## Part of the Larger Project

This repo is one of three that make up the full platform:

| Repo | Purpose |
|---|---|
| **ecommerce-infra** ← *you are here* | Terraform infrastructure + Ansible configuration |
| **ecommerce-app** | Application source code, Dockerfiles, Jenkins CI pipeline |
| **ecommerce-k8s-gitops** | Helm chart, Kustomize overlays, ArgoCD manifests |

Full CI/CD flow:
```
git push to ecommerce-app
    → Jenkins builds Docker images
    → Trivy scans for CVEs
    → Images pushed to ECR (URLs from terraform output ecr_repository_urls)
    → kustomization.yaml updated with new image tags
    → ArgoCD detects change, deploys to EKS
    → kubectl get ingress -n ecommerce-prod  ← your app URL
```

---

## License

MIT
