#!/usr/bin/env bash
set -euo pipefail

# Generate TLS certificates for OpenSearch and create the required k8s secrets.
# HCL DX Search v2 requires three secrets:
#   search-admin-cert  — used for cluster admin operations (securityadmin.sh)
#   search-node-cert   — used for inter-node and HTTP TLS
#   search-client-cert — used by the search middleware connecting to OpenSearch
#
# Certificate subjects must match the values baked into the OpenSearch image:
#   admin_dn : CN=A,OU=UNIT,O=ORG,C=US
#   nodes_dn : CN=opensearch-node* (wildcard)
#
# Keys must be in PKCS8 format (required by the OpenSearch security plugin).

LOCAL_ENV="local.env"

if [[ ! -f "$LOCAL_ENV" ]]; then
    echo "Error: local.env not found." >&2
    exit 1
fi

# shellcheck source=local.env
source "$LOCAL_ENV"

DX_NAMESPACE="${DX_NAMESPACE:-dxns}"
DX_SEARCH_RELEASE="${DX_SEARCH_RELEASE:-dx-search}"

if [[ -z "${DX_SEARCH_VERSION:-}" ]]; then
    echo "Error: DX_SEARCH_VERSION is not set in local.env." >&2
    exit 1
fi

CERT_DIR="charts/search/${DX_SEARCH_VERSION}/certs"
mkdir -p "$CERT_DIR"

# ── Root CA ────────────────────────────────────────────────────────────────────

if [[ -f "${CERT_DIR}/root-ca.pem" ]]; then
    echo "Root CA already exists at ${CERT_DIR}/root-ca.pem — skipping generation."
else
    echo "Generating root CA..."
    openssl genrsa -out "${CERT_DIR}/root-ca-key.pem" 2048 2>/dev/null
    openssl req -new -x509 -sha256 -days 3650 \
        -key "${CERT_DIR}/root-ca-key.pem" \
        -subj "/C=US/O=ORG/OU=UNIT/CN=opensearch" \
        -out "${CERT_DIR}/root-ca.pem" 2>/dev/null
    echo "Root CA generated."
fi

# ── Helper: generate a PKCS8 key + cert signed by the root CA ─────────────────

generate_cert() {
    local name="$1"      # base name: admin, node, client
    local subj="$2"      # full subject string e.g. /C=US/O=ORG/OU=UNIT/CN=A
    local extfile="${3:-}"  # optional SAN extensions file

    local key_temp="${CERT_DIR}/${name}-key-temp.pem"
    local key="${CERT_DIR}/${name}-key.pem"
    local csr="${CERT_DIR}/${name}.csr"
    local cert="${CERT_DIR}/${name}.pem"

    if [[ -f "$cert" ]]; then
        echo "${name} cert already exists — skipping."
        return
    fi

    echo "Generating ${name} cert (subject: ${subj})..."
    openssl genrsa -out "$key_temp" 2048 2>/dev/null
    # OpenSearch security plugin requires PKCS8 format keys
    openssl pkcs8 -inform PEM -outform PEM -in "$key_temp" \
        -topk8 -nocrypt -v1 PBE-SHA1-3DES -out "$key" 2>/dev/null
    rm -f "$key_temp"

    openssl req -new -sha256 -key "$key" -subj "$subj" -out "$csr" 2>/dev/null

    if [[ -n "$extfile" ]]; then
        openssl x509 -req -sha256 -days 3650 \
            -CA "${CERT_DIR}/root-ca.pem" \
            -CAkey "${CERT_DIR}/root-ca-key.pem" \
            -CAcreateserial \
            -extfile "$extfile" \
            -in "$csr" -out "$cert" 2>/dev/null
    else
        openssl x509 -req -sha256 -days 3650 \
            -CA "${CERT_DIR}/root-ca.pem" \
            -CAkey "${CERT_DIR}/root-ca-key.pem" \
            -CAcreateserial \
            -in "$csr" -out "$cert" 2>/dev/null
    fi

    rm -f "$csr"
    echo "${name} cert generated."
}

# ── Admin cert — subject must match admin_dn baked into the OpenSearch image ──
# Image opensearch.yml: plugins.security.authcz.admin_dn: ["CN=A,OU=UNIT,O=ORG,C=US"]

generate_cert "admin" "/C=US/O=ORG/OU=UNIT/CN=A"

# ── Node cert — CN must match nodes_dn wildcard: CN=opensearch-node* ──────────
# Includes SANs for all OpenSearch service and pod DNS names in the cluster.

NODE_SAN="${CERT_DIR}/node-san.ext"
cat > "$NODE_SAN" <<EOF
subjectAltName=DNS:${DX_SEARCH_RELEASE}-open-search-manager,\
DNS:${DX_SEARCH_RELEASE}-open-search-manager.${DX_NAMESPACE},\
DNS:${DX_SEARCH_RELEASE}-open-search-manager.${DX_NAMESPACE}.svc.cluster.local,\
DNS:${DX_SEARCH_RELEASE}-open-search-manager-headless,\
DNS:${DX_SEARCH_RELEASE}-open-search-manager-headless.${DX_NAMESPACE},\
DNS:${DX_SEARCH_RELEASE}-open-search-manager-headless.${DX_NAMESPACE}.svc.cluster.local,\
DNS:${DX_SEARCH_RELEASE}-open-search-data,\
DNS:${DX_SEARCH_RELEASE}-open-search-data.${DX_NAMESPACE},\
DNS:${DX_SEARCH_RELEASE}-open-search-data.${DX_NAMESPACE}.svc.cluster.local,\
DNS:localhost,IP:127.0.0.1
EOF

generate_cert "node" "/C=US/O=ORG/OU=UNIT/CN=opensearch-node" "$NODE_SAN"

# ── Client cert — used by the search middleware ────────────────────────────────

generate_cert "client" "/C=US/O=ORG/OU=UNIT/CN=opensearch-client"

# ── Create k8s secrets (idempotent) ───────────────────────────────────────────

echo ""
echo "Creating OpenSearch TLS secrets in namespace '${DX_NAMESPACE}'..."

kubectl create secret generic search-admin-cert \
    --namespace "$DX_NAMESPACE" \
    --from-file=root-ca.pem="${CERT_DIR}/root-ca.pem" \
    --from-file=admin.pem="${CERT_DIR}/admin.pem" \
    --from-file=admin-key.pem="${CERT_DIR}/admin-key.pem" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic search-node-cert \
    --namespace "$DX_NAMESPACE" \
    --from-file=root-ca.pem="${CERT_DIR}/root-ca.pem" \
    --from-file=node.pem="${CERT_DIR}/node.pem" \
    --from-file=node-key.pem="${CERT_DIR}/node-key.pem" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic search-client-cert \
    --namespace "$DX_NAMESPACE" \
    --from-file=root-ca.pem="${CERT_DIR}/root-ca.pem" \
    --from-file=client.pem="${CERT_DIR}/client.pem" \
    --from-file=client-key.pem="${CERT_DIR}/client-key.pem" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "OpenSearch TLS secrets created."
echo "Admin DN : CN=A,OU=UNIT,O=ORG,C=US"
