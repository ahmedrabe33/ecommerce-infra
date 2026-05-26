# ================================================================
# Remote State Backend
#
# The S3 bucket and DynamoDB table are created by the bootstrap
# script BEFORE you run terraform init.
#
# Run first:
#   cd scripts && bash bootstrap-backend.sh
#
# That script generates backend.hcl with your real values.
# Then run:
#   terraform init -backend-config=backend.hcl
# ================================================================
terraform {
  backend "s3" {
    # Values injected via: terraform init -backend-config=backend.hcl
    # See scripts/bootstrap-backend.sh
  }
}
