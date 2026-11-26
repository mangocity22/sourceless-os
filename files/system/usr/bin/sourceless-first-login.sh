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

# Apply the SourcelessGlass desktop theme and color scheme
if command -v plasma-apply-desktoptheme >/dev/null 2>&1; then
    plasma-apply-desktoptheme SourcelessGlass >/dev/null 2>&1 || true
fi
if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
    plasma-apply-colorscheme SourcelessGlass >/dev/null 2>&1 || plasma-apply-colorscheme BreezeDark >/dev/null 2>&1 || true
fi

QDBUS="$(command -v qdbus-qt6 || command -v qdbus6 || true)"

# Wait up to 10 seconds for plasmashell to register on DBus
if [[ -n "$QDBUS" ]]; then
    for i in {1..20}; do
        if "$QDBUS" org.kde.plasmashell /PlasmaShell >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
    done

    # Ensure bottom panels keep floating + windows-go-below behavior on first session initialization
    "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
var ps = panels();
for (var i = 0; i < ps.length; i++) {
    if (ps[i].location === "bottom") {
        ps[i].floating = true;
        ps[i].hiding = "windowsgobelow";
        ps[i].height = 52;
    }
}
' >/dev/null 2>&1 || true

    "$QDBUS" org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
fi

WALLPAPER_TARGET="/usr/share/wallpapers/SourceLess/contents/images_dark/3840x2160.jpg"
if [[ -f "$WALLPAPER_TARGET" ]] && command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
    plasma-apply-wallpaperimage "$WALLPAPER_TARGET" >/dev/null 2>&1 || true
fi

touch "$MARKER"
exit 0