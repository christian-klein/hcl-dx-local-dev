#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="local.env"

# ── Load current config to preserve non-DX values ─────────────────────────────

HCL_REGISTRY="hclcr.io"
HCL_USER=""
HCL_PASS=""
CLUSTER_NAME="hcl-dx"
K3D_SERVERS="1"
K3D_AGENTS="2"
K3D_CPUS="4"
K3D_MEMORY="8g"
DX_VERSION=""
DX_NAMESPACE="dxns"
DX_RELEASE="dx"
DX_REGISTRY_SECRET="dx-harbor"
EDITOR="vi"
DX_SEARCH_VERSION=""
DX_SEARCH_RELEASE="dx-search"

if [[ -f "$LOCAL_ENV" ]]; then
    # shellcheck source=local.env
    source "$LOCAL_ENV"
fi

# ── Cluster reachability check ─────────────────────────────────────────────────

if ! kubectl cluster-info &>/dev/null; then
    echo "Error: kubectl cannot reach the cluster." >&2
    echo "  Run 'make configure-k3d' and 'make start' first." >&2
    exit 1
fi

# ── Gather DX settings ────────────────────────────────────────────────────────

echo ""
echo "HCL DX deployment configuration"
echo "  Chart: oci://hclcr.io/dx/hcl-dx-deployment"
echo ""

read -rp "  Chart version (e.g. 2.3.0) [${DX_VERSION}]: " input
DX_VERSION="${input:-${DX_VERSION}}"
if [[ -z "$DX_VERSION" ]]; then
    echo "Error: chart version is required." >&2
    exit 1
fi

read -rp "  Kubernetes namespace [${DX_NAMESPACE}]: " input
DX_NAMESPACE="${input:-${DX_NAMESPACE}}"

read -rp "  Helm release name [${DX_RELEASE}]: " input
DX_RELEASE="${input:-${DX_RELEASE}}"

# ── Save ──────────────────────────────────────────────────────────────────────

cat > "$LOCAL_ENV" <<EOF
# local.env — project-local configuration, not tracked in git.
# Edit values here directly; run the relevant make targets to apply them.

# ── Registry ───────────────────────────────────────────────────────────────────
# HCL Harbor credentials. HCL_PASS is the CLI secret from your Harbor profile,
# not your HCL account password.
HCL_REGISTRY=${HCL_REGISTRY}
HCL_USER=${HCL_USER}
HCL_PASS=${HCL_PASS}

# ── k3d Cluster ────────────────────────────────────────────────────────────────
# Run 'make analyze-resources' to auto-detect recommended values from your hardware.
CLUSTER_NAME=${CLUSTER_NAME}
K3D_SERVERS=${K3D_SERVERS}
K3D_AGENTS=${K3D_AGENTS}
K3D_CPUS=${K3D_CPUS}
K3D_MEMORY=${K3D_MEMORY}

# ── HCL DX ─────────────────────────────────────────────────────────────────────
# Run 'make configure-dx' to set these interactively.
# DX_VERSION must be set before running 'make install-dx'.
DX_VERSION=${DX_VERSION}
DX_NAMESPACE=${DX_NAMESPACE}
DX_RELEASE=${DX_RELEASE}
DX_REGISTRY_SECRET=${DX_REGISTRY_SECRET}
# Editor opened by 'make install-dx' for reviewing the custom values file.
EDITOR=${EDITOR}

# HCL DX Search v2 — separate Helm chart, installed independently.
DX_SEARCH_VERSION=${DX_SEARCH_VERSION}
DX_SEARCH_RELEASE=${DX_SEARCH_RELEASE}
EOF

echo ""
echo "Saved DX settings to ${LOCAL_ENV}."

# ── Create namespace ───────────────────────────────────────────────────────────

if kubectl get namespace "$DX_NAMESPACE" &>/dev/null; then
    echo "Namespace '$DX_NAMESPACE' already exists. Skipping."
else
    kubectl create namespace "$DX_NAMESPACE"
    echo "Created namespace '$DX_NAMESPACE'."
fi

echo ""
echo "Next steps:"
echo "  1. Set HCL_USER and HCL_PASS in local.env."
echo "  2. Run 'make pull-dx-chart' then 'make pull-dx-values' to get the chart locally."
echo "  3. Edit charts/${DX_VERSION}/dx-values.yaml to customise the deployment."
echo "  4. Run: make install-dx"
