#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="local.env"

# ── Load config ────────────────────────────────────────────────────────────────

if [[ ! -f "$LOCAL_ENV" ]]; then
    echo "Error: local.env not found." >&2
    exit 1
fi

# shellcheck source=local.env
source "$LOCAL_ENV"

# ── Validate ───────────────────────────────────────────────────────────────────

if [[ -z "${HCL_USER:-}" || -z "${HCL_PASS:-}" ]]; then
    echo "Error: HCL_USER and HCL_PASS must be set in local.env." >&2
    exit 1
fi

HCL_REGISTRY="${HCL_REGISTRY:-hclcr.io}"
DX_NAMESPACE="${DX_NAMESPACE:-dxns}"
DX_REGISTRY_SECRET="${DX_REGISTRY_SECRET:-dx-harbor}"
DX_VERSION="${DX_VERSION:-}"
DX_VALUES="charts/dx/${DX_VERSION}/dx-values.yaml"

# ── Namespace check ────────────────────────────────────────────────────────────

if ! kubectl get namespace "$DX_NAMESPACE" &>/dev/null; then
    echo "Error: namespace '$DX_NAMESPACE' does not exist." >&2
    echo "  Run 'make configure-dx' to create it first." >&2
    exit 1
fi

# ── Create secret (idempotent) ─────────────────────────────────────────────────

echo "Applying image pull secret '${DX_REGISTRY_SECRET}' in namespace '${DX_NAMESPACE}'..."

kubectl create secret docker-registry "$DX_REGISTRY_SECRET" \
    --namespace "$DX_NAMESPACE" \
    --docker-server="$HCL_REGISTRY" \
    --docker-email="$HCL_USER" \
    --docker-username="$HCL_USER" \
    --docker-password="$HCL_PASS" \
    --dry-run=client -o yaml | kubectl apply -f -

# ── Create TLS secret (self-signed, idempotent) ────────────────────────────────

DX_TLS_SECRET="${DX_TLS_SECRET:-dx-tls-cert}"

if kubectl get secret "$DX_TLS_SECRET" -n "$DX_NAMESPACE" &>/dev/null; then
    echo "TLS secret '${DX_TLS_SECRET}' already exists in namespace '${DX_NAMESPACE}'."
else
    echo "Generating self-signed TLS certificate for '${DX_TLS_SECRET}'..."
    _TLS_TMP="$(mktemp -d)"
    trap 'rm -rf "$_TLS_TMP"' EXIT
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -keyout "${_TLS_TMP}/tls.key" \
        -out    "${_TLS_TMP}/tls.crt" \
        -subj   "/CN=localhost/O=hcl-dx-local" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
        2>/dev/null
    kubectl create secret tls "$DX_TLS_SECRET" \
        --namespace "$DX_NAMESPACE" \
        --cert="${_TLS_TMP}/tls.crt" \
        --key="${_TLS_TMP}/tls.key"
    echo "TLS secret '${DX_TLS_SECRET}' created."
fi

# ── Patch dx-values.yaml ───────────────────────────────────────────────────────

if [[ ! -f "$DX_VALUES" ]]; then
    echo ""
    echo "Note: ${DX_VALUES} not found — create it with 'make pull-dx-values', then add:"
    echo "  images:"
    echo "    imagePullSecrets:"
    echo "      - name: \"${DX_REGISTRY_SECRET}\""
    exit 0
fi

SECRET_ENTRY="    - name: \"${DX_REGISTRY_SECRET}\""

if grep -qF "$SECRET_ENTRY" "$DX_VALUES"; then
    echo "imagePullSecrets already contains '${DX_REGISTRY_SECRET}' in ${DX_VALUES}."
elif grep -q "^  imagePullSecrets:$" "$DX_VALUES"; then
    # Empty imagePullSecrets: key — insert the entry on the next line
    sed -i "s|^  imagePullSecrets:$|  imagePullSecrets:\n${SECRET_ENTRY}|" "$DX_VALUES"
    echo "Patched imagePullSecrets in ${DX_VALUES}."
else
    echo ""
    echo "Warning: could not auto-patch imagePullSecrets in ${DX_VALUES}." >&2
    echo "  Add the following manually under the 'images:' key:" >&2
    echo "    imagePullSecrets:" >&2
    echo "      - name: \"${DX_REGISTRY_SECRET}\"" >&2
fi
