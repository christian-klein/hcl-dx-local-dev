#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="local.env"

if [[ ! -f "$LOCAL_ENV" ]]; then
    echo "Error: local.env not found." >&2
    exit 1
fi

# shellcheck source=local.env
source "$LOCAL_ENV"

if [[ -z "${DX_SEARCH_VERSION:-}" ]]; then
    echo "Error: DX_SEARCH_VERSION is not set in local.env." >&2
    exit 1
fi

HCL_REGISTRY="${HCL_REGISTRY:-hclcr.io}"
CHART_DIR="charts/search/${DX_SEARCH_VERSION}"
EXTRACTED="${CHART_DIR}/hcl-dx-search"
REFERENCE="${CHART_DIR}/search-values-reference.yaml"

mkdir -p "$CHART_DIR"

# ── Prefer local chart; fall back to OCI ──────────────────────────────────────

if [[ -d "$EXTRACTED" ]]; then
    echo "Reading values from local chart at ${EXTRACTED}..."
    helm show values "$EXTRACTED" > "$REFERENCE"
else
    if [[ -z "${HCL_USER:-}" || -z "${HCL_PASS:-}" ]]; then
        echo "Error: local chart not found and HCL_USER/HCL_PASS are not set." >&2
        echo "  Run 'make pull-search-chart' first, or set credentials in local.env." >&2
        exit 1
    fi
    echo "Local chart not found. Fetching values from OCI registry..."
    echo "$HCL_PASS" | helm registry login "$HCL_REGISTRY" -u "$HCL_USER" --password-stdin
    helm show values "oci://${HCL_REGISTRY}/dx-compose/hcl-dx-search" \
        --version "$DX_SEARCH_VERSION" > "$REFERENCE"
fi

echo ""
echo "Reference values saved to: ${REFERENCE}"
echo "Copy the sections you want to override into charts/search/${DX_SEARCH_VERSION}/search-values.yaml."
