#!/usr/bin/env bash
# Install only the pinned Helm client, on the management VM.
set -euo pipefail
umask 077
ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/config/versions.env"
case "$(uname -m)" in
    x86_64) ARCH=amd64 ;;
    aarch64) ARCH=arm64 ;;
    *) echo 'Unsupported CPU architecture.' >&2; exit 1 ;;
esac
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
curl -fsSL --retry 3 "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz" -o "$tmp_dir/helm.tar.gz"
curl -fsSL --retry 3 "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz.sha256sum" -o "$tmp_dir/helm.sha256sum"
expected=$(awk 'NR==1 {print $1}' "$tmp_dir/helm.sha256sum")
[[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || { echo 'Invalid Helm checksum response.' >&2; exit 1; }
printf '%s  %s\n' "$expected" "$tmp_dir/helm.tar.gz" | sha256sum -c -
tar --no-same-owner -xzf "$tmp_dir/helm.tar.gz" -C "$tmp_dir"
mkdir -p "$ROOT_DIR/.tools/bin"
install -m 755 "$tmp_dir/linux-$ARCH/helm" "$ROOT_DIR/.tools/bin/helm"
"$ROOT_DIR/.tools/bin/helm" version --short
