#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
stage=${1:?Usage: install-addons.sh cilium|storage|gateway|metrics|monitoring|velero|verify|all}
shift
case "$stage" in cilium|storage|gateway|metrics|monitoring|velero|verify|all) ;; *) echo 'Invalid stage.' >&2; exit 1 ;; esac
source "$ROOT_DIR/private/site.env"
VENV_DIR=${VENV_DIR:-$ROOT_DIR/.tools/ansible-venv}
export PATH="$ROOT_DIR/.tools/bin:$PATH"
export ANSIBLE_CONFIG="$ROOT_DIR/ansible/ansible.cfg"
export KUBECONFIG="$ROOT_DIR/private/admin.conf"
extra_vars=()
if [[ -f "$ROOT_DIR/private/secrets.yml" ]]; then extra_vars=(-e "@$ROOT_DIR/private/secrets.yml"); fi
tag_args=()
if [[ "$stage" != all ]]; then tag_args=(--tags "$stage"); fi
exec "$VENV_DIR/bin/ansible-playbook" -i "$ROOT_DIR/ansible/inventory.ini" \
    -u "$SSH_USER" --private-key "$SSH_KEY" \
    "$ROOT_DIR/ansible/playbooks/addons.yml" "${extra_vars[@]}" "${tag_args[@]}" "$@"
