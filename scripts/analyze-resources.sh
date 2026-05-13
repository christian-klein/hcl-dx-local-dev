#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV="local.env"

# ── Load current config to preserve non-k3d values ────────────────────────────

HCL_REGISTRY="hclcr.io"
HCL_USER=""
HCL_PASS=""
CLUSTER_NAME="hcl-dx"
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

# ── Detect system resources ────────────────────────────────────────────────────

TOTAL_CPUS=$(nproc)
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_GB=$(( TOTAL_MEM_KB / 1024 / 1024 ))

# ── Calculate recommendations ─────────────────────────────────────────────────
# Reserve 2 CPUs and 4 GB for the host OS.

REC_CPUS=$(( TOTAL_CPUS - 2 ))
(( REC_CPUS < 2 )) && REC_CPUS=2

REC_MEM_GB=$(( TOTAL_MEM_GB - 4 ))
(( REC_MEM_GB < 4 )) && REC_MEM_GB=4

REC_SERVERS=1
REC_AGENTS=2

# ── Display ───────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       System Resource Analysis           ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Detected:"
echo "    CPUs : ${TOTAL_CPUS}"
echo "    RAM  : ${TOTAL_MEM_GB} GB"
echo ""
echo "  Recommended k3d settings (2 CPUs + 4 GB reserved for host):"
echo "    CPUs per node    : ${REC_CPUS}"
echo "    Memory per node  : ${REC_MEM_GB}g"
echo "    Server nodes     : ${REC_SERVERS}"
echo "    Agent nodes      : ${REC_AGENTS}"
echo ""

# ── Prompt ────────────────────────────────────────────────────────────────────

read -rp "Accept recommended settings? [Y/n] " ACCEPT
ACCEPT="${ACCEPT:-Y}"

if [[ "$ACCEPT" =~ ^[Yy]$ ]]; then
    K3D_CPUS="${REC_CPUS}"
    K3D_MEMORY="${REC_MEM_GB}g"
    K3D_SERVERS="${REC_SERVERS}"
    K3D_AGENTS="${REC_AGENTS}"
else
    echo ""
    read -rp "  CPUs per node [${REC_CPUS}]: " K3D_CPUS
    K3D_CPUS="${K3D_CPUS:-${REC_CPUS}}"

    read -rp "  Memory per node (e.g. 8g) [${REC_MEM_GB}g]: " K3D_MEMORY
    K3D_MEMORY="${K3D_MEMORY:-${REC_MEM_GB}g}"

    read -rp "  Server nodes [${REC_SERVERS}]: " K3D_SERVERS
    K3D_SERVERS="${K3D_SERVERS:-${REC_SERVERS}}"

    read -rp "  Agent nodes [${REC_AGENTS}]: " K3D_AGENTS
    K3D_AGENTS="${K3D_AGENTS:-${REC_AGENTS}}"
fi

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
echo "Saved k3d settings to ${LOCAL_ENV}."
