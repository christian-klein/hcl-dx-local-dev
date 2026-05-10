#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE=".k3d-config.env"

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

cat > "${CONFIG_FILE}" <<EOF
K3D_CPUS=${K3D_CPUS}
K3D_MEMORY=${K3D_MEMORY}
K3D_SERVERS=${K3D_SERVERS}
K3D_AGENTS=${K3D_AGENTS}
EOF

echo ""
echo "Saved to ${CONFIG_FILE}:"
echo ""
cat "${CONFIG_FILE}"
echo ""
