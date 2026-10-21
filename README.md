# EvinFL Infrastructure

Infrastructure automation, configuration, and operational runbooks for the EvinFL deployment on ArvanCloud.

## Documentation

| Resource | Description |
|---|---|
| [Deployment guide](docs/install-a-to-z.md) | End-to-end infrastructure installation and verification |
| [Kubernetes deployment](docs/kubespray-then-cilium.md) | Kubespray cluster installation, followed by Helm and Cilium |
| [Infrastructure inventory](docs/infrastructure.md) | Planned virtual machines, networking, and open decisions |
| [Per-VM instructions](vms/README.md) | Installation scripts, Ansible playbooks, and variables |
| [Kubespray entrypoint](cluster.yaml) | Cluster installation playbook |
| [Version pins](config/versions.env) | Kubernetes and Helm component versions |
| [HAProxy operations](docs/haproxy.md) | TLS configuration and service verification |
| [NFS backup](docs/nfs-backup.md) | Restic backup to MinIO and recovery procedures |

## Architecture

- One Kubernetes control-plane node and three worker nodes, deployed with Kubespray.
- Cilium installed with Helm, with kube-proxy replacement enabled.
- Traefik Gateway API for HTTP routing, behind a public HAProxy endpoint.
- Only Kerio and HAProxy have public IP addresses; private hosts use Kerio for outbound NAT.
- Zabbix and Grafana on the management VM; Prometheus inside Kubernetes.
- Velero for Kubernetes resources and Restic for NFS data, targeting MinIO with a planned 14-day retention policy.

## Deployment status

Configuration is not proof of successful deployment. ArvanCloud provisioning, networking, Kubernetes installation, and backups require validation in the target environment. Never commit production credentials, SSH keys, admin kubeconfigs, certificates, or licenses.

## CI/CD

The GitLab pipeline is intended to run on a self-hosted GitLab Runner after the repository is imported from GitHub. Provisioning and destructive operations must be explicitly approved and tested before production use.
