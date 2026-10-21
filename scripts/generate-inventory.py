#!/usr/bin/env python3
"""Generate Eways Ansible inventories from Terraform JSON output. No live API calls."""
import argparse
import ipaddress
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

K8S = ("k8s-master01", "k8s-worker01", "k8s-worker02", "k8s-worker03")
GROUPS = {
    "k8s_master": ("k8s-master01",),
    "k8s_workers": ("k8s-worker01", "k8s-worker02", "k8s-worker03"),
    "haproxy": ("haproxy01",),
    "nfs": ("nfs01",),
    "minio": ("minio01",),
    "monitoring": ("monitoring01",),
    "clickhouse": ("clickhouse01",),
    "meilisearch": ("meilisearch01",),
    "windows": ("mssql01",),
    "appliances": ("kerio01",),
}
ALL = {n for names in GROUPS.values() for n in names}
# Installed by the owner, not by Terraform/Ansible (see vms/README.md).
MANUAL = {"kerio01", "mssql01"}


def tracked_hosts(path):
    """Read ansible_host values from the tracked services inventory."""
    hosts = {}
    for line in path.read_text().splitlines():
        m = re.match(r"^([A-Za-z0-9-]+)\s+.*\bansible_host=(\S+)", line)
        if m:
            hosts[m.group(1)] = m.group(2)
    return hosts


def planned_ips(manual_hosts):
    """Planned private IPs: vms/<name>/vars.yml, or the tracked inventory for manual VMs."""
    planned = {}
    for name in ALL:
        vars_file = ROOT / "vms" / name / "vars.yml"
        m = re.search(r"^vm_private_ip:\s*(\S+)", vars_file.read_text(), re.M) if vars_file.exists() else None
        if m:
            planned[name] = m.group(1)
        elif name in manual_hosts:
            planned[name] = manual_hosts[name]
    return planned

def private_ip(addresses):
    ips = set()
    for raw in addresses:
        # Provider docs specify a list of strings. Reject unexpected shapes.
        if not isinstance(raw, str):
            raise ValueError(f"Unexpected address format: {raw!r}")
        try:
            ip = ipaddress.ip_address(raw)
        except ValueError:
            raise ValueError(f"Address is not a plain IP: {raw!r}") from None
        if isinstance(ip, ipaddress.IPv4Address) and ip in ipaddress.ip_network("10.0.0.0/8") or (
            isinstance(ip, ipaddress.IPv4Address) and
            (ip in ipaddress.ip_network("172.16.0.0/12") or ip in ipaddress.ip_network("192.168.0.0/16"))
        ):
            ips.add(str(ip))
    if len(ips) != 1:
        raise ValueError(f"Expected exactly one private IPv4, got {sorted(ips)}")
    return next(iter(ips))

def render(nodes, manual_hosts=None, planned=None):
    manual_hosts = manual_hosts or {}
    addresses = {name: private_ip(data["addresses"]) for name, data in nodes.items()}
    # Manually installed VMs may be absent from Terraform; take them from the tracked inventory.
    for name in MANUAL - set(nodes):
        if name in manual_hosts:
            addresses[name] = str(ipaddress.ip_address(manual_hosts[name]))
    if set(addresses) != ALL:
        raise ValueError(f"Machine mismatch; missing={sorted(ALL-set(addresses))}; extra={sorted(set(addresses)-ALL)}")
    if len(set(addresses.values())) != len(addresses):
        raise ValueError("Duplicate private IP addresses")
    if planned is not None:
        # Group vars, HAProxy, NFS exports and site.env pin these addresses.
        wrong = {n: (addresses[n], planned[n]) for n in sorted(addresses) if n in planned and addresses[n] != planned[n]}
        if wrong:
            details = ", ".join(f"{n}: got {got}, planned {want}" for n, (got, want) in wrong.items())
            raise ValueError(f"Private IPs differ from the planned addresses used across the repository ({details}). "
                             "Fix the Arvan network assignment, or update every pinned address, then rerun with --allow-ip-change.")
    k8s = ["[kube_control_plane]", f"k8s-master01 ansible_host={addresses['k8s-master01']} ip={addresses['k8s-master01']} access_ip={addresses['k8s-master01']}", "", "[etcd]", "k8s-master01", "", "[kube_node]"]
    for name in K8S[1:]:
        ip = addresses[name]
        k8s.append(f"{name} ansible_host={ip} ip={ip} access_ip={ip}")
    k8s += ["", "[k8s_cluster:children]", "kube_control_plane", "kube_node", ""]
    ansible = []
    for group, names in GROUPS.items():
        ansible.append(f"[{group}]")
        for name in names:
            extra = " ansible_connection=winrm ansible_port=5986 ansible_winrm_transport=ntlm ansible_winrm_server_cert_validation=validate" if group == "windows" else ""
            ansible.append(f"{name} ansible_host={addresses[name]}{extra}")
        ansible.append("")
    ansible += ["[linux:children]", "k8s_master", "k8s_workers", "haproxy", "nfs", "minio", "monitoring", "clickhouse", "meilisearch", "", "[linux:vars]", "ansible_python_interpreter=/usr/bin/python3", ""]
    return "\n".join(k8s), "\n".join(ansible)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True, type=Path, help="terraform output -json file")
    p.add_argument("--out", type=Path, default=Path("generated-inventory"))
    p.add_argument("--manual-inventory", type=Path, default=ROOT / "ansible" / "inventory.ini",
                   help="tracked inventory that supplies kerio01/mssql01 when Terraform does not manage them")
    p.add_argument("--allow-ip-change", action="store_true",
                   help="accept addresses that differ from vms/*/vars.yml (only after updating every pinned address)")
    a = p.parse_args()
    data = json.loads(a.input.read_text())
    nodes = data["inventory_nodes"]["value"]
    manual_hosts = {n: ip for n, ip in tracked_hosts(a.manual_inventory).items() if n in MANUAL}
    planned = None if a.allow_ip_change else planned_ips(manual_hosts)
    k8s, ansible = render(nodes, manual_hosts, planned)
    a.out.mkdir(parents=True, exist_ok=True)
    (a.out / "hosts.ini").write_text(k8s)
    (a.out / "ansible.ini").write_text(ansible)
    print(f"Generated {a.out / 'hosts.ini'} and {a.out / 'ansible.ini'}")

if __name__ == "__main__":
    main()
