#!/usr/bin/env bash
set -euo pipefail

# Run securityadmin.sh inside the OpenSearch manager pod to initialize (or
# re-initialize) the OpenSearch security index. Must be run once after every
# fresh install and after any cert rotation.
#
# The HCL OpenSearch image ships with an empty internal_users.yml. The search
# middleware query pod connects via basic auth (admin:admin) — hardcoded in the
# chart template. This script generates a bcrypt hash for "admin" using
# OpenSearch's own hash.sh tool and writes the user into internal_users.yml
# before pushing the full security config via securityadmin.sh.

LOCAL_ENV="local.env"

if [[ ! -f "$LOCAL_ENV" ]]; then
    echo "Error: local.env not found." >&2
    exit 1
fi

# shellcheck source=local.env
source "$LOCAL_ENV"

DX_NAMESPACE="${DX_NAMESPACE:-dxns}"
DX_SEARCH_RELEASE="${DX_SEARCH_RELEASE:-dx-search}"

OPENSEARCH_POD="${DX_SEARCH_RELEASE}-open-search-manager-0"
HASH_SH="/usr/share/opensearch/plugins/opensearch-security/tools/hash.sh"
SECURITYADMIN="/usr/share/opensearch/plugins/opensearch-security/tools/securityadmin.sh"
SECURITY_CONFIG="/usr/share/opensearch/config/opensearch-security"
ADMIN_CERTS="/usr/share/opensearch/config/certs/admin-certs"

echo "Waiting for ${OPENSEARCH_POD} to be ready..."
kubectl wait pod "$OPENSEARCH_POD" \
    --namespace "$DX_NAMESPACE" \
    --for=condition=Ready \
    --timeout=300s

# Generate a bcrypt hash for "admin" password using OpenSearch's own tool.
# This avoids shipping a hardcoded hash while staying compatible with OpenSearch's
# bcrypt verification.
echo ""
echo "Generating admin password hash..."
ADMIN_HASH=$(kubectl exec -n "$DX_NAMESPACE" "$OPENSEARCH_POD" -- \
    "$HASH_SH" -p admin 2>/dev/null | grep -v '^#' | grep -v '^[[:space:]]*$' | tail -1)

if [[ -z "$ADMIN_HASH" ]]; then
    echo "Error: Failed to generate admin password hash from ${HASH_SH}." >&2
    exit 1
fi

# Write internal_users.yml with the admin user into the pod.
# The admin backend_role maps to all_access in the chart's roles_mapping.yml.
# ADMIN_HASH is passed via env to avoid bash heredoc expansion of the bcrypt
# dollar signs ($2y$12$...) in the outer script context.
echo "Writing internal_users.yml..."
kubectl exec -n "$DX_NAMESPACE" "$OPENSEARCH_POD" -- \
    env ADMIN_HASH="$ADMIN_HASH" \
    bash -c 'cat > /usr/share/opensearch/config/opensearch-security/internal_users.yml <<INTERNALUSERS
_meta:
  type: "internalusers"
  config_version: 2

admin:
  hash: "${ADMIN_HASH}"
  reserved: true
  backend_roles:
    - "admin"
  description: "Admin user"
INTERNALUSERS'

echo ""
echo "Running securityadmin.sh..."
kubectl exec -n "$DX_NAMESPACE" "$OPENSEARCH_POD" -- \
    "$SECURITYADMIN" \
    -cd "$SECURITY_CONFIG" \
    -cacert "${ADMIN_CERTS}/root-ca.pem" \
    -cert  "${ADMIN_CERTS}/admin.pem" \
    -key   "${ADMIN_CERTS}/admin-key.pem" \
    -h localhost -p 9200 -nhnv -icl

echo ""
echo "OpenSearch security initialized."
