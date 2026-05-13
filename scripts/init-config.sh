#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="local.env"

[[ -f "$LOCAL_ENV" ]] && exit 0

cat > "$LOCAL_ENV" <<'EOF'
# local.env — project-local configuration, not tracked in git.
# Edit values here directly; run the relevant make targets to apply them.

# ── Registry ───────────────────────────────────────────────────────────────────
# HCL Harbor credentials. HCL_PASS is the CLI secret from your Harbor profile,
# not your HCL account password.
HCL_REGISTRY=hclcr.io
HCL_USER=
HCL_PASS=

# ── k3d Cluster ────────────────────────────────────────────────────────────────
# Run 'make analyze-resources' to auto-detect recommended values from your hardware.
CLUSTER_NAME=hcl-dx
K3D_SERVERS=1
K3D_AGENTS=2
K3D_CPUS=4
K3D_MEMORY=8g

# ── HCL DX ─────────────────────────────────────────────────────────────────────
# Run 'make configure-dx' to set these interactively.
# DX_VERSION must be set before running 'make install-dx'.
DX_VERSION=
DX_NAMESPACE=dxns
DX_RELEASE=dx
DX_REGISTRY_SECRET=dx-harbor
# Editor opened by 'make install-dx' for reviewing the custom values file.
EDITOR=vi

# HCL DX Search v2 — separate Helm chart, installed independently.
DX_SEARCH_VERSION=
DX_SEARCH_RELEASE=dx-search
EOF

echo "Created local.env with default configuration."
echo "Edit it directly, or run 'make analyze-resources' to set k3d values from your hardware."
