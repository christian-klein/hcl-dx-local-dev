#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/usr/local/bin"
FALLBACK_VERSION="v0.32.4"
K9S_VERSION="${K9S_VERSION:-}"

# ── Architecture ───────────────────────────────────────────────────────────────

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# ── Version resolution ─────────────────────────────────────────────────────────

if [[ -z "$K9S_VERSION" ]]; then
    echo "Fetching latest k9s release..."
    K9S_VERSION=$(curl -fs "https://api.github.com/repos/derailed/k9s/releases/latest" \
        | grep '"tag_name"' | cut -d'"' -f4) || true

    if [[ -z "$K9S_VERSION" ]]; then
        echo "GitHub API unavailable — falling back to $FALLBACK_VERSION"
        K9S_VERSION="$FALLBACK_VERSION"
    fi
fi

echo "k9s version  : $K9S_VERSION"
echo "Architecture : $ARCH"

# ── Idempotency check ──────────────────────────────────────────────────────────

if command -v k9s &>/dev/null; then
    INSTALLED=$(k9s version 2>/dev/null | grep 'Version:' | grep -oP 'v[\d.]+' || echo "unknown")
    if [[ "$INSTALLED" == "$K9S_VERSION" ]]; then
        echo "k9s $K9S_VERSION is already installed — skipping."
        exit 0
    fi
    echo "Upgrading k9s: $INSTALLED → $K9S_VERSION"
fi

# ── Download and install ───────────────────────────────────────────────────────

# k9s release naming: k9s_Linux_amd64.tar.gz (capital Linux, lowercase arch)
URL="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz"
echo "Downloading: $URL"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL "$URL" -o "${TMPDIR}/k9s.tar.gz"
tar -xzf "${TMPDIR}/k9s.tar.gz" -C "$TMPDIR"
sudo mv "${TMPDIR}/k9s" "${INSTALL_DIR}/k9s"

echo ""
echo "Installed: $(k9s version | grep 'Version:')"
