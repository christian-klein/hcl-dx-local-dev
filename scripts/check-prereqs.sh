#!/usr/bin/env bash
set -euo pipefail

# Prerequisites required before any tool install targets can run.
# Checks for presence and, where missing, offers to install via the detected
# package manager.

PASS="✓"
FAIL="✗"
WARN="!"
ERRORS=0

# ── Helpers ───────────────────────────────────────────────────────────────────

detect_pkg_manager() {
    if command -v pacman &>/dev/null; then echo "pacman"
    elif command -v apt-get &>/dev/null; then echo "apt"
    elif command -v dnf &>/dev/null; then echo "dnf"
    elif command -v brew &>/dev/null; then echo "brew"
    else echo "unknown"
    fi
}

pkg_install() {
    local pkg="$1"
    local mgr
    mgr=$(detect_pkg_manager)

    case "$mgr" in
        pacman) sudo pacman -S --noconfirm "$pkg" ;;
        apt)    sudo apt-get install -y "$pkg" ;;
        dnf)    sudo dnf install -y "$pkg" ;;
        brew)   brew install "$pkg" ;;
        *)
            echo "  Could not detect package manager. Install '${pkg}' manually."
            return 1
            ;;
    esac
}

prompt_install() {
    local name="$1"
    local pkg="$2"
    local extra="${3:-}"

    read -rp "  Install ${name}? [Y/n] " ans
    ans="${ans:-Y}"
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        pkg_install "$pkg"
        [[ -n "$extra" ]] && eval "$extra"
        return 0
    fi
    return 1
}

# ── Checks ────────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       Prerequisite Check                 ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# Docker binary
echo -n "  Docker binary  ... "
if command -v docker &>/dev/null; then
    echo "$PASS  $(docker --version)"
else
    echo "$FAIL  not found"
    if ! prompt_install "Docker" "docker"; then
        (( ERRORS++ )) || true
    fi
fi

# Docker daemon
echo -n "  Docker daemon  ... "
if docker info &>/dev/null 2>&1; then
    echo "$PASS  running"
else
    echo "$WARN  not running"
    read -rp "  Start Docker daemon now? [Y/n] " ans
    ans="${ans:-Y}"
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        if sudo systemctl enable --now docker 2>&1; then
            sudo usermod -aG docker "$USER"
            echo "  Docker started. You may need to log out and back in for group membership to take effect."
        else
            echo "  $FAIL  Failed to start Docker. Investigate with:"
            echo "           sudo systemctl status docker.service"
            echo "           sudo journalctl -xeu docker.service"
            (( ERRORS++ )) || true
        fi
    else
        echo "  Docker must be running before installing k3d."
        (( ERRORS++ )) || true
    fi
fi

# curl
echo -n "  curl           ... "
if command -v curl &>/dev/null; then
    echo "$PASS  $(curl --version | head -1)"
else
    echo "$FAIL  not found"
    if ! prompt_install "curl" "curl"; then
        (( ERRORS++ )) || true
    fi
fi

# make (self-check)
echo -n "  make           ... "
if command -v make &>/dev/null; then
    echo "$PASS  $(make --version | head -1)"
else
    echo "$FAIL  not found — install 'make' via your package manager"
    (( ERRORS++ )) || true
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
if (( ERRORS == 0 )); then
    echo "All prerequisites satisfied. You can proceed with 'make install-all'."
else
    echo "${ERRORS} prerequisite(s) unresolved. Resolve them before running 'make install-all'."
    exit 1
fi
echo ""
