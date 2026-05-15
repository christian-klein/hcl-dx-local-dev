#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="local.env"

# ── Load config ────────────────────────────────────────────────────────────────

if [[ ! -f "$LOCAL_ENV" ]]; then
    echo "Error: local.env not found. Run 'make configure-dx' first." >&2
    exit 1
fi

# shellcheck source=local.env
source "$LOCAL_ENV"

# ── Validate ───────────────────────────────────────────────────────────────────

if [[ -z "${DX_VERSION:-}" ]]; then
    echo "Error: DX_VERSION is not set in local.env." >&2
    exit 1
fi

if [[ -z "${HCL_USER:-}" || -z "${HCL_PASS:-}" ]]; then
    echo "Error: HCL_USER and HCL_PASS must be set in local.env." >&2
    exit 1
fi

HCL_REGISTRY="${HCL_REGISTRY:-hclcr.io}"
DX_CHART_REPO="${DX_CHART_REPO:-hclcr.io/dx/hcl-dx-deployment}"
CHART_DIR="charts/dx/${DX_VERSION}"
TARBALL="${CHART_DIR}/hcl-dx-deployment-${DX_VERSION}.tgz"
EXTRACTED="${CHART_DIR}/hcl-dx-deployment"

mkdir -p "$CHART_DIR"

# ── Download ───────────────────────────────────────────────────────────────────

if [[ -f "$TARBALL" ]]; then
    echo "Tarball already present: ${TARBALL}"
else
    echo "Logging in to ${HCL_REGISTRY}..."
    echo "$HCL_PASS" | helm registry login "$HCL_REGISTRY" -u "$HCL_USER" --password-stdin

    echo "Pulling hcl-dx-deployment ${DX_VERSION}..."
    helm pull "oci://${DX_CHART_REPO}" \
        --version "$DX_VERSION" \
        --destination "$CHART_DIR"
    echo "Tarball saved to: ${TARBALL}"
fi

# ── Extract ────────────────────────────────────────────────────────────────────

if [[ -d "$EXTRACTED" ]]; then
    echo "Chart already extracted at: ${EXTRACTED}"
    echo "  Edit it freely. Run 'make reset-dx-chart' to restore from the tarball."
else
    echo "Extracting chart..."
    tar -xzf "$TARBALL" -C "$CHART_DIR"
    echo "Chart extracted to: ${EXTRACTED}"
fi
