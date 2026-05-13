#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="local.env"
DX_NAMESPACE="${DX_NAMESPACE:-dxns}"
DX_RELEASE="${DX_RELEASE:-dx}"

if [[ -f "$LOCAL_ENV" ]]; then
    # shellcheck source=local.env
    source "$LOCAL_ENV"
fi

DX_NAMESPACE="${DX_NAMESPACE:-dxns}"
DX_RELEASE="${DX_RELEASE:-dx}"

# ── Helm uninstall ─────────────────────────────────────────────────────────────

if ! helm status "$DX_RELEASE" -n "$DX_NAMESPACE" &>/dev/null; then
    echo "No Helm release '$DX_RELEASE' found in namespace '$DX_NAMESPACE'. Nothing to uninstall."
    exit 0
fi

echo "Uninstalling HCL DX release '$DX_RELEASE' from namespace '$DX_NAMESPACE'..."
helm uninstall "$DX_RELEASE" -n "$DX_NAMESPACE"
echo "HCL DX uninstalled."
