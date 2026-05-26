# ================================================================
# locals.tf — All derived values from AWS data sources.
# Nothing is hardcoded. Everything flows from the AWS account
# and region that Terraform is authenticated against.
# ================================================================
locals {
  # AWS account ID and region — fetched from AWS APIs at apply time
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  # ECR registry base URL — constructed from account + region
  # Example: 123456789012.dkr.ecr.us-east-1.amazonaws.com
  ecr_registry = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com"

  # Full AZ names built from region + suffix letters
  # Example: us-east-1 + ["a","b","c"] = ["us-east-1a","us-east-1b","us-east-1c"]
  availability_zones = [
    for s in var.az_suffixes : "${local.region}${s}"
  ]

  # S3 state bucket name — unique per AWS account, no collision possible
  tfstate_bucket = "ecommerce-tfstate-${local.account_id}"
}
