#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="local.env"

if [[ ! -f "$LOCAL_ENV" ]]; then
    echo "Error: local.env not found." >&2
    exit 1
fi

# shellcheck source=local.env
source "$LOCAL_ENV"

DX_NAMESPACE="${DX_NAMESPACE:-dxns}"
DX_RELEASE="${DX_RELEASE:-dx}"

if ! kubectl get namespace "$DX_NAMESPACE" &>/dev/null; then
    echo "Error: namespace '$DX_NAMESPACE' does not exist." >&2
    echo "  Run 'make configure-dx' to create it first." >&2
    exit 1
fi

echo "Applying Traefik TCP passthrough route for HCL DX..."

kubectl apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: dx-haproxy-passthrough
  namespace: ${DX_NAMESPACE}
spec:
  entryPoints:
    - websecure
  routes:
    - match: HostSNI(\`localhost\`)
      services:
        - name: ${DX_RELEASE}-haproxy
          port: 443
  tls:
    passthrough: true
EOF

echo ""
echo "Done. HCL DX is accessible at: https://localhost/wps/portal"
echo "  Traffic path: browser → k3d lb:443 → Traefik (TCP passthrough) → dx-haproxy:443 → WAS"
