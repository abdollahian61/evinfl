# GitLab-managed Terraform state (HTTP backend with locking).
# CI passes address, lock and credentials via -backend-config; see .gitlab/ci/README.md.
# For local work without remote state, run: terraform init -backend=false
terraform {
  backend "http" {}
}
