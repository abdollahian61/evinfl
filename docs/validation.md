# Validation — 2026-10-21

Checked locally, without connecting to user VMs:

- Bash syntax for all shell scripts.
- YAML parsing and consistency between versions.env and Ansible version variables.
- Ansible 12.3.0 / ansible-core 2.19.14 syntax checks: site, addons, agents, Kerio verify, MSSQL verify.
- Official Kubespray v2.32.0 cluster.yml syntax check with this Kubernetes inventory (warnings for unused optional bastion/calico groups only).
- Helm 3.22.0 template with Kubernetes 1.36.4: Cilium 1.20.3 (36 resources), Traefik 42.1.1 (33), NFS CSI 4.13.5 (9), Metrics Server 3.14.0 (9), kube-prometheus-stack 92.11.0 (81), Velero 12.2.1 (26), including CRDs.
- Rendered Traefik Service NodePort 30080 and named Gateway; Prometheus local storage class.

Earlier backup script checks covered missing mount, backup failure, retention only after success and successful 14-day retention using mocked commands.

Not validated against live servers: Arvan routing/security groups/MTU, blank disk preparation, OS package installation, MinIO license activation, runtime health, admission/schema validation against a running API, database connections, or real backup/restore. Follow install-a-to-z.md for acceptance checks. A successful syntax check is not a deployment result.

## cluster.yaml entry point

The root cluster.yaml import was syntax-checked from the project directory with the pinned Kubespray checkout, inventory, roles and library paths. The installation script now uses this same entry point; inspection/check modes exit before retrieving credentials. No managed host was contacted.
