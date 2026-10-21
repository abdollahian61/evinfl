# k8s-worker02

IP: `192.168.1.22` — Ubuntu 24.04 — 6 vCPU — RAM 12 GB — OS disk 30 GB.

Data disk: 50 GB, default device `/dev/sdb`, mount `/srv/k8s-data`. Verify the real device first; formatting is disabled by default.

## Files

- `install.yml`: per-VM Ansible playbook.
- `vars.yml`: this VM's public settings; keep passwords in `private/secrets.yml`.
- `install.sh`: run this wrapper **on the Ansible controller**, not on this VM.

## Run from the repository root

```bash
bash vms/k8s-worker02/install.sh
```

For a confirmed empty data disk, add an explicit JSON boolean:

```bash
bash vms/k8s-worker02/install.sh -e '{"data_disk_allow_format": true}'
```

Read [the complete runbook](../../docs/documentation.md) for prerequisites, execution order, secrets and checks.

This playbook prepares the node. Kubernetes installation/join is performed by the cluster-wide Kubespray playbook; do not install kubeadm or another CNI independently.
