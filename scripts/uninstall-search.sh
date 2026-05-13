#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="local.env"
DX_NAMESPACE="${DX_NAMESPACE:-dxns}"
DX_SEARCH_RELEASE="${DX_SEARCH_RELEASE:-dx-search}"

if [[ -f "$LOCAL_ENV" ]]; then
    # shellcheck source=local.env
    source "$LOCAL_ENV"
fi

DX_NAMESPACE="${DX_NAMESPACE:-dxns}"
DX_SEARCH_RELEASE="${DX_SEARCH_RELEASE:-dx-search}"

if ! helm status "$DX_SEARCH_RELEASE" -n "$DX_NAMESPACE" &>/dev/null; then
    echo "No Helm release '${DX_SEARCH_RELEASE}' found in namespace '${DX_NAMESPACE}'. Nothing to uninstall."
    exit 0
fi

echo "Uninstalling HCL DX Search v2 release '${DX_SEARCH_RELEASE}' from namespace '${DX_NAMESPACE}'..."
helm uninstall "$DX_SEARCH_RELEASE" -n "$DX_NAMESPACE"
echo "HCL DX Search v2 uninstalled."
