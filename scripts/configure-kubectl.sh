#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-hcl-dx}"
CONTEXT="k3d-${CLUSTER_NAME}"

# ── Set active context ─────────────────────────────────────────────────────────

echo "Setting kubectl context to '${CONTEXT}'..."

if ! kubectl config get-contexts "${CONTEXT}" &>/dev/null; then
    echo "Error: context '${CONTEXT}' not found in kubeconfig." >&2
    echo "Make sure the cluster exists: make configure-k3d" >&2
    exit 1
fi

kubectl config use-context "${CONTEXT}"

# ── Verify connectivity ────────────────────────────────────────────────────────

echo ""
echo -n "Verifying cluster connectivity... "
if kubectl cluster-info &>/dev/null; then
    echo "OK"
else
    echo "FAILED"
    echo "The cluster context is set but the API server is unreachable." >&2
    echo "Start the cluster with: make start" >&2
    exit 1
fi

echo ""
kubectl cluster-info
echo ""

# ── Shell completions ──────────────────────────────────────────────────────────

# Bash
if [[ -d /etc/bash_completion.d ]]; then
    kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null
    echo "Bash completion installed: /etc/bash_completion.d/kubectl"
fi

# Fish
if command -v fish &>/dev/null; then
    FISH_COMP_DIR="${HOME}/.config/fish/completions"
    mkdir -p "$FISH_COMP_DIR"
    kubectl completion fish > "${FISH_COMP_DIR}/kubectl.fish"
    echo "Fish completion installed: ${FISH_COMP_DIR}/kubectl.fish"
fi

echo ""
echo "kubectl context: $(kubectl config current-context)"
echo "kubectl is configured and ready."
