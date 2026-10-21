# GitLab deployment pipeline

This pipeline is intended for a self-hosted GitLab project mirrored or manually pushed from GitHub.

## Runner requirements
Register a dedicated runner with tag `evinfl-infra`. It must have network access to the Arvan API and private VM addresses through a secure management network/VPN. Never run this runner on nodes it provisions.

## CI variables
- `ARVAN_API_KEY` (masked, protected): provider credential; configure the provider using the documented provider-specific environment variable.
- `SSH_PRIVATE_KEY` (file, protected): Ansible key, loaded only in deployment jobs.
- `KUBECONFIG` (file, protected): admin kubeconfig for cluster add-ons.
- `TF_STATE_ADDRESS`, `TF_HTTP_USERNAME`, `TF_HTTP_PASSWORD`: remote HTTP backend credentials and address (or configure GitLab-managed Terraform state).
- `KUBESPRAY_DIR`: checked-out, pinned compatible Kubespray source path on the runner.
- `ANSIBLE_USER`: remote SSH username.

## Operational safety
- Validate before running any deploy job.
- Terraform plan is automatic, apply is manual and protected.
- Inventory is generated from the applied Terraform output; do not hardcode cloud-generated addresses.
- Kubespray initial install and scale are different operations. Use Kubespray scale.yml for added workers.
- Kubernetes add-ons require a valid kubeconfig and a working CNI.
- Never commit state, private keys, kubeconfig, or passwords.
- This is a CI framework, not a tested production deployment. Confirm provider schema, networking, versions and routes before apply.
