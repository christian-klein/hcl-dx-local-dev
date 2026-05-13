#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="local.env"

if [[ -f "$LOCAL_ENV" ]]; then
    # shellcheck source=local.env
    source "$LOCAL_ENV"
fi

DX_NAMESPACE="${DX_NAMESPACE:-dxns}"
DX_SEARCH_RELEASE="${DX_SEARCH_RELEASE:-dx-search}"
DX_RELEASE="${DX_RELEASE:-dx}"
DX_VERSION="${DX_VERSION:-}"

# ── Uninstall Search v2 ────────────────────────────────────────────────────────

if ! helm status "$DX_SEARCH_RELEASE" -n "$DX_NAMESPACE" &>/dev/null; then
    echo "No Helm release '${DX_SEARCH_RELEASE}' found in namespace '${DX_NAMESPACE}'. Nothing to uninstall."
else
    echo "Uninstalling HCL DX Search v2 release '${DX_SEARCH_RELEASE}' from namespace '${DX_NAMESPACE}'..."
    helm uninstall "$DX_SEARCH_RELEASE" -n "$DX_NAMESPACE"
    echo "HCL DX Search v2 uninstalled."
fi

# ── Revert DX to Search v1 ────────────────────────────────────────────────────

echo ""
echo "─────────────────────────────────────────────────────────────────────"
echo "  Reverting DX to Search v1 (Remote Search enabled, Search v2 off)"
echo "─────────────────────────────────────────────────────────────────────"

if [[ -z "$DX_VERSION" ]]; then
    echo "  DX_VERSION is not set in local.env — cannot auto-revert DX."
    echo "  Delete charts/dx/<version>/dx-search-values.yaml and run 'make install-dx'."
    exit 0
fi

DX_SEARCH_VALUES="charts/dx/${DX_VERSION}/dx-search-values.yaml"
DX_VALUES="charts/dx/${DX_VERSION}/dx-values.yaml"
DX_LOCAL_CHART="charts/dx/${DX_VERSION}/hcl-dx-deployment"

if [[ -f "$DX_SEARCH_VALUES" ]]; then
    rm "$DX_SEARCH_VALUES"
    echo "  Removed ${DX_SEARCH_VALUES}."
else
    echo "  ${DX_SEARCH_VALUES} not found — already removed."
fi

if [[ ! -f "$DX_VALUES" ]]; then
    echo "  ${DX_VALUES} not found — skipping DX upgrade."
    exit 0
fi

if [[ ! -d "$DX_LOCAL_CHART" ]]; then
    echo "  Local DX chart not found at ${DX_LOCAL_CHART} — skipping DX upgrade."
    echo "  Run 'make install-dx' to complete the revert."
    exit 0
fi

if ! helm status "$DX_RELEASE" -n "$DX_NAMESPACE" &>/dev/null; then
    echo "  DX release '${DX_RELEASE}' not found — skipping upgrade."
    exit 0
fi

echo "  Upgrading DX release '${DX_RELEASE}' to restore defaults..."
helm upgrade "$DX_RELEASE" "$DX_LOCAL_CHART" \
    --namespace "$DX_NAMESPACE" \
    -f "$DX_VALUES"

echo ""
echo "DX reverted. Remote Search is re-enabled; Search v2 is off."
echo "  Monitor : k9s -n ${DX_NAMESPACE}"
