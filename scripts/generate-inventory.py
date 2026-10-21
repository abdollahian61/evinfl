#!/usr/bin/env python3
"""Convert Terraform output JSON to Kubespray INI inventory."""
import argparse, ipaddress, json, re
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument("--input",required=True)
p.add_argument("--output",required=True)
a=p.parse_args()
data=json.loads(Path(a.input).read_text())
nodes=data["nodes"]["value"]
if not isinstance(nodes,list) or not nodes:
    raise ValueError("Terraform output nodes must be a nonempty list")
groups={"kube_control_plane":[],"etcd":[],"kube_node":[]}
seen=set()
for n in nodes:
    name=n["name"]
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*",name) or name in seen:
        raise ValueError("Invalid or duplicate node name")
    seen.add(name)
    private=str(ipaddress.ip_address(n["private_ip"]))
    access=str(ipaddress.ip_address(n.get("public_ip") or private))
    entry=f"{name} ansible_host={access} ip={private} access_ip={private}"
    role=n["role"]
    if role=="control-plane":
        groups["kube_control_plane"].append(entry)
        groups["etcd"].append(name)
    elif role=="worker":
        groups["kube_node"].append(entry)
    else:
        raise ValueError("Unknown role: "+str(role))
if not groups["kube_control_plane"] or not groups["kube_node"]:
    raise ValueError("Control plane and worker nodes required")
lines=[]
for group, entries in groups.items():
    lines += [f"[{group}]",*entries,""]
lines += ["[k8s_cluster:children]","kube_control_plane","kube_node",""]
target=Path(a.output)
target.parent.mkdir(parents=True,exist_ok=True)
target.write_text("\n".join(lines))
