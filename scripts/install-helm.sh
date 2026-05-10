#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/usr/local/bin"
FALLBACK_VERSION="v3.15.0"
HELM_VERSION="${HELM_VERSION:-}"

# ── Architecture ───────────────────────────────────────────────────────────────

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# ── Version resolution ─────────────────────────────────────────────────────────

if [[ -z "$HELM_VERSION" ]]; then
    echo "Fetching latest Helm release..."
    HELM_VERSION=$(curl -fs "https://api.github.com/repos/helm/helm/releases/latest" \
        | grep '"tag_name"' | cut -d'"' -f4) || true

    if [[ -z "$HELM_VERSION" ]]; then
        echo "GitHub API unavailable — falling back to $FALLBACK_VERSION"
        HELM_VERSION="$FALLBACK_VERSION"
    fi
fi

echo "Helm version : $HELM_VERSION"
echo "Architecture : $ARCH"

# ── Idempotency check ──────────────────────────────────────────────────────────

if command -v helm &>/dev/null; then
    INSTALLED=$(helm version --short 2>/dev/null | grep -oP 'v[\d.]+' || echo "unknown")
    if [[ "$INSTALLED" == "$HELM_VERSION" ]]; then
        echo "Helm $HELM_VERSION is already installed — skipping."
        exit 0
    fi
    echo "Upgrading Helm: $INSTALLED → $HELM_VERSION"
fi

# ── Download and install ───────────────────────────────────────────────────────

URL="https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz"
echo "Downloading: $URL"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL "$URL" -o "${TMPDIR}/helm.tar.gz"
tar -xzf "${TMPDIR}/helm.tar.gz" -C "$TMPDIR"
sudo mv "${TMPDIR}/linux-${ARCH}/helm" "${INSTALL_DIR}/helm"

echo ""
echo "Installed: $(helm version --short)"
