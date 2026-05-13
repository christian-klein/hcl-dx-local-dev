#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="local.env"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Load config ────────────────────────────────────────────────────────────────

if [[ ! -f "$LOCAL_ENV" ]]; then
    echo "Error: local.env not found. Run 'make configure-dx' first." >&2
    exit 1
fi

# shellcheck source=local.env
source "$LOCAL_ENV"

# ── Validate ───────────────────────────────────────────────────────────────────

if [[ -z "${DX_VERSION:-}" ]]; then
    echo "Error: DX_VERSION is not set in local.env." >&2
    exit 1
fi

if [[ -z "${HCL_USER:-}" || -z "${HCL_PASS:-}" ]]; then
    echo "Error: HCL_USER and HCL_PASS must be set in local.env." >&2
    echo "" >&2
    echo "  Add your HCL Harbor credentials to local.env:" >&2
    echo "    HCL_USER=your-email@example.com" >&2
    echo "    HCL_PASS=your-harbor-cli-secret" >&2
    echo "" >&2
    echo "  Harbor CLI secrets are available at https://${HCL_REGISTRY:-hclcr.io} under your profile." >&2
    exit 1
fi

HCL_REGISTRY="${HCL_REGISTRY:-hclcr.io}"
DX_NAMESPACE="${DX_NAMESPACE:-dxns}"
DX_RELEASE="${DX_RELEASE:-dx}"
DX_REGISTRY_SECRET="${DX_REGISTRY_SECRET:-dx-harbor}"
EDITOR="${EDITOR:-vi}"

LOCAL_CHART="charts/${DX_VERSION}/hcl-dx-deployment"
REFERENCE="charts/${DX_VERSION}/dx-values-reference.yaml"
DX_VALUES="charts/${DX_VERSION}/dx-values.yaml"

# ── Step 1: Ensure namespace exists ──────────────────────────────────────────

if kubectl get namespace "$DX_NAMESPACE" &>/dev/null; then
    echo "Namespace '${DX_NAMESPACE}' already exists."
else
    echo "Creating namespace '${DX_NAMESPACE}'..."
    kubectl create namespace "$DX_NAMESPACE"
fi

# ── Step 3: Ensure chart is pulled ────────────────────────────────────────────

if [[ ! -d "$LOCAL_CHART" ]]; then
    echo "Local chart not found. Pulling from registry..."
    echo ""
    bash "${SCRIPT_DIR}/pull-dx-chart.sh"
    echo ""
fi

# ── Step 4: Ensure reference values exist ────────────────────────────────────

if [[ ! -f "$REFERENCE" ]]; then
    echo "Reference values not found. Fetching from local chart..."
    echo ""
    bash "${SCRIPT_DIR}/pull-dx-values.sh"
    echo ""
fi

# ── Step 5: Create custom values file from reference if not present ───────────

if [[ ! -f "$DX_VALUES" ]]; then
    cp "$REFERENCE" "$DX_VALUES"
    echo "Created ${DX_VALUES} from reference file."
fi

# ── Step 6: Open values in editor ────────────────────────────────────────────

echo ""
echo "Opening ${DX_VALUES} in ${EDITOR}."
echo "Customise the values for your environment, then save and exit to continue."
echo ""
read -rp "Press Enter to open the editor (Ctrl+C to abort)..."
"${EDITOR}" "$DX_VALUES"

# ── Step 7: Create image pull secret ─────────────────────────────────────────

echo ""
bash "${SCRIPT_DIR}/create-dx-secret.sh"

# ── Step 8: Helm install or upgrade ──────────────────────────────────────────

if helm status "$DX_RELEASE" -n "$DX_NAMESPACE" &>/dev/null; then
    ACTION="Upgrading"
else
    ACTION="Installing"
fi

echo ""
echo "${ACTION} HCL DX..."
echo "  Release   : ${DX_RELEASE}"
echo "  Namespace : ${DX_NAMESPACE}"
echo "  Version   : ${DX_VERSION}"
echo "  Chart     : ${LOCAL_CHART}"
echo "  Values    : ${DX_VALUES}"
echo ""

helm upgrade --install "$DX_RELEASE" "$LOCAL_CHART" \
    --namespace "$DX_NAMESPACE" \
    -f "$DX_VALUES"

echo ""
echo "${ACTION} submitted. Pods are starting — this can take 20-30 minutes."
echo "  Monitor : k9s -n ${DX_NAMESPACE}"
echo "  Watch   : kubectl get pods -n ${DX_NAMESPACE} -w"
