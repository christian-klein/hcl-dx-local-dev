#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/usr/local/bin"
FALLBACK_VERSION="v1.30.0"
KUBECTL_VERSION="${KUBECTL_VERSION:-}"

# ── Architecture ───────────────────────────────────────────────────────────────

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# ── Version resolution ─────────────────────────────────────────────────────────

if [[ -z "$KUBECTL_VERSION" ]]; then
    echo "Fetching latest stable kubectl version..."
    KUBECTL_VERSION=$(curl -fsSL "https://dl.k8s.io/release/stable.txt") || true

    if [[ -z "$KUBECTL_VERSION" ]]; then
        echo "dl.k8s.io unavailable — falling back to $FALLBACK_VERSION"
        KUBECTL_VERSION="$FALLBACK_VERSION"
    fi
fi

echo "kubectl version : $KUBECTL_VERSION"
echo "Architecture    : $ARCH"

# ── Idempotency check ──────────────────────────────────────────────────────────

if command -v kubectl &>/dev/null; then
    INSTALLED=$(kubectl version --client -o json 2>/dev/null \
        | grep '"gitVersion"' | head -1 | grep -oP 'v[\d.]+' || echo "unknown")
    if [[ "$INSTALLED" == "$KUBECTL_VERSION" ]]; then
        echo "kubectl $KUBECTL_VERSION is already installed — skipping."
        exit 0
    fi
    echo "Upgrading kubectl: $INSTALLED → $KUBECTL_VERSION"
fi

# ── Download and install ───────────────────────────────────────────────────────

URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"
echo "Downloading: $URL"
curl -fsSL "$URL" -o /tmp/kubectl
chmod +x /tmp/kubectl
sudo mv /tmp/kubectl "${INSTALL_DIR}/kubectl"

echo ""
echo "Installed: $(kubectl version --client)"
