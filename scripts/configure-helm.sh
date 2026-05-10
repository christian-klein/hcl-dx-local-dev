#!/usr/bin/env bash
set -euo pipefail

# Traditional Helm repositories — added via `helm repo add`.
# Tracked here so clean-helm can remove them.
REPOS=(
    "bitnami https://charts.bitnami.com/bitnami"
)

# OCI registries — used with oci:// URLs, not added via `helm repo add`.
# Login for each registry is deferred to the tool/chart that requires it
# (e.g. hclcr.io login happens during HCL DX installation).
OCI_REGISTRIES=(
    "hclcr.io oci://hclcr.io"
)

# ── Add repositories ───────────────────────────────────────────────────────────

echo "Configuring Helm repositories..."
echo ""

for entry in "${REPOS[@]}"; do
    NAME="${entry%% *}"
    URL="${entry#* }"

    if helm repo list 2>/dev/null | grep -q "^${NAME}[[:space:]]"; then
        echo "  [exists]  $NAME ($URL)"
    else
        helm repo add "$NAME" "$URL"
        echo "  [added]   $NAME ($URL)"
    fi
done

# ── Update repository index ────────────────────────────────────────────────────

echo ""
echo "Updating repository index..."
helm repo update

# ── Shell completions ──────────────────────────────────────────────────────────

# Bash
if [[ -d /etc/bash_completion.d ]]; then
    helm completion bash | sudo tee /etc/bash_completion.d/helm > /dev/null
    echo "Bash completion installed: /etc/bash_completion.d/helm"
fi

# Fish
if command -v fish &>/dev/null; then
    FISH_COMP_DIR="${HOME}/.config/fish/completions"
    mkdir -p "$FISH_COMP_DIR"
    helm completion fish > "${FISH_COMP_DIR}/helm.fish"
    echo "Fish completion installed: ${FISH_COMP_DIR}/helm.fish"
fi

echo ""
echo "Helm is configured and ready."
echo ""
echo "Traditional repositories:"
helm repo list
echo ""
echo "OCI registries (login required before use):"
for entry in "${OCI_REGISTRIES[@]}"; do
    NAME="${entry%% *}"
    URL="${entry#* }"
    printf "  %-12s %s\n" "$NAME" "$URL"
done
echo ""
echo "  To authenticate before installing HCL DX, run:"
echo "    helm registry login hclcr.io --username <user> --password <token>"
