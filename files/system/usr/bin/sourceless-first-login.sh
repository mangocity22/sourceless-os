#!/usr/bin/env bash
set -uo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sourceless"
MARKER="$STATE_DIR/first-login.done"

if [[ -f "$MARKER" ]]; then
    exit 0
fi

mkdir -p "$STATE_DIR"

# Asteapta ca plasmashell sa fie incarcat complet in sesiune
waited=0
while ! pgrep -x plasmashell >/dev/null 2>&1 && (( waited < 30 )); do
    sleep 1
    waited=$((waited + 1))
done
sleep 2

# 1. Aplica tema intunecata
if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
    plasma-apply-colorscheme SourcelessDark >/dev/null 2>&1 || true
fi

# 2. Aplica wallpaper-ul oficial SourceLess
WALLPAPER_DIR="/usr/share/wallpapers/SourceLess"
if [[ -d "$WALLPAPER_DIR" ]] && command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
    plasma-apply-wallpaperimage "$WALLPAPER_DIR" >/dev/null 2>&1 || true
fi

# Daca a ajuns pana aici, marcheaza procesul ca incheiat sa nu mai ruleze din nou
touch "$MARKER"
exit 0