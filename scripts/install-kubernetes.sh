#!/usr/bin/env bash
set -euo pipefail
umask 077
ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/config/versions.env"
source "$ROOT_DIR/private/site.env"
KUBESPRAY_DIR=${KUBESPRAY_DIR:-$ROOT_DIR/.tools/kubespray}
VENV_DIR=${VENV_DIR:-$ROOT_DIR/.tools/ansible-venv}
[[ -f "$KUBESPRAY_DIR/cluster.yml" ]] || { echo 'Run bootstrap-controller.sh first.' >&2; exit 1; }
[[ "$(git -C "$KUBESPRAY_DIR" rev-parse HEAD)" == "$(git -C "$KUBESPRAY_DIR" rev-parse "$KUBESPRAY_VERSION^{commit}")" ]] || { echo 'Kubespray version mismatch.' >&2; exit 1; }
(
    cd "$KUBESPRAY_DIR"
    export ANSIBLE_CONFIG="$KUBESPRAY_DIR/ansible.cfg"
    "$VENV_DIR/bin/ansible-playbook" -i "$ROOT_DIR/inventory/hosts.ini" \
        -u "$SSH_USER" --private-key "$SSH_KEY" -b cluster.yml "$@"
)
# Never replace the operator's default ~/.kube/config.
tmp_config=$(mktemp "$ROOT_DIR/private/admin.conf.XXXXXX")
trap 'rm -f "$tmp_config"' EXIT
ssh -i "$SSH_KEY" "$SSH_USER@${MASTER_IP:-192.168.1.10}" 'sudo -n cat /etc/kubernetes/admin.conf' > "$tmp_config"
export KUBECONFIG="$tmp_config"
KUBECTL="$ROOT_DIR/.tools/bin/kubectl"
cluster_name=$("$KUBECTL" config view --minify -o jsonpath='{.clusters[0].name}')
"$KUBECTL" config set-cluster "$cluster_name" --server="https://${MASTER_IP:-192.168.1.10}:6443"
chmod 600 "$tmp_config"
mv "$tmp_config" "$ROOT_DIR/private/admin.conf"
printf '%s\n' 'Kubernetes control plane installed. Install Cilium next; nodes may be NotReady until then.'
