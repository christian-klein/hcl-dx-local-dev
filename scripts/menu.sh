#!/usr/bin/env bash
set -euo pipefail

# Always run relative to the project root (where the Makefile lives)
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null \
    || realpath "$(dirname "$0")/..")"
cd "$ROOT"

# ── Parse documented targets from Makefile ────────────────────────────────────
# Matches lines of the form:  target-name: [prereqs] ## Description

NAMES=()
DESCS=()

while IFS= read -r line; do
    if [[ "$line" =~ ^([a-zA-Z0-9_-]+):.*##[[:space:]]+(.*) ]]; then
        NAMES+=("${BASH_REMATCH[1]}")
        DESCS+=("${BASH_REMATCH[2]}")
    fi
done < Makefile

if [[ ${#NAMES[@]} -eq 0 ]]; then
    echo "No documented targets found in Makefile." >&2
    exit 1
fi

# ── fzf path ──────────────────────────────────────────────────────────────────

if command -v fzf &>/dev/null; then
    MENU=""
    for i in "${!NAMES[@]}"; do
        MENU+="$(printf '%-25s  %s' "${NAMES[$i]}" "${DESCS[$i]}")"$'\n'
    done

    SELECTED=$(printf '%s' "$MENU" | fzf \
        --prompt="▶  " \
        --height=60% \
        --border=rounded \
        --header=" hcl-dx-local-dev  |  ↑↓ navigate   enter select   esc quit" \
        --header-first \
        --no-sort) || exit 0

    [[ -z "$SELECTED" ]] && exit 0
    TARGET=$(awk '{print $1}' <<< "$SELECTED")

# ── Numbered-list fallback (no fzf) ───────────────────────────────────────────

else
    echo ""
    printf "  %-4s  %-25s  %s\n" "No." "Target" "Description"
    printf "  %s\n" "$(printf '─%.0s' {1..70})"
    for i in "${!NAMES[@]}"; do
        printf "  %-4s  %-25s  %s\n" "$((i+1)))" "${NAMES[$i]}" "${DESCS[$i]}"
    done
    echo ""
    read -rp "Select a target (number, or q to quit): " CHOICE

    [[ "$CHOICE" == "q" || "$CHOICE" == "Q" ]] && exit 0

    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || (( CHOICE < 1 || CHOICE > ${#NAMES[@]} )); then
        echo "Invalid selection: '$CHOICE'" >&2
        exit 1
    fi
    TARGET="${NAMES[$((CHOICE - 1))]}"
fi

echo ""
echo "▶  make $TARGET"
echo ""
exec make "$TARGET"
