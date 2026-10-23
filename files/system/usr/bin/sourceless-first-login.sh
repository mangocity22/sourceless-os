#!/usr/bin/env bash
set -uo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sourceless"
MARKER="$STATE_DIR/first-login.done"

if [[ -f "$MARKER" ]]; then
    exit 0
fi

mkdir -p "$STATE_DIR"

# Wait for the graphical session to be fully initialized (up to 30 seconds)
waited=0
while ! pgrep -x plasmashell >/dev/null 2>&1 && (( waited < 30 )); do
    sleep 1
    waited=$((waited + 1))
done
sleep 2

# Apply the BreezeDark theme for security
if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
    plasma-apply-colorscheme BreezeDark >/dev/null 2>&1 || true
fi

# Apply the wallpaper only if the file exists physically on disk
WALLPAPER_DIR="/usr/share/wallpapers/SourceLess"
if [[ -f "$WALLPAPER_DIR/contents/images/3840x2160.png" ]] && command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
    plasma-apply-wallpaperimage "$WALLPAPER_DIR" >/dev/null 2>&1 || true
fi

WALLPAPER_IMG="/usr/share/wallpapers/SourceLess/contents/images/3840x2160.png"

if [[ -f "$WALLPAPER_IMG" ]] && command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
    plasma-apply-wallpaperimage "$WALLPAPER_IMG" >/dev/null 2>&1 || true
fi

touch "$MARKER"
exit 0