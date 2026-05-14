#!/usr/bin/env bash
set -euo pipefail

# k3d's local-path StorageClass only supports ReadWriteOnce.
# Two DX chart PVC templates hardcode ReadWriteMany; this script patches them.
# Called automatically by install-dx.sh before every helm install/upgrade.

LOCAL_ENV="local.env"

if [[ ! -f "$LOCAL_ENV" ]]; then
    echo "Error: local.env not found." >&2
    exit 1
fi

# shellcheck source=local.env
source "$LOCAL_ENV"

if [[ -z "${DX_VERSION:-}" ]]; then
    echo "Error: DX_VERSION is not set in local.env." >&2
    exit 1
fi

CHART_DIR="charts/dx/${DX_VERSION}/hcl-dx-deployment/templates"

patch_pvc() {
    local file="$1"
    local label="$2"

    if [[ ! -f "$file" ]]; then
        echo "Warning: ${file} not found — skipping." >&2
        return
    fi

    if grep -q '"ReadWriteMany"' "$file"; then
        sed -i 's/"ReadWriteMany"/"ReadWriteOnce"/' "$file"
        echo "Patched ${label}: ReadWriteMany → ReadWriteOnce"
    else
        echo "${label}: already ReadWriteOnce — skipping."
    fi
}

patch_pvc "${CHART_DIR}/core/core-pvc.yaml"                                              "core-pvc"
patch_pvc "${CHART_DIR}/digital-asset-management/digital-asset-management-pvc.yaml"      "dam-pvc"
