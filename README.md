# EvinFL Infrastructure

Infrastructure as Code and operational documentation for the EvinFL environment on ArvanCloud.

## Deployment documentation

| Document | Purpose |
|---|---|
| [Terraform provisioning](terraform/README.md) | ArvanCloud Terraform scaffold and dynamic inventory generation |
| [End-to-end installation guide](docs/install-a-to-z.md) | Infrastructure setup, deployment, and validation |
| [Kubespray and Cilium](docs/kubespray-then-cilium.md) | Kubernetes installation followed by Helm and Cilium |
| [Infrastructure specifications](docs/infrastructure.md) | VM sizing, private networking, and outstanding decisions |
| [Per-VM instructions](vms/README.md) | Individual installation scripts, playbooks, and variables |
| [Kubespray playbook](cluster.yaml) | Kubernetes cluster installation entrypoint |
| [Pinned versions](config/versions.env) | Component and chart versions |
| [HAProxy operations](docs/haproxy.md) | HTTPS ingress and service configuration |
| [NFS backup](docs/nfs-backup.md) | Restic backups to MinIO and recovery |

## Architecture

- One Kubernetes control-plane node and three worker nodes, installed with Kubespray.
- Cilium deployed with Helm and kube-proxy replacement.
- Traefik Gateway API behind HAProxy for application ingress.
- Kerio provides VPN access and outbound NAT for private VMs.
- Zabbix and Grafana on the management host; Prometheus inside Kubernetes.
- Velero and Restic backups to MinIO with a planned 14-day retention period.

## Terraform and inventory

Terraform definitions live in `terraform/`. After a reviewed deployment, export Terraform outputs and generate Ansible and Kubespray inventories with `scripts/generate-inventory.py`. The ArvanCloud provider integration and live deployment have not been verified. Do not run placeholder Terraform plans in production.

## Security

Keep API keys, SSH private keys, admin kubeconfigs, TLS credentials, licenses, and Terraform state outside Git. Review all infrastructure changes before applying them.
