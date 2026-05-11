#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/usr/local/bin"
FALLBACK_VERSION="v5.7.4"
K3D_VERSION="${K3D_VERSION:-}"

# ── Architecture ───────────────────────────────────────────────────────────────

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# ── Version resolution ─────────────────────────────────────────────────────────

if [[ -z "$K3D_VERSION" ]]; then
    echo "Fetching latest k3d release..."
    K3D_VERSION=$(curl -fs "https://api.github.com/repos/k3d-io/k3d/releases/latest" \
        | grep '"tag_name"' | cut -d'"' -f4) || true

    if [[ -z "$K3D_VERSION" ]]; then
        echo "GitHub API unavailable — falling back to $FALLBACK_VERSION"
        K3D_VERSION="$FALLBACK_VERSION"
    fi
fi

echo "k3d version  : $K3D_VERSION"
echo "Architecture : $ARCH"

# ── Idempotency check ──────────────────────────────────────────────────────────

if command -v k3d &>/dev/null; then
    INSTALLED=$(k3d version 2>/dev/null | grep '^k3d version' | awk '{print $3}' || echo "unknown")
    if [[ "$INSTALLED" == "$K3D_VERSION" ]]; then
        echo "k3d $K3D_VERSION is already installed — skipping."
        exit 0
    fi
    echo "Upgrading k3d: $INSTALLED → $K3D_VERSION"
fi

# ── Download and install ───────────────────────────────────────────────────────

URL="https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-${ARCH}"
echo "Downloading: $URL"
curl -fsSL "$URL" -o /tmp/k3d
chmod +x /tmp/k3d
sudo mv /tmp/k3d "${INSTALL_DIR}/k3d"

echo ""
echo "Installed: $(k3d version)"
