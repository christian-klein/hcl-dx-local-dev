#!/usr/bin/env bash
set -euo pipefail

K9S_CONFIG_DIR="${HOME}/.config/k9s"
K9S_CONFIG="${K9S_CONFIG_DIR}/config.yaml"

# ── Create config directory ────────────────────────────────────────────────────

mkdir -p "$K9S_CONFIG_DIR"

# ── Write default config ───────────────────────────────────────────────────────

if [[ -f "$K9S_CONFIG" ]]; then
    echo "k9s config already exists: $K9S_CONFIG — skipping."
else
    cat > "$K9S_CONFIG" <<'EOF'
k9s:
  refreshRate: 2
  skipLatestRevCheck: true
  noExitOnCtrlC: false
  readOnly: false
  ui:
    enableMouse: false
    headless: false
    logoless: false
    crumbsless: false
    noIcons: false
  logger:
    tail: 200
    buffer: 5000
    sinceSeconds: 5
    fullScreenLogs: false
    textWrap: false
    showTime: false
  shellPod:
    image: busybox:1.35.0
    namespace: default
    limits:
      cpu: 100m
      memory: 100Mi
EOF
    echo "k9s config written: $K9S_CONFIG"
fi

# ── Shell completions ──────────────────────────────────────────────────────────

# Bash
if [[ -d /etc/bash_completion.d ]]; then
    k9s completion bash | sudo tee /etc/bash_completion.d/k9s > /dev/null
    echo "Bash completion installed: /etc/bash_completion.d/k9s"
fi

# Fish
if command -v fish &>/dev/null; then
    FISH_COMP_DIR="${HOME}/.config/fish/completions"
    mkdir -p "$FISH_COMP_DIR"
    k9s completion fish > "${FISH_COMP_DIR}/k9s.fish"
    echo "Fish completion installed: ${FISH_COMP_DIR}/k9s.fish"
fi

echo ""
echo "k9s is configured. Launch with: k9s"
echo "Config directory: $K9S_CONFIG_DIR"
