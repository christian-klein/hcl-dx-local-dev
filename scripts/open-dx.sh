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
DX_CONTEXT_ROOT="${DX_CONTEXT_ROOT:-/wps/portal}"

# Traffic path:
#   Browser → https://localhost (port 443, k3d host mapping)
#   → k3d lb → Traefik websecure entrypoint
#   → IngressRouteTCP passthrough (HostSNI: localhost)
#   → dx-haproxy service:443
#   → HAProxy pod → WAS core:10042
#
# Traefik TCP passthrough preserves TLS so HAProxy terminates it.
# The browser sends Host: localhost (no port, since 443 is the HTTPS default),
# which WAS's extractHostHeaderPort reads as no explicit port and matches its
# wildcard virtual host alias.

URL="https://localhost${DX_CONTEXT_ROOT}"

if ! kubectl get svc dx-haproxy -n "$DX_NAMESPACE" &>/dev/null; then
    echo "Error: dx-haproxy service not found in namespace '${DX_NAMESPACE}'." >&2
    echo "  Run 'make install-dx' first." >&2
    exit 1
fi

if ! kubectl get ingressroutetcp dx-haproxy-passthrough -n "$DX_NAMESPACE" &>/dev/null; then
    echo "Error: Traefik IngressRouteTCP 'dx-haproxy-passthrough' not found in namespace '${DX_NAMESPACE}'." >&2
    echo "  Run 'make configure-dx-ingress' to create it." >&2
    exit 1
fi

echo "HCL DX is accessible at: ${URL}"
echo "  (accept the self-signed certificate warning in your browser)"
echo ""

if command -v xdg-open &>/dev/null; then
    xdg-open "$URL"
elif command -v open &>/dev/null; then
    open "$URL"
else
    echo "Open the URL above in your browser."
fi
