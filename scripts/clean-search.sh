#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="local.env"
DX_SEARCH_VERSION="${DX_SEARCH_VERSION:-}"

if [[ -f "$LOCAL_ENV" ]]; then
    # shellcheck source=local.env
    source "$LOCAL_ENV"
fi

DX_SEARCH_VERSION="${DX_SEARCH_VERSION:-}"

echo "Chart files in charts/ are not removed by clean-search."
if [[ -n "$DX_SEARCH_VERSION" ]]; then
    echo "  Delete charts/search/${DX_SEARCH_VERSION} manually if needed."
fi
