# Step-by-Step Deployment: Kubespray → Helm → Cilium

This procedure targets a fresh cluster with one control-plane node and three workers running Ubuntu 24.04. Install Kubernetes, containerd, etcd, and CoreDNS resources first; install Helm on the management VM next; then install Cilium through Helm. Traefik, NFS, monitoring, and backup are not installed at this stage. Run these steps as `devops` on `monitoring01`, not separately on all four nodes.

| Role | Hostname | Private IP |
|---|---|---|
| Master + etcd | k8s-master01 | 192.168.1.10 |
| Worker | k8s-worker01 | 192.168.1.21 |
| Worker | k8s-worker02 | 192.168.1.22 |
| Worker | k8s-worker03 | 192.168.1.23 |

Pinned versions: Kubespray `v2.32.0`, Kubernetes `1.36.4`, Helm `3.22.0`, and Cilium chart `1.20.3`. Versions are defined in [versions.env](../config/versions.env); do not use `latest` for reproducible deployment. Cilium 1.20 officially supports Kubernetes 1.36.

## 1. Access and Prerequisites

- Each VM requires a fresh Ubuntu 24.04 installation, a unique hostname, and a static private IP. The SSH user must have a valid key and passwordless `sudo`. Verify SSH host fingerprints from the provider console before accepting them.
- The VMs must not already belong to an RKE2, K3s, or other cluster. This guide is not a migration or CNI replacement procedure for existing nodes.
- All nodes need outbound access through Kerio to package repositories and container registries, working host DNS, and synchronized clocks. The standard Ubuntu 24.04 kernel is suitable for this baseline.
- Pod CIDR is `10.244.0.0/16` and Service CIDR is `10.96.0.0/16`. Confirm neither overlaps the LAN or VPN. Do not infer the VM subnet mask from the listed IP addresses.

Allow these private connections through ArvanCloud and host firewalls. Do not expose management ports to the public internet.

| Connection | Port |
|---|---|
| Management/VPN to nodes | TCP 22 |
| Management and all four nodes to master | TCP 6443 |
| Master to node kubelets | TCP 10250 |
| etcd on master | TCP 2379/2380, restricted to necessary private peers |
| Inter-node VXLAN | UDP 8472 |
| Inter-node health | TCP 4240 and ICMP |
| Cluster nodes for Hubble | TCP 4244 |
| Node egress | Configured DNS, NTP, and HTTPS to registries/repositories via Kerio |

This is an infrastructure connectivity matrix, not a complete Pod/Service policy. Do not open public NodePorts yet. These files do not modify routes, NICs, ArvanCloud port security, or netplan. If UFW is enabled, inspect Pod forwarding and node traffic rules rather than disabling firewall protection indiscriminately.

On the management host:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/abdollahian61/evinfl.git
cd evinfl
bash scripts/bootstrap-controller.sh --ansible-only
editor private/site.env
source private/site.env
export KUBESPRAY_DIR
export PATH="$VENV_DIR/bin:$PWD/.tools/bin:$PATH"
export ANSIBLE_CONFIG="$KUBESPRAY_DIR/ansible.cfg"
export ANSIBLE_ROLES_PATH="$KUBESPRAY_DIR/roles"
export ANSIBLE_LIBRARY="$KUBESPRAY_DIR/library"
export ANSIBLE_HOST_KEY_CHECKING=True
export ANSIBLE_SSH_ARGS='-o ControlMaster=auto -o ControlPersist=60s -o ConnectionAttempts=10'
```

For an existing checkout, inspect local changes and run `git pull --ff-only`; do not clone again. Set the real `SSH_USER` and `SSH_KEY` in `site.env`. The `--ansible-only` mode installs controller prerequisites and pinned Ansible/Kubespray, but not Helm or kubectl. MinIO and database secrets are unnecessary for this stage. Re-source the environment and repeat the exports in new terminals.

To place worker containerd/kubelet data on the second 50 GB disk, run the [four-VM preparation playbooks](../vms/README.md) before deploying Kubernetes. Confirm `/dev/sdb` is empty with `lsblk -f`. Formatting requires the explicit `-e data_disk_allow_format=true` flag. Otherwise Kubespray uses the standard `/var/lib/containerd` location on the OS disk; it will not migrate data to sdb automatically.

## 2. Minimal Inventory

Edit only [inventory/minimal/hosts.ini](../inventory/minimal/hosts.ini):

```ini
[kube_control_plane]
k8s-master01 ansible_host=192.168.1.10 ip=192.168.1.10 access_ip=192.168.1.10

[etcd]
k8s-master01

[kube_node]
k8s-worker01 ansible_host=192.168.1.21 ip=192.168.1.21 access_ip=192.168.1.21
k8s-worker02 ansible_host=192.168.1.22 ip=192.168.1.22 access_ip=192.168.1.22
k8s-worker03 ansible_host=192.168.1.23 ip=192.168.1.23 access_ip=192.168.1.23

[k8s_cluster:children]
kube_control_plane
kube_node
```

Settings load automatically from the adjacent [group_vars/k8s_cluster.yml](../inventory/minimal/group_vars/k8s_cluster.yml). Key settings:

```yaml
kube_network_plugin: cni
kube_proxy_remove: true
helm_enabled: false
kubelet_csr_approver_enabled: false
enable_nodelocaldns: false
resolvconf_mode: none
```

In this Kubespray version, `cni` copies generic CNI binaries but does not establish Pod networking. `kube_proxy_remove` prevents kube-proxy installation. Disabling Helm and the CSR approver keeps them out of stage one. Host DNS remains intact for pulling Cilium images. Use `inventory/minimal/hosts.ini`; `inventory/hosts.ini` is the earlier, more extensive profile.

If the master IP changes, update the inventory plus `kube_apiserver_bind_address`, `supplementary_addresses_in_ssl_keys` in group_vars, and `k8sServiceHost` in Cilium values.

Verify SSH, Python, and sudo:

```bash
ansible -i inventory/minimal/hosts.ini k8s_cluster \
  -u "$SSH_USER" --private-key "$SSH_KEY" -m ansible.builtin.ping
ansible -i inventory/minimal/hosts.ini k8s_cluster \
  -u "$SSH_USER" --private-key "$SSH_KEY" -b -m ansible.builtin.command -a 'id -u'
```

All four nodes must return `pong` and then `0`. Resolve DNS, SSH, sudo, or download failures before proceeding.

## 3. Deploy Kubernetes with cluster.yaml

The root [cluster.yaml](../cluster.yaml) imports the official Kubespray playbook from the pinned checkout. Check syntax first:

```bash
ansible-playbook -i inventory/minimal/hosts.ini \
  -u "$SSH_USER" --private-key "$SSH_KEY" -b \
  cluster.yaml --syntax-check
```

Deploy:

```bash
ansible-playbook -i inventory/minimal/hosts.ini \
  -u "$SSH_USER" --private-key "$SSH_KEY" -b \
  cluster.yaml
```

Expect `failed=0` and `unreachable=0`. If downloads fail, fix the cause and rerun the command; cluster reset is not the first troubleshooting step. Successful installation writes kubectl and kubeconfig artifacts to `inventory/minimal/artifacts/`. Controller and node architectures must match for this kubectl retrieval approach; the planned VMs use amd64.

```bash
mkdir -p .tools/bin private
chmod 700 private
install -m 755 inventory/minimal/artifacts/kubectl .tools/bin/kubectl
install -m 600 inventory/minimal/artifacts/admin.conf private/admin.conf
export KUBECONFIG="$PWD/private/admin.conf"
kubectl get --raw=/readyz
kubectl get nodes -o wide
kubectl -n kube-system get pods,daemonsets
```

The API should return `ok`. Before Cilium, `NotReady` nodes and `Pending` CoreDNS are expected; API/etcd static Pods do not require Pod networking. No Calico, Flannel, Cilium, or kube-proxy DaemonSet should exist. Never commit artifacts or private kubeconfig files. If nodes are already Ready or another CNI exists, investigate before installing Cilium.

### Initial Kubelet Serving Certificate Approval

This profile requires kubelet serving certificates signed by the cluster CA; no automatic approver is installed. Inspect the four nodes' initial requests before using later `exec` or `logs` commands:

```bash
kubectl get csr
kubectl describe csr REPLACE_WITH_CSR_NAME
kubectl get csr REPLACE_WITH_CSR_NAME -o jsonpath='{.spec.request}' \
  | base64 --decode | openssl req -noout -text
```

Replace the placeholder with the actual request name. Approve only requests with signer `kubernetes.io/kubelet-serving`, a `system:node:NAME` identity belonging to one of your four nodes, matching CN/O, and valid node SANs/IPs. Approve each verified request individually:

```bash
kubectl certificate approve REPLACE_WITH_CSR_NAME
kubectl get csr
```

Status should become `Approved,Issued`. Never approve all CSRs blindly. If none exist, inspect kubelet and CSR state. Certificate approval does not make nodes Ready; Cilium is still required. Future renewals also require review or a suitably restricted approver.

## 4. Install Helm

On the management host only:

```bash
bash scripts/install-helm.sh
export PATH="$PWD/.tools/bin:$PATH"
helm version --short
helm list -A
```

The script downloads the pinned Helm binary from the official source, verifies its checksum, and installs it at `.tools/bin/helm`. Helm is a client, not a separate service on each worker or inside the cluster. Run `helm list -A` before Cilium even if Pod networking is not yet ready.

## 5. Cilium Settings for This Architecture

Editable values: [config/helm/cilium.yaml](../config/helm/cilium.yaml). This is a baseline for a small cluster on a private cloud network. Optimal memory and MTU depend on actual load and networking.

| Setting | Value / Reason |
|---|---|
| kubeProxyReplacement | Enabled; kube-proxy is absent from the outset |
| k8sServiceHost / Port | `192.168.1.10:6443`; direct API bootstrap |
| IPAM | Kubernetes; node-specific subnets from configured Pod CIDR |
| Routing | VXLAN; no per-node Pod CIDR routes required in ArvanCloud |
| MTU | Auto-detected; test large packets after deployment |
| Masquerade | eBPF, then internet egress through existing Kerio gateway |
| LoadBalancer mode | SNAT; no DSR return-path design required |
| Operator | Two replicas, chart-default anti-affinity and PDB maxUnavailable=1 |
| Resources | Explicit requests and initial memory limits; no CPU limit |
| Hubble | Relay and UI enabled as private services; access through port-forward |
| Cilium Gateway/Ingress | Disabled; Traefik will manage Gateway API later |
| Images | Retain default image digests from the pinned chart |

Initial memory limits are 1 GiB for agents and 512 MiB for operators. Monitor OOMs, restarts, endpoint counts, and policies, then tune under load. Two operators do not protect against a single master/etcd failure. VXLAN is not encryption. WireGuard and host firewall are not enabled in this baseline without testing routing, MTU, and requirements. Prometheus ServiceMonitor is disabled until its CRDs are installed.

Install using Helm:

```bash
source config/versions.env
helm repo add cilium https://helm.cilium.io/
helm repo update cilium
helm template cilium cilium/cilium \
  --version "$CILIUM_CHART_VERSION" --namespace kube-system \
  -f config/helm/cilium.yaml > /tmp/evinfl-cilium-rendered.yaml
helm upgrade --install cilium cilium/cilium \
  --version "$CILIUM_CHART_VERSION" --namespace kube-system \
  -f config/helm/cilium.yaml --wait --timeout 15m
```

`helm template` checks rendering, not actual networking or admission. This installation is for the minimal profile; `install-addons.sh all` deploys later components and is not required here.

## 6. Verify Node Readiness

```bash
kubectl -n kube-system rollout status daemonset/cilium --timeout=600s
kubectl -n kube-system rollout status deployment/cilium-operator --timeout=300s
kubectl wait --for=condition=Ready nodes --all --timeout=600s
kubectl -n kube-system rollout status deployment/coredns --timeout=300s
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide
kubectl -n kube-system exec daemonset/cilium -- cilium-dbg status --verbose
kubectl -n kube-system exec daemonset/cilium -- cilium-health status --verbose
```

All four nodes should be Ready with an agent on each. The two operators should run on different nodes; kube-proxy replacement must be enabled. The `exec` commands inspect one agent; check all agents with:

```bash
for pod in $(kubectl -n kube-system get pods -l k8s-app=cilium -o name); do
  kubectl -n kube-system exec "$pod" -- cilium-dbg status --verbose || break
done
```

## 7. Test Pod, Service, and DNS Connectivity

```bash
kubectl apply -f manifests/cilium-smoke.yaml
kubectl -n cilium-smoke rollout status daemonset/echo --timeout=300s
kubectl -n cilium-smoke rollout status deployment/client --timeout=300s
kubectl -n cilium-smoke get pods -o wide
kubectl -n cilium-smoke exec deployment/client -- nslookup kubernetes.default.svc.cluster.local
kubectl -n cilium-smoke exec deployment/client -- wget -qO- http://echo:8080/
```

Expect three echo Pods on the workers and one client. HTTP responses identify the serving Pod. Test direct Pod IP access, including across nodes:

```bash
for pod_ip in $(kubectl -n cilium-smoke get pods -l app=cilium-smoke-echo -o jsonpath='{.items[*].status.podIP}'); do
  kubectl -n cilium-smoke exec deployment/client -- wget -T 5 -qO- "http://$pod_ip:8080/" || break
done
```

All three IPs must respond. If Pod internet egress is required, use a trusted image with wget/curl to test HTTPS to an approved destination. The BusyBox smoke-test image is intended for internal HTTP; its CA store and HTTPS behavior are not independent proof of network readiness. This smoke test does not establish performance, MTU, or all NetworkPolicy behavior. Run the full Cilium connectivity suite and packet-size tests suitable for ArvanCloud before production acceptance. Remove the test namespace afterward:

```bash
kubectl delete namespace cilium-smoke
```

From another terminal on the controller, expose Hubble UI locally:

```bash
kubectl -n kube-system port-forward --address 127.0.0.1 service/hubble-ui 12000:80
```

Open `http://127.0.0.1:12000` on that host. For a remote controller, create an SSH tunnel from your workstation: `ssh -L 12000:127.0.0.1:12000 devops@192.168.1.30`. The UI is not publicly exposed.

## 8. Troubleshooting

```bash
kubectl -n kube-system get pods -o wide
kubectl -n kube-system get events --sort-by=.lastTimestamp
kubectl -n kube-system logs daemonset/cilium --all-containers --tail=100
kubectl -n kube-system logs deployment/cilium-operator --tail=100
kubectl get nodes -o custom-columns=NAME:.metadata.name,PODCIDR:.spec.podCIDR
```

| Symptom | First Check |
|---|---|
| ImagePullBackOff | Node DNS, registry reachability, and egress via Kerio |
| Agent cannot reach API | `.10:6443`, routes, firewall, and k8sServiceHost |
| Empty PodCIDR | allocate-node-cidrs and controller-manager Pod CIDR |
| Broken inter-node traffic | UDP 8472, MTU, firewall, cloud port security |
| Broken Pod DNS | CoreDNS readiness, kube-dns ClusterIP, Service routing |
| Operator Pending | Capacity and anti-affinity; two schedulable nodes required |
| OOMKilled | Actual memory usage and agent/operator limits; tune after measuring |

`helm uninstall cilium` is not a general troubleshooting fix: removing the CNI immediately affects workloads. Modify values using the pinned chart and `helm upgrade`. Preserve the minimal inventory and externally managed CNI during future Kubernetes upgrades. Do not inadvertently change Kubespray to `kube_network_plugin: cilium`; Helm must remain the owner.

This profile does not install a CSR approver. Initial serving CSRs are approved in step 3. Establish ongoing CSR review or a restricted, trusted approver before installing Metrics Server. Never permanently enable blanket CSR approval or `--kubelet-insecure-tls`. Later services and CSR management are covered in the [full infrastructure runbook](documentation.md), but are not installed at this stage.

## References and Validation Status

- [Kubespray v2.32.0](https://github.com/kubernetes-sigs/kubespray/releases/tag/v2.32.0)
- [Generic CNI tasks in the selected tag](https://github.com/kubernetes-sigs/kubespray/blob/v2.32.0/roles/network_plugin/cni/tasks/main.yml)
- [Kubespray kube-proxy skip defaults](https://github.com/kubernetes-sigs/kubespray/blob/v2.32.0/roles/kubespray_defaults/defaults/main/main.yml)
- [Cilium Helm installation](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
- [Cilium kube-proxy replacement](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
- [Kubernetes compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)
- [Cilium requirements and ports](https://docs.cilium.io/en/stable/operations/system_requirements/)
- [Official Helm installation](https://helm.sh/docs/v3/intro/install/)

Local validation covered YAML/Bash, minimal inventory loading, cluster.yaml syntax against pinned Kubespray, and Cilium rendering. The deployment has not been executed on your VMs and actual network tests have not been run.
