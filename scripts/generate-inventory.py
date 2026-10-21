#!/usr/bin/env python3
"""Generate Eways Ansible inventories from Terraform JSON output. No live API calls."""
import argparse
import ipaddress
import json
from pathlib import Path

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

def render(nodes):
    if set(nodes) != ALL:
        raise ValueError(f"Machine mismatch; missing={sorted(ALL-set(nodes))}; extra={sorted(set(nodes)-ALL)}")
    addresses = {name: private_ip(data["addresses"]) for name, data in nodes.items()}
    if len(set(addresses.values())) != len(addresses):
        raise ValueError("Duplicate private IP addresses")
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
    a = p.parse_args()
    data = json.loads(a.input.read_text())
    nodes = data["inventory_nodes"]["value"]
    k8s, ansible = render(nodes)
    a.out.mkdir(parents=True, exist_ok=True)
    (a.out / "hosts.ini").write_text(k8s)
    (a.out / "ansible.ini").write_text(ansible)
    print(f"Generated {a.out / 'hosts.ini'} and {a.out / 'ansible.ini'}")

if __name__ == "__main__":
    main()
