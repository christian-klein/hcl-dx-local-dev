#!/usr/bin/env bash
set -euo pipefail

# Delete a specific image from the local registry.
# Usage: make delete-image IMAGE=hclcr.io/dx-compose/core:v95_CF229_20250814-2215

REGISTRY_PORT="${REGISTRY_PORT:-5001}"
REGISTRY_HOST="localhost:${REGISTRY_PORT}"

if [[ -f "local.env" ]]; then
    # shellcheck source=local.env
    source local.env
fi
REGISTRY_HOST="localhost:${REGISTRY_PORT:-5001}"
HCL_REGISTRY="${HCL_REGISTRY:-hclcr.io}"

IMAGE="${1:-${IMAGE:-}}"

if [[ -z "$IMAGE" ]]; then
    echo "Usage: make delete-image IMAGE=hclcr.io/dx-compose/core:tag" >&2
    exit 1
fi

# Strip registry prefix to get repo:tag
path_and_tag="${IMAGE#${HCL_REGISTRY}/}"
# Handle images already using localhost:port prefix
path_and_tag="${path_and_tag#${REGISTRY_HOST}/}"

repo="${path_and_tag%:*}"
tag="${path_and_tag##*:}"

echo "Deleting ${repo}:${tag} from local registry..."

# Fetch the content digest (must request manifest v2 to get the correct digest)
DIGEST=$(curl -sf \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    -I "http://${REGISTRY_HOST}/v2/${repo}/manifests/${tag}" \
    | grep -i "Docker-Content-Digest" \
    | tr -d '\r' \
    | awk '{print $2}')

if [[ -z "$DIGEST" ]]; then
    echo "Image not found in local registry: ${repo}:${tag}" >&2
    exit 1
fi

curl -sf -X DELETE "http://${REGISTRY_HOST}/v2/${repo}/manifests/${DIGEST}"
echo "Deleted ${repo}:${tag} (${DIGEST})"
