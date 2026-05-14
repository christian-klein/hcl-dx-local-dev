#!/usr/bin/env bash
set -euo pipefail

# Installs a systemd-sleep hook that restarts Docker on every resume.
#
# After laptop sleep/wake, Docker's network bridge goes stale and k3d nodes
# lose DNS resolution, causing ImagePullBackOff on pods that need to pull
# images. Restarting Docker rebuilds the bridge; k3d containers come back
# automatically via their --restart=unless-stopped policy.

HOOK="/etc/systemd/system-sleep/hcl-dx-k3d-resume"

if [[ -f "$HOOK" ]]; then
    echo "Sleep hook already installed at ${HOOK}."
    exit 0
fi

echo "Installing sleep hook at ${HOOK} (requires sudo)..."

sudo mkdir -p "$(dirname "$HOOK")"
sudo tee "$HOOK" > /dev/null <<'EOF'
#!/bin/sh
# Restart Docker on resume so k3d nodes regain network / DNS after sleep.
case "$1/$2" in
  post/suspend|post/hibernate|post/hybrid-sleep|post/suspend-then-hibernate)
    systemctl restart docker &
    ;;
esac
EOF

sudo chmod +x "$HOOK"

echo "Sleep hook installed. Docker will restart automatically on every resume."
echo "Run 'make uninstall-sleep-hook' to remove it."
