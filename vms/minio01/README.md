# minio01

IP: `192.168.1.28` — Ubuntu 24.04 — 4 vCPU — RAM 8 GB — OS disk 30 GB.

Data disk: 100 GB, default device `/dev/sdb`, mount `/srv/minio`. Verify the real device first; formatting is disabled by default.

## Files

- `install.yml`: per-VM Ansible playbook.
- `vars.yml`: this VM's public settings; keep passwords in `private/secrets.yml`.
- `install.sh`: run this wrapper **on the Ansible controller**, not on this VM.

## Run from the repository root

```bash
bash vms/minio01/install.sh
```

For a confirmed empty data disk, add an explicit JSON boolean:

```bash
bash vms/minio01/install.sh -e '{"data_disk_allow_format": true}'
```

Read [the complete runbook](../../docs/documentation.md) for prerequisites, execution order, secrets and checks.

Supply the purchased AIStor license and root credentials. The latest stable binary is downloaded and checksummed only on first install; subsequent runs preserve the installed server version. Bucket and per-backup user setup follows the runbook.
