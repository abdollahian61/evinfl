#!/usr/bin/env bash
set -euo pipefail
umask 077
MODE=${1:---all}
[[ $# -le 1 ]] || { echo 'Usage: bootstrap-controller.sh [--all|--ansible-only]' >&2; exit 1; }
case "$MODE" in --all|--ansible-only) ;; *) echo 'Usage: bootstrap-controller.sh [--all|--ansible-only]' >&2; exit 1 ;; esac
ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/config/versions.env"
mkdir -p "$ROOT_DIR/private" "$ROOT_DIR/.tools/bin"
chmod 700 "$ROOT_DIR/private"
if [[ ! -f "$ROOT_DIR/private/site.env" ]]; then
    install -m 600 "$ROOT_DIR/config/site.env.example" "$ROOT_DIR/private/site.env"
fi
source "$ROOT_DIR/private/site.env"
source /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 ]] || { echo 'Run on Ubuntu 24.04.' >&2; exit 1; }
sudo apt-get update
sudo apt-get install -y git curl ca-certificates python3-venv python3-pip jq openssh-client
KUBESPRAY_DIR=${KUBESPRAY_DIR:-$ROOT_DIR/.tools/kubespray}
VENV_DIR=${VENV_DIR:-$ROOT_DIR/.tools/ansible-venv}
if [[ ! -d "$KUBESPRAY_DIR/.git" ]]; then
    git clone --depth 1 --branch "$KUBESPRAY_VERSION" https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_DIR"
fi
[[ "$(git -C "$KUBESPRAY_DIR" rev-parse HEAD)" == "$(git -C "$KUBESPRAY_DIR" rev-parse "$KUBESPRAY_VERSION^{commit}")" ]] || { echo 'Kubespray checkout differs from the pinned release.' >&2; exit 1; }
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install -r "$KUBESPRAY_DIR/requirements.txt"
if [[ "$MODE" == --ansible-only ]]; then
    printf '%s\n' 'Ansible and pinned Kubespray installed. Helm has not been installed by this command.'
    exit 0
fi
case "$(uname -m)" in
    x86_64) ARCH=amd64 ;;
    aarch64) ARCH=arm64 ;;
    *) echo 'Unsupported CPU architecture.' >&2; exit 1 ;;
esac
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
curl -fsSL --retry 3 "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz" -o "$tmp_dir/helm.tar.gz"
curl -fsSL --retry 3 "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz.sha256sum" -o "$tmp_dir/helm.sha256sum"
expected=$(awk '{print $1}' "$tmp_dir/helm.sha256sum")
printf '%s  %s\n' "$expected" "$tmp_dir/helm.tar.gz" | sha256sum -c -
tar --no-same-owner -xzf "$tmp_dir/helm.tar.gz" -C "$tmp_dir"
install -m 755 "$tmp_dir/linux-$ARCH/helm" "$ROOT_DIR/.tools/bin/helm"
curl -fsSL --retry 3 "https://dl.k8s.io/release/v${KUBERNETES_VERSION}/bin/linux/${ARCH}/kubectl" -o "$tmp_dir/kubectl"
curl -fsSL --retry 3 "https://dl.k8s.io/release/v${KUBERNETES_VERSION}/bin/linux/${ARCH}/kubectl.sha256" -o "$tmp_dir/kubectl.sha256"
expected=$(tr -d '[:space:]' < "$tmp_dir/kubectl.sha256")
printf '%s  %s\n' "$expected" "$tmp_dir/kubectl" | sha256sum -c -
install -m 755 "$tmp_dir/kubectl" "$ROOT_DIR/.tools/bin/kubectl"
printf '%s\n' 'Controller tools installed. Edit private/site.env and private/secrets.yml before deployment.'
