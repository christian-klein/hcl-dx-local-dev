#!/usr/bin/env bash
set -euo pipefail

# Pull all HCL images referenced by the current chart versions and push them
# to the local k3d registry. Once loaded, pods pull from the local registry
# transparently (via the hclcr.io mirror) and work offline.

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
        echo "  (chart not found at ${chart} — skipping)"
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

echo "==> Collecting image list from helm templates..."

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

# Deduplicate
IFS=$'\n' read -r -d '' -a IMAGES < <(printf '%s\n' "${IMAGES[@]}" | sort -u && printf '\0') || true

if [[ ${#IMAGES[@]} -eq 0 ]]; then
    echo "No images found. Pull the charts first:"
    echo "  make pull-dx-chart"
    echo "  make pull-search-chart"
    exit 1
fi

echo "  Found ${#IMAGES[@]} images."
echo ""

# ── Check registry is reachable ───────────────────────────────────────────────

if ! curl -sf "http://${REGISTRY_HOST}/v2/" > /dev/null 2>&1; then
    echo "Error: local registry at ${REGISTRY_HOST} is not reachable." >&2
    echo "  Start the cluster first: make start" >&2
    exit 1
fi

# ── Login to HCL registry ─────────────────────────────────────────────────────

if [[ -z "${HCL_USER:-}" || -z "${HCL_PASS:-}" ]]; then
    echo "Error: HCL_USER and HCL_PASS must be set in local.env." >&2
    exit 1
fi

echo "$HCL_PASS" | docker login "$HCL_REGISTRY" -u "$HCL_USER" --password-stdin
echo ""

# ── Pull, retag, push ─────────────────────────────────────────────────────────

LOADED=0
SKIPPED=0
FAILED=0

for image in "${IMAGES[@]}"; do
    local_image="${image/${HCL_REGISTRY}/${REGISTRY_HOST}}"
    path_and_tag="${image#${HCL_REGISTRY}/}"

    # Check if already in local registry via API
    repo="${path_and_tag%:*}"
    tag="${path_and_tag##*:}"
    if curl -sf "http://${REGISTRY_HOST}/v2/${repo}/manifests/${tag}" > /dev/null 2>&1; then
        echo "  [cached]  ${image}"
        ((SKIPPED++)) || true
        continue
    fi

    echo "  [loading] ${image}"
    if docker pull "$image" && \
       docker tag  "$image" "$local_image" && \
       docker push "$local_image"; then
        ((LOADED++)) || true
    else
        echo "  [failed]  ${image}" >&2
        ((FAILED++)) || true
    fi
done

echo ""
echo "Done. ${LOADED} loaded, ${SKIPPED} already cached, ${FAILED} failed."
[[ $FAILED -gt 0 ]] && exit 1 || exit 0
