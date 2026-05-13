#!/usr/bin/env bash
set -euo pipefail

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

CHART_DIR="charts/${DX_VERSION}"
TARBALL="${CHART_DIR}/hcl-dx-deployment-${DX_VERSION}.tgz"
EXTRACTED="${CHART_DIR}/hcl-dx-deployment"

if [[ ! -f "$TARBALL" ]]; then
    echo "Error: tarball not found: ${TARBALL}" >&2
    echo "  Run 'make pull-dx-chart' to download it first." >&2
    exit 1
fi

echo "This will overwrite any local edits to ${EXTRACTED}."
read -rp "Reset chart from tarball? [y/N] " ans
[[ "${ans:-N}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

rm -rf "$EXTRACTED"
tar -xzf "$TARBALL" -C "$CHART_DIR"
echo "Chart reset to original at: ${EXTRACTED}"
