#!/usr/bin/env bash
set -euo pipefail

REGISTRY_NAME="dx-registry"
REGISTRY_PORT="${REGISTRY_PORT:-5001}"

if [[ -f "local.env" ]]; then
    # shellcheck source=local.env
    source local.env
fi
REGISTRY_PORT="${REGISTRY_PORT:-5001}"

echo "This will delete all images in the local registry."
read -rp "Continue? [y/N] " ans
[[ "${ans:-N}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

echo "Deleting registry 'k3d-${REGISTRY_NAME}'..."
k3d registry delete "$REGISTRY_NAME" 2>/dev/null || true

echo "Recreating registry on port ${REGISTRY_PORT}..."
k3d registry create "$REGISTRY_NAME" --port "$REGISTRY_PORT" \
    --env REGISTRY_STORAGE_DELETE_ENABLED=true

echo "Registry wiped. Run 'make load-images' to reload."
