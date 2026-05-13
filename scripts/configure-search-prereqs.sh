#!/usr/bin/env bash
set -euo pipefail

# OpenSearch requires vm.max_map_count >= 262144.
# In k3d, nodes are Docker containers that share the host kernel,
# so setting this on the host applies to all k3d nodes.

REQUIRED=262144
SYSCTL_CONF="/etc/sysctl.d/99-dx-opensearch.conf"

current="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"

if [[ "$current" -ge "$REQUIRED" ]]; then
    echo "vm.max_map_count is already ${current} (>= ${REQUIRED}). Nothing to do."
    exit 0
fi

echo "vm.max_map_count is ${current} — OpenSearch requires at least ${REQUIRED}."
echo "Applying setting now and persisting to ${SYSCTL_CONF} (requires sudo)..."

sudo sysctl -w vm.max_map_count=${REQUIRED}

echo "vm.max_map_count=${REQUIRED}" | sudo tee "$SYSCTL_CONF" > /dev/null

echo "Done. vm.max_map_count=${REQUIRED} set and persisted."
