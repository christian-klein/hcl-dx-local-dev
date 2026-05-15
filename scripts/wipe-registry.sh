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
    --delete-enabled

# Reconnect the registry to the cluster network so nodes can resolve k3d-dx-registry.
CLUSTER_NETWORK="k3d-${CLUSTER_NAME:-hcl-dx}"
if docker network inspect "$CLUSTER_NETWORK" &>/dev/null; then
    echo "Reconnecting registry to cluster network '${CLUSTER_NETWORK}'..."
    docker network connect "$CLUSTER_NETWORK" "k3d-${REGISTRY_NAME}" 2>/dev/null || true
fi

echo "Registry wiped. Run 'make load-images' to reload."
