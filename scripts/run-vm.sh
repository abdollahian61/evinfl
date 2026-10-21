#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
VM=${1:?Usage: run-vm.sh VM_NAME [ansible-playbook options]}
shift
case "$VM" in
    k8s-master01|k8s-worker01|k8s-worker02|k8s-worker03|haproxy01|nfs01|minio01|monitoring01|clickhouse01|meilisearch01) ;;
    *) echo 'Unknown or manually installed VM. See vms/README.md.' >&2; exit 1 ;;
esac
[[ -f "$ROOT_DIR/private/site.env" ]] || { echo 'Run bootstrap-controller.sh first.' >&2; exit 1; }
source "$ROOT_DIR/private/site.env"
VENV_DIR=${VENV_DIR:-$ROOT_DIR/.tools/ansible-venv}
export ANSIBLE_CONFIG="$ROOT_DIR/ansible/ansible.cfg"
extra_vars=()
if [[ -f "$ROOT_DIR/private/secrets.yml" ]]; then extra_vars=(-e "@$ROOT_DIR/private/secrets.yml"); fi
exec "$VENV_DIR/bin/ansible-playbook" -i "$ROOT_DIR/ansible/inventory.ini" \
    -u "$SSH_USER" --private-key "$SSH_KEY" -b \
    "$ROOT_DIR/vms/$VM/install.yml" "${extra_vars[@]}" "$@"
