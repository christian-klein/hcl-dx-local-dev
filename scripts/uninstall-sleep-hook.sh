#!/usr/bin/env bash
set -euo pipefail

HOOK="/etc/systemd/system-sleep/hcl-dx-k3d-resume"

if [[ ! -f "$HOOK" ]]; then
    echo "Sleep hook not found at ${HOOK}. Nothing to remove."
    exit 0
fi

echo "Removing sleep hook at ${HOOK} (requires sudo)..."
sudo rm "$HOOK"
echo "Sleep hook removed."
