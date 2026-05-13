#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="local.env"
CLUSTER_NAME="${CLUSTER_NAME:-hcl-dx}"
CLUSTER_CONFIG="config/k3d-cluster.yaml"

# ── Validate prerequisites ─────────────────────────────────────────────────────

if [[ ! -f "$LOCAL_ENV" ]]; then
    echo "Error: local.env not found. Run 'make analyze-resources' first." >&2
    exit 1
fi

# shellcheck source=local.env
source "$LOCAL_ENV"
CLUSTER_NAME="${CLUSTER_NAME:-hcl-dx}"

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
echo "  Config file    : $CLUSTER_CONFIG"
echo ""

k3d cluster create --config "$CLUSTER_CONFIG"

echo ""
echo "Cluster '$CLUSTER_NAME' is ready."
echo "Active kubectl context: $(kubectl config current-context)"
