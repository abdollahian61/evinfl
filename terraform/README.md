# Arvan Terraform and generated Ansible inventories

This is a **safe, untested scaffold**, not a production-ready deployment. The official Arvan Terraform provider 0.6.4 is archived. Its documented `arvan_iaas_abrak.addresses` attribute is a list of IP strings. Confirm current API compatibility, valid flavor IDs, images, networks, and security groups before enabling VMs.

## Source of truth

The 12-machine sizing and desired roles are in [../docs/infrastructure.md](../docs/infrastructure.md). Provider `flavor` requires an Arvan plan ID, not CPU/RAM values. All example machines are deliberately disabled. Windows and Kerio images, licensing, public connectivity, secondary disks, and NAT are **not provisioned by this scaffold**. Do not assume the plan is complete merely because Terraform succeeds.

## Steps

1. Copy `terraform.tfvars.example` to `terraform.tfvars`. Fill region, private network name, exact approved flavor IDs and image names, and only enable machines after verification. Set `TF_VAR_arvan_api_key` from a secret manager. Never commit credentials or state.
2. From `terraform/`, run `terraform init`, `terraform validate`, `terraform plan`, then review and run `terraform apply`. Do not apply the placeholder example.
3. Run `terraform output -json > ../terraform-output.json`. Treat this file as sensitive operational data.
4. From repository root, run `python3 scripts/generate-inventory.py --input terraform-output.json --out generated-inventory`.
5. Inspect `generated-inventory/hosts.ini` (Kubespray) and `generated-inventory/ansible.ini` (services). Run Kubespray with `-i generated-inventory/hosts.ini`. Do not overwrite tracked inventories automatically.

The generator fails closed if any of the 12 machines is missing, has multiple private addresses, no private address, an unexpected address format, or duplicate IPs. Arvan's `addresses` may not distinguish interfaces; for multi-NIC hosts, replace this selection logic with an explicit private-network attachment lookup before production use.

Terraform state must use a protected remote backend with locking and encryption for team usage. GitHub Actions must not automatically run `apply` on pull requests.
