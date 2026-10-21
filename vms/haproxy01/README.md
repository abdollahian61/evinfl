# haproxy01

IP: `192.168.1.5` — Ubuntu 24.04 — 4 vCPU — RAM 8 GB — OS disk 30 GB.

Data disk: 50 GB, default device `/dev/sdb`, mount `/srv/haproxy`. Verify the real device first; formatting is disabled by default.

## Files

- `install.yml`: per-VM Ansible playbook.
- `vars.yml`: this VM's public settings; keep passwords in `private/secrets.yml`.
- `install.sh`: run this wrapper **on the Ansible controller**, not on this VM.

## Run from the repository root

```bash
bash vms/haproxy01/install.sh
```

For a confirmed empty data disk, add an explicit JSON boolean:

```bash
bash vms/haproxy01/install.sh -e '{"data_disk_allow_format": true}'
```

Read [the complete runbook](../../docs/documentation.md) for prerequisites, execution order, secrets and checks.

Supply `private/haproxy.pem` containing the real certificate chain and key. Test-only self-signed mode is available via `haproxy_allow_self_signed: true`. The second disk stores rotated HAProxy logs.
