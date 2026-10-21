#!/usr/bin/env python3
"""Generate Kubespray inventory from Terraform JSON outputs.

Expected: {"nodes":{"value":[{"name":"k8s-master01","role":"control-plane",
"private_ip":"10.0.0.10","public_ip":null},...]}}
"""
import argparse
import ipaddress
import json
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--input", required=True)
p.add_argument("--output", required=True)
args = p.parse_args()
data = json.loads(Path(args.input).read_text())
nodes = data["nodes"]["value"]
groups = {"kube_control_plane": [], "etcd": [], "kube_node": []}
for n in nodes:
    name, role = n["name"], n["role"]
    if not name.replace("-", "").isalnum():
        raise ValueError("Unsafe hostname")
    private = str(ipaddress.ip_address(n["private_ip"]))
    access = str(ipaddress.ip_address(n.get("public_ip") or private))
    line = f"{name} ansible_host={access} ip={private} access_ip={private}"
    if role == "control-plane":
        groups["kube_control_plane"].append(line)
        groups["etcd"].append(name)
    elif role == "worker":
        groups["kube_node"].append(line)
    else:
        raise ValueError(f"Unknown role: {role}")
if not groups["kube_control_plane"] or not groups["kube_node"]:
    raise ValueError("At least one control plane and one worker required")
out = []
for group, entries in groups.items():
    out += [f"[{group}]", *entries, ""]
out += ["[k8s_cluster:children]", "kube_control_plane", "kube_node", ""]
target = Path(args.output)
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text("\n".join(out))
