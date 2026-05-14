#!/usr/bin/env bash
set -euo pipefail

# Manual recovery after laptop sleep when the sleep hook is not installed,
# or when pods are still stuck after automatic Docker restart.

LOCAL_ENV="local.env"
CLUSTER_NAME="${CLUSTER_NAME:-hcl-dx}"

if [[ -f "$LOCAL_ENV" ]]; then
    # shellcheck source=local.env
    source "$LOCAL_ENV"
fi

CLUSTER_NAME="${CLUSTER_NAME:-hcl-dx}"

echo "==> Restarting Docker (requires sudo)..."
sudo systemctl restart docker

echo "==> Waiting for Docker daemon..."
until docker info &>/dev/null 2>&1; do sleep 1; done
echo "    Docker is ready."

echo "==> Starting k3d cluster '${CLUSTER_NAME}'..."
k3d cluster start "$CLUSTER_NAME" 2>/dev/null || true

echo ""
echo "Done. Pods with ImagePullBackOff will retry automatically."
echo "  Watch : kubectl get pods -n ${DX_NAMESPACE:-dxns} -w"
