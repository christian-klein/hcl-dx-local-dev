#!/usr/bin/env bash
set -euo pipefail

# Report which images required by the current chart versions are present in
# the local registry and which are missing.

LOCAL_ENV="local.env"
REGISTRY_HOST="localhost:${REGISTRY_PORT:-5001}"

if [[ ! -f "$LOCAL_ENV" ]]; then
    echo "Error: local.env not found." >&2
    exit 1
fi

# shellcheck source=local.env
source "$LOCAL_ENV"

REGISTRY_HOST="localhost:${REGISTRY_PORT:-5001}"
DX_RELEASE="${DX_RELEASE:-dx}"
DX_SEARCH_RELEASE="${DX_SEARCH_RELEASE:-dx-search}"

# ── Collect images from rendered helm templates ────────────────────────────────

IMAGES=()

collect_images() {
    local release="$1"
    local chart="$2"
    shift 2
    local values_flags=("$@")

    if [[ ! -d "$chart" ]]; then
        return
    fi

    while IFS= read -r image; do
        [[ -n "$image" ]] && IMAGES+=("$image")
    done < <(helm template "$release" "$chart" "${values_flags[@]}" 2>/dev/null \
        | grep -E '^\s+image:' \
        | sed 's/^\s*image:\s*//' \
        | tr -d '"'"'" \
        | grep "${HCL_REGISTRY}" \
        | sort -u)
}

DX_LOCAL_CHART="charts/dx/${DX_VERSION}/hcl-dx-deployment"
DX_VALUES="charts/dx/${DX_VERSION}/dx-values.yaml"
DX_SEARCH_VALUES="charts/dx/${DX_VERSION}/dx-search-values.yaml"

DX_FLAGS=()
[[ -f "$DX_VALUES" ]]        && DX_FLAGS+=(-f "$DX_VALUES")
[[ -f "$DX_SEARCH_VALUES" ]] && DX_FLAGS+=(-f "$DX_SEARCH_VALUES")

collect_images "$DX_RELEASE" "$DX_LOCAL_CHART" "${DX_FLAGS[@]}"

SEARCH_LOCAL_CHART="charts/search/${DX_SEARCH_VERSION}/hcl-dx-search"
SEARCH_VALUES="charts/search/${DX_SEARCH_VERSION}/search-values.yaml"
SEARCH_VALUES_LOCAL="charts/search/${DX_SEARCH_VERSION}/search-values-local.yaml"

SEARCH_FLAGS=()
[[ -f "$SEARCH_VALUES" ]]       && SEARCH_FLAGS+=(-f "$SEARCH_VALUES")
[[ -f "$SEARCH_VALUES_LOCAL" ]] && SEARCH_FLAGS+=(-f "$SEARCH_VALUES_LOCAL")

collect_images "$DX_SEARCH_RELEASE" "$SEARCH_LOCAL_CHART" "${SEARCH_FLAGS[@]}"

IFS=$'\n' read -r -d '' -a IMAGES < <(printf '%s\n' "${IMAGES[@]}" | sort -u && printf '\0') || true

if [[ ${#IMAGES[@]} -eq 0 ]]; then
    echo "No images found. Pull the charts first:"
    echo "  make pull-dx-chart"
    echo "  make pull-search-chart"
    exit 0
fi

# ── Check registry ─────────────────────────────────────────────────────────────

if ! curl -sf "http://${REGISTRY_HOST}/v2/" > /dev/null 2>&1; then
    echo "Warning: local registry at ${REGISTRY_HOST} is not reachable."
    echo "  Start the cluster first: make start"
    echo ""
fi

# ── Report ─────────────────────────────────────────────────────────────────────

PRESENT=0
MISSING=0

echo "Image status for DX ${DX_VERSION} / Search ${DX_SEARCH_VERSION}:"
echo ""

for image in "${IMAGES[@]}"; do
    path_and_tag="${image#${HCL_REGISTRY}/}"
    repo="${path_and_tag%:*}"
    tag="${path_and_tag##*:}"

    if curl -sf "http://${REGISTRY_HOST}/v2/${repo}/manifests/${tag}" > /dev/null 2>&1; then
        echo "  [ok]      ${image}"
        ((PRESENT++)) || true
    else
        echo "  [missing] ${image}"
        ((MISSING++)) || true
    fi
done

echo ""
echo "${PRESENT} cached, ${MISSING} missing."
[[ $MISSING -gt 0 ]] && echo "Run 'make load-images' to load missing images."
exit 0
