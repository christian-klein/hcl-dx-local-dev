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

if [[ -z "${HCL_USER:-}" || -z "${HCL_PASS:-}" ]]; then
    echo "Error: HCL_USER and HCL_PASS must be set in local.env." >&2
    exit 1
fi

HCL_REGISTRY="${HCL_REGISTRY:-hclcr.io}"
CHART_DIR="charts/search/${DX_SEARCH_VERSION}"
TARBALL="${CHART_DIR}/hcl-dx-search-${DX_SEARCH_VERSION}.tgz"
EXTRACTED="${CHART_DIR}/hcl-dx-search"

mkdir -p "$CHART_DIR"

# ── Download ───────────────────────────────────────────────────────────────────

if [[ -f "$TARBALL" ]]; then
    echo "Tarball already present: ${TARBALL}"
else
    echo "Logging in to ${HCL_REGISTRY}..."
    echo "$HCL_PASS" | helm registry login "$HCL_REGISTRY" -u "$HCL_USER" --password-stdin

    echo "Pulling hcl-dx-search ${DX_SEARCH_VERSION}..."
    helm pull "oci://${HCL_REGISTRY}/dx-compose/hcl-dx-search" \
        --version "$DX_SEARCH_VERSION" \
        --destination "$CHART_DIR"
    echo "Tarball saved to: ${TARBALL}"
fi

# ── Extract ────────────────────────────────────────────────────────────────────

if [[ -d "$EXTRACTED" ]]; then
    echo "Chart already extracted at: ${EXTRACTED}"
    echo "  Edit it freely. Run 'make reset-search-chart' to restore from the tarball."
else
    echo "Extracting chart..."
    tar -xzf "$TARBALL" -C "$CHART_DIR"
    echo "Chart extracted to: ${EXTRACTED}"
fi
