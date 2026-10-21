# monitoring01

IP: `192.168.1.30` — Ubuntu 24.04 — 4 vCPU — RAM 8 GB — OS disk 30 GB.

Data disk: 100 GB, default device `/dev/sdb`, mount `/srv/monitoring`. Verify the real device first; formatting is disabled by default.

## Files

- `install.yml`: per-VM Ansible playbook.
- `vars.yml`: this VM's public settings; keep passwords in `private/secrets.yml`.
- `install.sh`: run this wrapper **on the Ansible controller**, not on this VM.

## Run from the repository root

```bash
bash vms/monitoring01/install.sh
```

For a confirmed empty data disk, add an explicit JSON boolean:

```bash
bash vms/monitoring01/install.sh -e '{"data_disk_allow_format": true}'
```

Read [the complete runbook](../../docs/documentation.md) for prerequisites, execution order, secrets and checks.

Installs PostgreSQL, Zabbix 7.4, Grafana and the Zabbix datasource plugin. Prometheus remains in Kubernetes. PostgreSQL/Grafana data use the second disk. No CI/CD Runner is installed.
