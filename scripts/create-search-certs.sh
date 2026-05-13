#!/usr/bin/env bash
set -euo pipefail

# Generate TLS certificates for OpenSearch and create the required k8s secrets.
# HCL DX Search v2 requires three secrets:
#   search-admin-cert  — used for cluster admin operations; drives adminDn config
#   search-node-cert   — used for inter-node TLS; includes cluster DNS SANs
#   search-client-cert — used by the search middleware connecting to OpenSearch

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
        -out "${CERT_DIR}/root-ca.pem" \
        -subj "/CN=DX Search Root CA/OU=DX/O=HCL/C=US" 2>/dev/null
    echo "Root CA generated."
fi

# ── Helper: generate a cert signed by the root CA ─────────────────────────────

generate_cert() {
    local name="$1"   # base name: admin, node, client
    local cn="$2"     # Common Name for the cert subject
    local extfile="${3:-}"  # path to a SAN extensions file (empty = no SANs)

    local key="${CERT_DIR}/${name}-key.pem"
    local csr="${CERT_DIR}/${name}.csr"
    local cert="${CERT_DIR}/${name}.pem"

    if [[ -f "$cert" ]]; then
        echo "${name} cert already exists — skipping."
        return
    fi

    echo "Generating ${name} cert..."
    openssl genrsa -out "$key" 2048 2>/dev/null
    openssl req -new -sha256 \
        -key "$key" \
        -out "$csr" \
        -subj "/CN=${cn}/OU=DX/O=HCL/C=US" 2>/dev/null

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

# ── Admin cert ─────────────────────────────────────────────────────────────────

generate_cert "admin" "admin"

# ── Node cert — SANs cover all OpenSearch pod and service DNS names ────────────

NODE_SAN="${CERT_DIR}/node-san.ext"
cat > "$NODE_SAN" <<EOF
subjectAltName=DNS:${DX_SEARCH_RELEASE}-search-master,\
DNS:${DX_SEARCH_RELEASE}-search-master.${DX_NAMESPACE},\
DNS:${DX_SEARCH_RELEASE}-search-master.${DX_NAMESPACE}.svc.cluster.local,\
DNS:${DX_SEARCH_RELEASE}-search-master-headless,\
DNS:${DX_SEARCH_RELEASE}-search-master-headless.${DX_NAMESPACE},\
DNS:${DX_SEARCH_RELEASE}-search-master-headless.${DX_NAMESPACE}.svc.cluster.local,\
DNS:localhost,IP:127.0.0.1
EOF

generate_cert "node" "node" "$NODE_SAN"

# ── Client cert ────────────────────────────────────────────────────────────────

generate_cert "client" "client"

# ── Extract adminDN from the admin cert (RFC2253 subject) ─────────────────────

ADMIN_DN="$(openssl x509 -in "${CERT_DIR}/admin.pem" -noout -subject -nameopt RFC2253 \
    | sed 's/^subject=//')"

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
echo "Admin DN : ${ADMIN_DN}"
