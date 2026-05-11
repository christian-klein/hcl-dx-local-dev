#!/usr/bin/env bash
set -euo pipefail

# Always run relative to the project root (where the Makefile lives)
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null \
    || realpath "$(dirname "$0")/..")"
cd "$ROOT"

# ── Parse Makefile: group headers (##@) and documented targets (##) ───────────

NAMES=()
DESCS=()
TARGET_GROUPS=()

current_group=""
while IFS= read -r line; do
    if [[ "$line" =~ ^##@[[:space:]]+(.*) ]]; then
        current_group="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^([a-zA-Z0-9_-]+):.*##[[:space:]]+(.*) ]]; then
        name="${BASH_REMATCH[1]}"
        [[ "$name" == "menu" ]] && continue
        NAMES+=("$name")
        DESCS+=("${BASH_REMATCH[2]}")
        TARGET_GROUPS+=("$current_group")
    fi
done < Makefile

if [[ ${#NAMES[@]} -eq 0 ]]; then
    echo "No documented targets found in Makefile." >&2
    exit 1
fi

# ── fzf path ──────────────────────────────────────────────────────────────────

if command -v fzf &>/dev/null; then
    MENU=""
    prev_group=""
    for i in "${!NAMES[@]}"; do
        group="${TARGET_GROUPS[$i]}"
        if [[ "$group" != "$prev_group" ]]; then
            [[ -n "$MENU" ]] && MENU+=$'\n'
            MENU+="  ── $group"$'\n'
            prev_group="$group"
        fi
        MENU+="$(printf '     %-23s  %s' "${NAMES[$i]}" "${DESCS[$i]}")"$'\n'
    done

    SELECTED=$(printf '%s' "$MENU" | fzf \
        --prompt="▶  " \
        --height=60% \
        --border=rounded \
        --layout=reverse \
        --header=" hcl-dx-local-dev  |  ↑↓ navigate   enter select   esc quit" \
        --header-first \
        --no-sort \
        --bind 'enter:transform:printf "%s" {} | grep -q "^  ── " && echo ignore || echo accept') || exit 0

    [[ -z "$SELECTED" ]] && exit 0
    TARGET=$(awk '{print $1}' <<< "$SELECTED")

# ── Numbered-list fallback (no fzf) ───────────────────────────────────────────

else
    echo ""
    printf "  %-4s  %-25s  %s\n" "No." "Target" "Description"
    printf "  %s\n" "$(printf '─%.0s' {1..70})"

    num=0
    prev_group=""
    for i in "${!NAMES[@]}"; do
        group="${TARGET_GROUPS[$i]}"
        if [[ "$group" != "$prev_group" ]]; then
            echo ""
            printf "  ── %s\n" "$group"
            prev_group="$group"
        fi
        num=$(( num + 1 ))
        printf "  %-4s  %-25s  %s\n" "$num)" "${NAMES[$i]}" "${DESCS[$i]}"
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
