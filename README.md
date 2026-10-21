# EvinFL Infrastructure

Infrastructure automation and deployment documentation for ArvanCloud.

## Guides

- [End-to-end deployment guide](docs/install-a-to-z.md)
- [Kubespray, Helm, and Cilium installation](docs/kubespray-then-cilium.md)
- [Infrastructure specifications](docs/infrastructure.md)
- [Per-VM installation instructions](vms/README.md)
- [HAProxy operations](docs/haproxy.md)
- [NFS backup and recovery](docs/nfs-backup.md)

## Architecture

- One Kubernetes control plane and three workers deployed with Kubespray.
- Cilium installed using Helm with kube-proxy replacement.
- Traefik Gateway API behind HAProxy.
- Kerio provides VPN and outbound NAT for private VMs.
- Zabbix and Grafana run on the management VM; Prometheus runs inside Kubernetes.
- Velero and Restic back up Kubernetes resources and NFS data to MinIO.

## Configuration

- [Kubespray entrypoint](cluster.yaml)
- [Version pins](config/versions.env)
- [Ansible inventory](ansible/inventory.ini)
- [Helm values](config/helm/)

## Security and deployment status

Do not commit credentials, private keys, admin kubeconfigs, TLS secrets, or licenses. Infrastructure definitions and installation scripts require validation in the target ArvanCloud environment before production execution.

The GitLab CI/CD workflow is designed for a self-hosted runner after the GitHub repository is transferred to GitLab. Provisioning and destructive operations must remain manually controlled.
