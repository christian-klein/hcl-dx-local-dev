#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="local.env"
DX_NAMESPACE="${DX_NAMESPACE:-dxns}"

if [[ -f "$LOCAL_ENV" ]]; then
    # shellcheck source=local.env
    source "$LOCAL_ENV"
fi

DX_NAMESPACE="${DX_NAMESPACE:-dxns}"

# ── Delete namespace ───────────────────────────────────────────────────────────

if kubectl get namespace "$DX_NAMESPACE" &>/dev/null; then
    echo "Deleting namespace '$DX_NAMESPACE'..."
    kubectl delete namespace "$DX_NAMESPACE"
    echo "Namespace '$DX_NAMESPACE' deleted."
else
    echo "Namespace '$DX_NAMESPACE' not found. Skipping."
fi

# ── Note ───────────────────────────────────────────────────────────────────────

echo "Chart files in charts/ are not removed by clean-dx."
echo "  Delete charts/${DX_VERSION} manually if needed."
