#!/usr/bin/env bash
# Prepare a GitLab CI job as the Evinfl controller. Never prints secrets.
# Usage: scripts/ci/prepare.sh [--kubeconfig]
set -euo pipefail
umask 077
ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
need() { [[ -n "${!1:-}" ]] || { echo "Missing CI/CD variable: $1" >&2; exit 1; }; }
need SSH_PRIVATE_KEY
need SSH_KNOWN_HOSTS
need ANSIBLE_USER

# Ubuntu 24.04 job image runs as root; bootstrap-controller.sh expects sudo.
export DEBIAN_FRONTEND=noninteractive
if ! command -v sudo >/dev/null; then
    apt-get update -qq
    apt-get install -y -qq sudo >/dev/null
fi

# SSH key and pinned host keys (ansible.cfg keeps host_key_checking enabled).
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
key_file="$HOME/.ssh/evinfl_ci"
# File-type variables hold a path; variable-type ones hold the value.
if [[ -f "$SSH_PRIVATE_KEY" ]]; then cp "$SSH_PRIVATE_KEY" "$key_file"; else printf '%s\n' "$SSH_PRIVATE_KEY" > "$key_file"; fi
chmod 600 "$key_file"
if [[ -f "$SSH_KNOWN_HOSTS" ]]; then cp "$SSH_KNOWN_HOSTS" "$HOME/.ssh/known_hosts"; else printf '%s\n' "$SSH_KNOWN_HOSTS" > "$HOME/.ssh/known_hosts"; fi
chmod 600 "$HOME/.ssh/known_hosts"

# Controller settings for the existing scripts; tools live in the cached .tools/.
mkdir -p "$ROOT_DIR/private"
chmod 700 "$ROOT_DIR/private"
cat > "$ROOT_DIR/private/site.env" <<SITE
SSH_USER='$ANSIBLE_USER'
SSH_KEY='$key_file'
MASTER_IP='${MASTER_IP:-192.168.1.10}'
NFS_IP='${NFS_IP:-192.168.1.24}'
MINIO_ENDPOINT='${MINIO_ENDPOINT:-http://192.168.1.28:9000}'
APP_DOMAIN='${APP_DOMAIN:-app.example.com}'
KUBESPRAY_DIR='$ROOT_DIR/.tools/kubespray'
VENV_DIR='$ROOT_DIR/.tools/ansible-venv'
SITE
chmod 600 "$ROOT_DIR/private/site.env"

# Optional Ansible secrets (file-type variable with the contents of private/secrets.yml).
if [[ -n "${ANSIBLE_SECRETS_FILE:-}" ]]; then
    install -m 600 "$ANSIBLE_SECRETS_FILE" "$ROOT_DIR/private/secrets.yml"
fi
# Optional MinIO license (file-type variable).
if [[ -n "${MINIO_LICENSE_FILE:-}" ]]; then
    install -m 600 "$MINIO_LICENSE_FILE" "$ROOT_DIR/private/minio.license"
fi

# Pinned Kubespray, Ansible venv, Helm and kubectl (idempotent; cache makes reruns fast).
bash "$ROOT_DIR/scripts/bootstrap-controller.sh" --all >/dev/null

if [[ "${1:-}" == --kubeconfig ]]; then
    if [[ -n "${KUBECONFIG_FILE:-}" ]]; then
        install -m 600 "$KUBECONFIG_FILE" "$ROOT_DIR/private/admin.conf"
    else
        # Same source as install-kubernetes.sh; never stored as an artifact.
        master=${MASTER_IP:-192.168.1.10}
        tmp_config=$(mktemp "$ROOT_DIR/private/admin.conf.XXXXXX")
        ssh -i "$key_file" "$ANSIBLE_USER@$master" 'sudo -n cat /etc/kubernetes/admin.conf' > "$tmp_config"
        cluster_name=$(KUBECONFIG="$tmp_config" "$ROOT_DIR/.tools/bin/kubectl" config view --minify -o jsonpath='{.clusters[0].name}')
        KUBECONFIG="$tmp_config" "$ROOT_DIR/.tools/bin/kubectl" config set-cluster "$cluster_name" --server="https://$master:6443" >/dev/null
        mv "$tmp_config" "$ROOT_DIR/private/admin.conf"
    fi
fi
echo "CI controller ready."
