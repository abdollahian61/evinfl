# Infrastructure Specification (Draft)

## Virtual Machines

VM names are proposed. Disk capacities are in GB. The first disk is the OS disk; the second is a separate data disk.

| VM | Private IP | OS / Product | vCPU | RAM (GB) | OS Disk | Second Disk | Role |
|---|---|---|---:|---:|---:|---:|---|
| kerio01 | 192.168.1.4 | Kerio Control | 4 | 8 | 30 | — | VPN and outbound NAT gateway |
| haproxy01 | 192.168.1.5 | Ubuntu 24.04 LTS | 4 | 8 | 30 | 50 | Public HTTPS entry point |
| k8s-master01 | 192.168.1.10 | Ubuntu 24.04 LTS | 4 | 8 | 30 | — | Control plane and etcd |
| k8s-worker01 | 192.168.1.21 | Ubuntu 24.04 LTS | 6 | 12 | 30 | 50 | Worker |
| k8s-worker02 | 192.168.1.22 | Ubuntu 24.04 LTS | 6 | 12 | 30 | 50 | Worker |
| k8s-worker03 | 192.168.1.23 | Ubuntu 24.04 LTS | 6 | 12 | 30 | 50 | Worker |
| nfs01 | 192.168.1.24 | Ubuntu 24.04 LTS | 4 | 8 | 30 | 100 | Kubernetes PV/PVC storage |
| minio01 | 192.168.1.28 | Ubuntu 24.04 LTS / MinIO AIStor | 4 | 8 | 30 | 100 | Single-node backup repository |
| monitoring01 | 192.168.1.30 | Ubuntu 24.04 LTS | 4 | 8 | 30 | 100 | Zabbix, Grafana, DevOps management |
| mssql01 | 192.168.1.40 | Windows Server 2025 / SQL Server 2019 Standard | 8 | 16 | 100 | 500 | Database; installed by project owner |
| clickhouse01 | 192.168.1.42 | Ubuntu 24.04 LTS | 4 | 8 | 30 | 100 | Standalone ClickHouse |
| meilisearch01 | 192.168.1.43 | Ubuntu 24.04 LTS | 4 | 8 | 30 | 100 | Standalone Meilisearch |

On workers, disk `sdb` is intended for containerd and kubelet data. Verify actual device names, UUIDs and mounts before running disk commands.

## Network and Access

- Only Kerio and HAProxy have public IPs; actual addresses are not yet assigned.
- Kerio VPN supports up to 10 simultaneous users with direct administrative access to private VM addresses. Linux uses SSH; Windows management will be defined separately.
- Private VMs use Kerio at `192.168.1.4` for outbound internet NAT.
- Verify outbound connectivity and return routing separately for publicly addressed VMs.
- Restrict NFS exports to required Kubernetes nodes. Other VMs do not use the share; administrative SSH access is independent.
- Subnet mask, VPN range, DNS and NTP remain undefined. Do not assume a `/24` subnet from the addresses.
- Confirm ArvanCloud support for Kerio images, NICs, VM-based routing, port-security/anti-spoofing and return routes before deployment.

## Kubernetes

| Item | Current Decision |
|---|---|
| Target version | Kubernetes 1.36.4; other pinned versions in `config/versions.env` |
| Installer | Kubespray; compatibility baseline v2.32.0 |
| Runtime | containerd 2.3.5, per Kubespray bundle |
| CNI | Cilium via Helm, chart version 1.20.3 |
| kube-proxy | Not installed initially; Cilium `kubeProxyReplacement` enabled |
| Pod CIDR | `10.244.0.0/16` |
| Service CIDR | `10.96.0.0/16` |
| Web ingress | Gateway API with Traefik controller |
| Proposed HTTP NodePort | `30080` |
| Application storage | NFS at `192.168.1.24` with suitable provisioner/CSI |
| In-cluster monitoring | Metrics Server and Prometheus Stack |

Deployment order:

1. Prepare OS, networking and disks.
2. Install Kubernetes with Kubespray, leaving CNI to Helm and omitting kube-proxy.
3. Install Cilium; verify node readiness, DNS, Services and NodePort.
4. Install Gateway API CRDs, Traefik and routes; connect HAProxy to three workers.
5. Install NFS driver/provisioner and StorageClass.
6. Install Metrics Server, Prometheus Stack and Velero.

Validate exact Kubespray parameters and CNI-dependent steps against the selected tag. This design does not install a default CNI and replace it later. Specify the private Kubernetes API endpoint, `k8sServiceHost` and `k8sServicePort` for kube-proxy-free Cilium.

Web request path: client HTTPS -> HAProxy -> HTTP NodePort on three workers -> Traefik Gateway API -> workload. Preserve the original Host header. Restrict trusted `X-Forwarded-*` sources in Traefik to the HAProxy private IP.

## Monitoring and Management

- Run Zabbix and Grafana on `monitoring01` for asset monitoring.
- Install kubectl, Helm, Ansible and Kubespray management tools on the same host.
- Do not run the CI/CD Runner on this host.
- Prometheus Stack runs in-cluster with a Local PV on Worker01, seven-day retention and a 6 GB cap. External Grafana connects via private NodePort 30900.

## Backups

- Deploy single-node MinIO AIStor using the latest stable release at installation time and record the exact version.
- Commercial licensing and official support are requested but not yet purchased or activated.
- Store Kubernetes resource backups via Velero in a dedicated bucket. Back up the full NFS data directory using Restic to bucket `nfs-backup`.
- Run daily backups with 14-day retention.
- Independent database backups are outside this phase's scope.
- The initial 100 GB MinIO allocation must be validated against actual data size and change rate.
- Define separate etcd/control-plane backup and restore testing. Velero resource backups alone do not constitute a complete control-plane machine backup.

## Open Decisions

- Public IPs, subnet mask, VPN range, DNS, NTP and domains.
- Final ArvanCloud network configuration, firewall rules and return routes.
- Verify pinned `config/versions.env` versions and compatibility in the real environment.
- Validate automatic MTU discovery and VXLAN on ArvanCloud; see `config/helm/cilium.yaml`.
- Confirm actual `sdb` device before formatting; HAProxy's second disk is reserved for logs.
- Validate NFS CSI, metrics Local PV and Grafana integration per deployment guide.
- Activate MinIO licensing, create keys and test restores; schedules are defined in the deployment guide.
- Review single points of failure and HA upgrade path; do not change VM counts without owner approval.
- Produce Visio output after explicit final approval; see the [deployment guide](install-a-to-z.md).

## Technical References

- [Kubespray v2.32.0](https://github.com/kubernetes-sigs/kubespray/releases/tag/v2.32.0)
- [Cilium Kubernetes compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)
- [Cilium kube-proxy replacement](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
- [Traefik Gateway API](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/gateway-api/)
- [MinIO AIStor licenses](https://docs.min.io/aistor/operations/licenses/)
