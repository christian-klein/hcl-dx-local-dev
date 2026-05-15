#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="local.env"
CLUSTER_NAME="${CLUSTER_NAME:-hcl-dx}"
CLUSTER_CONFIG="config/k3d-cluster.yaml"
REGISTRY_NAME="dx-registry"
REGISTRY_PORT="${REGISTRY_PORT:-5001}"

# ── Validate prerequisites ─────────────────────────────────────────────────────

if [[ ! -f "$LOCAL_ENV" ]]; then
    echo "Error: local.env not found. Run 'make analyze-resources' first." >&2
    exit 1
fi

# shellcheck source=local.env
source "$LOCAL_ENV"
CLUSTER_NAME="${CLUSTER_NAME:-hcl-dx}"
REGISTRY_PORT="${REGISTRY_PORT:-5001}"

# ── Docker socket access check ─────────────────────────────────────────────────

if ! docker info &>/dev/null; then
    echo "Error: cannot connect to the Docker daemon." >&2
    echo "" >&2
    echo "  If Docker was just installed or your user was just added to the" >&2
    echo "  'docker' group, the current shell session does not have the updated" >&2
    echo "  group membership yet. Fix with one of:" >&2
    echo "" >&2
    echo "    newgrp docker          # apply in the current shell" >&2
    echo "    exec su -l \$USER       # start a fresh login shell" >&2
    echo "" >&2
    echo "  Then re-run: make install-all" >&2
    exit 1
fi

# ── Local registry (persists across cluster recreations) ──────────────────────

if k3d registry list 2>/dev/null | grep -q "k3d-${REGISTRY_NAME}"; then
    echo "Local registry 'k3d-${REGISTRY_NAME}' already exists on port ${REGISTRY_PORT}."
else
    echo "Creating local registry 'k3d-${REGISTRY_NAME}' on port ${REGISTRY_PORT}..."
    k3d registry create "$REGISTRY_NAME" --port "$REGISTRY_PORT" \
        --delete-enabled
    echo "Registry ready. Push images with 'make load-images'."
fi

# ── Idempotency check ──────────────────────────────────────────────────────────

if k3d cluster get "$CLUSTER_NAME" &>/dev/null; then
    echo "Cluster '$CLUSTER_NAME' already exists."
    read -rp "Delete and recreate? [y/N] " ans
    ans="${ans:-N}"
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        echo "Deleting existing cluster '$CLUSTER_NAME'..."
        k3d cluster delete "$CLUSTER_NAME"
    else
        echo "Keeping existing cluster. Skipping configure-k3d."
        exit 0
    fi
fi

# ── Generate cluster config ────────────────────────────────────────────────────

mkdir -p config

cat > "$CLUSTER_CONFIG" <<EOF
apiVersion: k3d.io/v1alpha5
kind: Simple
metadata:
  name: ${CLUSTER_NAME}
servers: ${K3D_SERVERS}
agents: ${K3D_AGENTS}
ports:
  - port: 80:80
    nodeFilters:
      - loadbalancer
  - port: 443:443
    nodeFilters:
      - loadbalancer
registries:
  use:
    - k3d-${REGISTRY_NAME}:${REGISTRY_PORT}
  config: |
    mirrors:
      "${HCL_REGISTRY:-hclcr.io}":
        endpoint:
          - "http://k3d-${REGISTRY_NAME}:5000"
options:
  k3d:
    wait: true
    timeout: "300s"
  runtime:
    serversMemory: "${K3D_MEMORY}"
    agentsMemory: "${K3D_MEMORY}"
  kubeconfig:
    updateDefaultKubeconfig: true
    switchCurrentContext: true
EOF

# ── Create cluster ─────────────────────────────────────────────────────────────

echo ""
echo "Creating k3d cluster '$CLUSTER_NAME'..."
echo "  Servers        : $K3D_SERVERS"
echo "  Agents         : $K3D_AGENTS"
echo "  Memory per node: $K3D_MEMORY"
echo "  Registry       : k3d-${REGISTRY_NAME}:${REGISTRY_PORT} (mirror for ${HCL_REGISTRY:-hclcr.io})"
echo "  Config file    : $CLUSTER_CONFIG"
echo ""

k3d cluster create --config "$CLUSTER_CONFIG"

echo ""
echo "Cluster '$CLUSTER_NAME' is ready."
echo "Active kubectl context: $(kubectl config current-context)"
echo ""
echo "Run 'make load-images' to pre-load HCL images into the local registry."
