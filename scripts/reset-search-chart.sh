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

CHART_DIR="charts/search/${DX_SEARCH_VERSION}"
TARBALL="${CHART_DIR}/hcl-dx-search-${DX_SEARCH_VERSION}.tgz"
EXTRACTED="${CHART_DIR}/hcl-dx-search"

if [[ ! -f "$TARBALL" ]]; then
    echo "Error: tarball not found at ${TARBALL}." >&2
    echo "  Run 'make pull-search-chart' first." >&2
    exit 1
fi

echo "This will overwrite ${EXTRACTED} with the contents of the tarball."
read -rp "Continue? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

rm -rf "$EXTRACTED"
tar -xzf "$TARBALL" -C "$CHART_DIR"
echo "Chart reset to tarball contents at: ${EXTRACTED}"
