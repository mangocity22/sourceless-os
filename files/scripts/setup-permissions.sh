#!/usr/bin/bash
# =============================================================================
# Sourceless-OS Build-Time Security and System Branding Setup
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# 1. Terminal Lockdown & Execution Isolation
# -----------------------------------------------------------------------------

if [ -f /usr/bin/konsole ] && [ ! -f /usr/bin/konsole.real ]; then
    echo "[Sourceless] Relocating original Konsole binary..."
    mv /usr/bin/konsole /usr/bin/konsole.real
else
    echo "[Sourceless] Original Konsole binary not found or already relocated. Skipping."
fi

echo "[Sourceless] Generating Konsole security wrapper..."
cat << 'EOF' > /usr/bin/konsole
#!/usr/bin/bash

if [ -f /tmp/sourceless_support_active ] || [ -f /var/run/sourceless_support_active ]; then
    exec /usr/bin/konsole.real "$@"
else
    kdialog --error "Access Denied. Terminal execution is restricted on Sourceless-OS." --title "Security Policy"
    exit 1
fi
EOF

# Unhide native Konsole desktop launcher
KONSOLE_DESKTOP="/usr/share/applications/org.kde.konsole.desktop"
if [[ -f "$KONSOLE_DESKTOP" ]]; then
    echo "[Sourceless] Unhiding Konsole desktop entry..."
    sed -i '/^NoDisplay=/d' "$KONSOLE_DESKTOP" 2>/dev/null || true
    sed -i 's/^Hidden=.*/Hidden=false/' "$KONSOLE_DESKTOP" 2>/dev/null || true
fi

# Force global Starship config for all users
if ! grep -q "STARSHIP_CONFIG" /etc/bashrc; then
    echo 'export STARSHIP_CONFIG="/etc/starship.toml"' >> /etc/bashrc
fi

# Ensure starship initializes if not already appended
if ! grep -q "starship init bash" /etc/bashrc; then
    echo 'eval "$(starship init bash)"' >> /etc/bashrc
fi

# -----------------------------------------------------------------------------
# Force native Konsole visible and mask Flatpak Konsole
# -----------------------------------------------------------------------------
KONSOLE_DESKTOP="/usr/share/applications/org.kde.konsole.desktop"
if [[ -f "$KONSOLE_DESKTOP" ]]; then
    sed -i '/^NoDisplay=/d' "$KONSOLE_DESKTOP" 2>/dev/null || true
    sed -i 's/^Hidden=.*/Hidden=false/' "$KONSOLE_DESKTOP" 2>/dev/null || true
fi

# Previne instalarea sau suprascrierea de catre utilizator a versiunii Flatpak
flatpak mask org.kde.konsole 2>/dev/null || true

chmod +x /usr/bin/konsole

# -----------------------------------------------------------------------------
# 2. System Permissions and Security Access Controls
# -----------------------------------------------------------------------------

chmod 700 /usr/bin/sourceless-unlock 2>/dev/null || true
chmod 700 /usr/bin/sourceless-client-boot.sh 2>/dev/null || true
chmod 644 /etc/profile.d/sourceless-shell-guard.sh 2>/dev/null || true
chmod +x /etc/grub.d/40_custom_sourceless 2>/dev/null || true

chmod 0440 /etc/sudoers.d/sourceless-lockdown 2>/dev/null || true
chmod 0644 /etc/polkit-1/rules.d/10-sourceless-security.rules 2>/dev/null || true

chmod 755 /usr/bin/sourceless-emergency-terminal 2>/dev/null || true
chmod 644 /usr/share/applications/sourceless-emergency-terminal.desktop 2>/dev/null || true

mkdir -p /etc/sourceless
chown root:users /etc/sourceless 2>/dev/null || true
chmod 775 /etc/sourceless 2>/dev/null || true

chmod 755 /usr/bin/sourceless-autoupdate 2>/dev/null || true
chmod +x /usr/bin/sourceless-first-login.sh 2>/dev/null || true

chmod +x /usr/bin/sourceless-fix-home.sh 2>/dev/null || true

# -----------------------------------------------------------------------------
# 3. User Privilege and Clean Home Directory Permissions
# -----------------------------------------------------------------------------

systemctl --global mask kdeconnectd.service 2>/dev/null || true

if id "sourceless" &>/dev/null; then
    gpasswd -d sourceless wheel 2>/dev/null || true
    usermod -g sourceless -G users sourceless 2>/dev/null || true
fi

# Set skeleton permissions without breaking user ~/.config ownership
mkdir -p /etc/skel/.config
chmod 755 /etc/skel/.config
mkdir -p /etc/skel/.config/autostart

# Enable runtime ownership repair service
systemctl enable sourceless-fix-home.service 2>/dev/null || true

# Fix permissions across standard skeleton directory
mkdir -p /etc/skel/.config
chmod 755 /etc/skel/.config
mkdir -p /etc/skel/.config/autostart
chmod 755 /etc/skel/.config/autostart

# Pre-apply numeric UID 1000 ownership to any existing home tree
if [ -d "/var/home/sourceless" ]; then
    chown -R 1000:1000 /var/home/sourceless 2>/dev/null || true
    chmod 755 /var/home/sourceless/.config 2>/dev/null || true
fi

# Ensure /var/home permissions are safe and fully writable by the user
if [ -d "/var/home/sourceless" ]; then
    mkdir -p /var/home/sourceless/.config
    chmod 755 /var/home/sourceless/.config
    mkdir -p /var/home/sourceless/.config/autostart
    chmod 555 /var/home/sourceless/.config/autostart
    chown -R sourceless:users /var/home/sourceless 2>/dev/null || true
fi

# Neutralize sudo privileges for wheel group
sed -i 's/^%wheel\s\+ALL=(ALL)\s\+ALL/# %wheel ALL=(ALL) ALL/' /etc/sudoers 2>/dev/null || true

# -----------------------------------------------------------------------------
# 4. Secure Flatpak Configuration & PackageKit Removal
# -----------------------------------------------------------------------------

echo "[Sourceless] Configuring secure Flatpak remotes..."
flatpak remote-add --system --if-not-exists fedora oci+https://registry.fedoraproject.org 2>/dev/null || true
flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
flatpak remote-modify --system --subset=verified flathub 2>/dev/null || true

chmod 755 /var/lib/flatpak 2>/dev/null || true

echo "[Sourceless] Purging PackageKit backend from Discover..."
rpm -e --nodeps plasma-discover-packagekit plasma-discover-offline-updates 2>/dev/null || true
rm -f /usr/lib64/qt6/plugins/discover/packagekit-backend.so 2>/dev/null || true
rm -f /usr/share/dbus-1/system-services/org.freedesktop.PackageKit.service 2>/dev/null || true

# -----------------------------------------------------------------------------
# 5. Security Daemons & Services Configuration
# -----------------------------------------------------------------------------

chmod 755 /usr/bin/sourceless-guard 2>/dev/null || true
chmod 755 /usr/bin/sourceless-downloads-watcher 2>/dev/null || true
chmod 755 /usr/bin/sourceless-sandbox 2>/dev/null || true

mkdir -p /var/quarantine
chmod 700 /var/quarantine

systemctl enable sourceless-client.service 2>/dev/null || true
systemctl enable freshclam.service 2>/dev/null || true
systemctl enable clamd@scan.service 2>/dev/null || true
systemctl enable sourceless-shield.service 2>/dev/null || true
systemctl enable systemd-resolved.service 2>/dev/null || true

systemctl mask fedora-atomic-desktop-appstream-cache-refresh.service 2>/dev/null || true
systemctl enable rustdesk.service 2>/dev/null || true

sed -i 's|^#LocalSocket /run/clamd.scan/clamd.sock|LocalSocket /run/clamd.scan/clamd.sock|' /etc/clamd.d/scan.conf 2>/dev/null || true

# -----------------------------------------------------------------------------
# 6. Official OS Release Identification (/usr/lib/os-release and /etc/os-release)
# -----------------------------------------------------------------------------

echo "[Sourceless] Patching OS release metadata..."
for os_target in /usr/lib/os-release /etc/os-release; do
    if [[ -f "$os_target" || -L "$os_target" ]]; then
        sed -i 's/^NAME=.*/NAME="Sourceless OS"/' "$os_target" 2>/dev/null || true
        sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Sourceless OS"/' "$os_target" 2>/dev/null || true
        sed -i 's/^ID=.*/ID=sourceless/' "$os_target" 2>/dev/null || true
        
        if grep -q "^ID_LIKE=" "$os_target"; then
            sed -i 's/^ID_LIKE=.*/ID_LIKE="fedora"/' "$os_target" 2>/dev/null || true
        else
            echo 'ID_LIKE="fedora"' >> "$os_target"
        fi

        sed -i 's/^HOME_URL=.*/HOME_URL="https:\/\/sourceless.net"/' "$os_target" 2>/dev/null || true
        sed -i 's/^DOCUMENTATION_URL=.*/DOCUMENTATION_URL="https:\/\/sourceless.net"/' "$os_target" 2>/dev/null || true
        sed -i 's/^SUPPORT_URL=.*/SUPPORT_URL="https:\/\/sourceless.net"/' "$os_target" 2>/dev/null || true
        sed -i 's/^BUG_REPORT_URL=.*/BUG_REPORT_URL="https:\/\/sourceless.net"/' "$os_target" 2>/dev/null || true
        sed -i 's/^LOGO=.*/LOGO=sourceless-logo/' "$os_target" 2>/dev/null || true
        sed -i 's/^DEFAULT_HOSTNAME=.*/DEFAULT_HOSTNAME=sourceless/' "$os_target" 2>/dev/null || true
    fi
done

chmod 644 /etc/xdg/kcm-about-distrorc 2>/dev/null || true

# -----------------------------------------------------------------------------
# 7. GRUB Bootloader Configuration & Compilation
# -----------------------------------------------------------------------------

echo "[Sourceless] Configuring GRUB theme and compiling configuration..."
if [[ -f /etc/default/grub ]]; then
    sed -i 's|^GRUB_THEME=.*|GRUB_THEME="/usr/share/grub/themes/sourceless/theme.txt"|' /etc/default/grub 2>/dev/null || true
    if ! grep -q "^GRUB_THEME=" /etc/default/grub; then
        echo 'GRUB_THEME="/usr/share/grub/themes/sourceless/theme.txt"' >> /etc/default/grub
    fi
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub 2>/dev/null || true
    sed -i 's/^GRUB_TERMINAL_OUTPUT=.*/GRUB_TERMINAL_OUTPUT="gfxterm"/' /etc/default/grub 2>/dev/null || true
fi

THEME_DIR="/usr/share/grub/themes/sourceless"
if [[ -d "$THEME_DIR" ]]; then
    TTF_SRC=$(find /usr/share/fonts -name "DejaVuSans.ttf" 2>/dev/null | head -n 1)
    if [[ -n "$TTF_SRC" ]] && command -v grub2-mkfont >/dev/null 2>&1; then
        grub2-mkfont -s 16 -n "Sourceless Regular" -o "$THEME_DIR/font-16.pf2" "$TTF_SRC" 2>/dev/null || true
        grub2-mkfont -s 14 -n "Sourceless Regular" -o "$THEME_DIR/font-14.pf2" "$TTF_SRC" 2>/dev/null || true
    fi
    if [[ ! -f "$THEME_DIR/font-16.pf2" && -f /usr/share/grub/unicode.pf2 ]]; then
        cp -f /usr/share/grub/unicode.pf2 "$THEME_DIR/font-16.pf2" 2>/dev/null || true
    fi
fi

THEME_DIR="/boot/grub2/themes/sourceless"
if [[ -d "$THEME_DIR" && -f /usr/share/grub/unicode.pf2 ]]; then
    cp -f /usr/share/grub/unicode.pf2 "$THEME_DIR/unicode.pf2" 2>/dev/null || true
fi

# Regenerate GRUB config so the theme is baked into bootloader
if command -v grub2-mkconfig >/dev/null 2>&1; then
    echo "[Sourceless] Running grub2-mkconfig..."
    grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
    if [[ -d /boot/efi/EFI/fedora ]]; then
        grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg 2>/dev/null || true
    fi
fi

# -----------------------------------------------------------------------------
# 8. Wallpaper Packaging & Safe Global KDE Enforcement
# -----------------------------------------------------------------------------

echo "[Sourceless] Applying custom wallpapers safely..."
WALLPAPER_DARK="/usr/share/wallpapers/SourceLess/contents/images_dark/3840x2160.png"

if [[ -f "$WALLPAPER_DARK" ]]; then
    # Overwrite images inside default KDE packages WITHOUT touching metadata.json
    for pkg in Waterfall Next Breeze; do
        PKG_DIR="/usr/share/wallpapers/$pkg"
        if [[ -d "$PKG_DIR" ]]; then
            mkdir -p "$PKG_DIR/contents/images"
            mkdir -p "$PKG_DIR/contents/images_dark"
            for size in 3840x2160.png 5120x2880.png 1920x1080.png; do
                cp -f "$WALLPAPER_DARK" "$PKG_DIR/contents/images/$size" 2>/dev/null || true
                cp -f "$WALLPAPER_DARK" "$PKG_DIR/contents/images_dark/$size" 2>/dev/null || true
            done
        fi
    done
fi

# Ensure SourceLess package itself has a valid metadata.json for Plasma 6
mkdir -p /usr/share/wallpapers/SourceLess
cat << 'EOF' > /usr/share/wallpapers/SourceLess/metadata.json
{
    "KPlugin": {
        "Id": "SourceLess",
        "Name": "SourceLess Dark"
    }
}
EOF
chmod 644 /usr/share/wallpapers/SourceLess/metadata.json 2>/dev/null || true

# -----------------------------------------------------------------------------
# Lock Screen (KScreenLocker) & SDDM Branding Enforcement
# -----------------------------------------------------------------------------
WALLPAPER_DARK="/usr/share/wallpapers/SourceLess/contents/images_dark/3840x2160.png"

# 1. Fortam wallpaper-ul pe Lock Screen la nivel global de sistem
mkdir -p /etc/xdg
cat << 'EOF' > /etc/xdg/kscreenlockerrc
[Greeter]
WallpaperPlugin=org.kde.image

[Greeter][Wallpaper][org.kde.image][General]
Image=/usr/share/wallpapers/SourceLess/contents/images_dark/3840x2160.png
PreviewImage=/usr/share/wallpapers/SourceLess/contents/images_dark/3840x2160.png
EOF
chmod 644 /etc/xdg/kscreenlockerrc 2>/dev/null || true

# Replicam si in skeleton pentru orice profil nou de utilizator
mkdir -p /etc/skel/.config
cp -f /etc/xdg/kscreenlockerrc /etc/skel/.config/kscreenlockerrc 2>/dev/null || true

# 2. Fortam wallpaper-ul pe ecranul de login SDDM (tema Breeze)
for sddm_theme in /usr/share/sddm/themes/*; do
    if [[ -d "$sddm_theme" ]]; then
        cat << EOF > "$sddm_theme/theme.conf.user"
[General]
background=$WALLPAPER_DARK
EOF
    fi
done

# -----------------------------------------------------------------------------
# Clean purge of upstream KDE wallpapers while keeping ALL Sourceless assets
# -----------------------------------------------------------------------------
echo "[Sourceless] Cleaning upstream wallpapers and protecting custom packages..."

# Stergem imaginile upstream generice din /usr/share/backgrounds (cele de Fedora/GNOME)
rm -rf /usr/share/backgrounds/* 2>/dev/null || true

# Lista neagră cu tapetele native KDE care trebuie suprascrise/eliminate
UPSTREAM_DEFAULTS=("Waterfall" "Next" "Breeze" "Altai" "Flow" "Shell" "Opal" "Kay")

# Calea către pachetul principal de fallback
MAIN_TARGET="/usr/share/wallpapers/SourceLess"

# 1. Eliminăm strict pachetele upstream cunoscute și le redirecționăm către tema principală
for wp in "${UPSTREAM_DEFAULTS[@]}"; do
    WP_PATH="/usr/share/wallpapers/$wp"
    if [[ -d "$WP_PATH" || -L "$WP_PATH" ]]; then
        rm -rf "$WP_PATH"
        # Punem symlink doar peste cele implicite ca să nu crăpe Plasma când le caută
        if [[ -d "$MAIN_TARGET" ]]; then
            ln -sf "$MAIN_TARGET" "$WP_PATH"
        fi
    fi
done

# 2. Ștergem orice alt folder care NU conține 'sourceless' în nume (case-insensitive)
shopt -s nocasematch
for wp_dir in /usr/share/wallpapers/*; do
    dir_name=$(basename "$wp_dir")
    
    # Dacă numele NU conține 'sourceless' și NU este în lista neagră procesată deja
    if [[ ! "$dir_name" =~ sourceless ]] && [[ ! " ${UPSTREAM_DEFAULTS[*]} " =~ " ${dir_name} " ]]; then
        rm -rf "$wp_dir"
    fi
done
shopt -u nocasematch

# 3. Asigurăm metadata.json valid în FIECARE folder Sourceless rămas
for custom_wp in /usr/share/wallpapers/*; do
    if [[ -d "$custom_wp" && ! -L "$custom_wp" ]]; then
        name=$(basename "$custom_wp")
        if [[ ! -f "$custom_wp/metadata.json" ]]; then
            cat << EOF > "$custom_wp/metadata.json"
{
    "KPlugin": {
        "Id": "$name",
        "Name": "$name"
    }
}
EOF
            chmod 644 "$custom_wp/metadata.json" 2>/dev/null || true
        fi
    fi
done



# Bake Sourceless Dark as the default wallpaper into system-wide kdeglobals
mkdir -p /etc/xdg
cat << 'EOF' >> /etc/xdg/kdeglobals

[Wallpaper]
defaultWallpaperTheme=SourceLess
defaultFile=/usr/share/wallpapers/SourceLess/contents/images_dark/3840x2160.png
EOF

# -----------------------------------------------------------------------------
# 9. Visual Branding & Desktop Icon Overrides
# -----------------------------------------------------------------------------

echo "[Sourceless] Injecting branding icons into Breeze themes..."
START_SRC="/usr/share/icons/hicolor/scalable/apps/start-here.svg"
LOGO_SVG="/usr/share/icons/hicolor/scalable/apps/sourceless-logo.svg"
LOGO_PNG="/usr/share/icons/hicolor/scalable/apps/sourceless-logo.png"
APPS_SRC="/usr/share/icons/breeze/apps/scalable"

if [[ -f "$START_SRC" ]]; then
    for theme in breeze breeze-dark; do
        for size_dir in /usr/share/icons/"$theme"/places/*; do
            if [[ -d "$size_dir" ]]; then
                cp -f "$START_SRC" "$size_dir/start-here-kde-plasma.svg" 2>/dev/null || true
                cp -f "$START_SRC" "$size_dir/start-here-kde.svg" 2>/dev/null || true
                cp -f "$START_SRC" "$size_dir/start-here.svg" 2>/dev/null || true
                cp -f "$START_SRC" "$size_dir/start-here-kde-plasma-symbolic.svg" 2>/dev/null || true
                cp -f "$START_SRC" "$size_dir/start-here-symbolic.svg" 2>/dev/null || true
                cp -f "$START_SRC" "$size_dir/distributor-logo.svg" 2>/dev/null || true
            fi
        done
    done
fi

if [[ -f "$LOGO_SVG" ]]; then
    for theme in breeze breeze-dark; do
        for size_dir in /usr/share/icons/"$theme"/apps/*; do
            if [[ -d "$size_dir" ]]; then
                cp -f "$LOGO_SVG" "$size_dir/sourceless-logo.svg" 2>/dev/null || true
                cp -f "$LOGO_SVG" "$size_dir/distributor-logo.svg" 2>/dev/null || true
                cp -f "$LOGO_SVG" "$size_dir/distributor-logo-fedora.svg" 2>/dev/null || true
                cp -f "$LOGO_SVG" "$size_dir/fedora-logo-icon.svg" 2>/dev/null || true
            fi
        done

        if [[ -d "/usr/share/icons/$theme/places/scalable" ]]; then
            cp -f "$LOGO_SVG" "/usr/share/icons/$theme/places/scalable/distributor-logo.svg" 2>/dev/null || true
            cp -f "$LOGO_SVG" "/usr/share/icons/$theme/places/scalable/distributor-logo-fedora.svg" 2>/dev/null || true
        fi
    done

    cp -f "$LOGO_SVG" /usr/share/icons/hicolor/scalable/apps/distributor-logo.svg 2>/dev/null || true
    cp -f "$LOGO_SVG" /usr/share/icons/hicolor/scalable/apps/distributor-logo-fedora.svg 2>/dev/null || true
    cp -f "$LOGO_SVG" /usr/share/icons/hicolor/scalable/apps/fedora-logo-icon.svg 2>/dev/null || true
    cp -f "$LOGO_SVG" /usr/share/pixmaps/sourceless-logo.svg 2>/dev/null || true
    cp -f "$LOGO_SVG" /usr/share/pixmaps/distributor-logo.svg 2>/dev/null || true
    cp -f "$LOGO_SVG" /usr/share/pixmaps/fedora-logo.svg 2>/dev/null || true
fi

if [[ -f "$LOGO_PNG" ]]; then
    cp -f "$LOGO_PNG" /usr/share/pixmaps/sourceless-logo.png 2>/dev/null || true
    cp -f "$LOGO_PNG" /usr/share/pixmaps/distributor-logo.png 2>/dev/null || true
    cp -f "$LOGO_PNG" /usr/share/pixmaps/fedora-logo.png 2>/dev/null || true
    cp -f "$LOGO_PNG" /usr/share/pixmaps/system-logo-white.png 2>/dev/null || true
fi

if [[ -d "$APPS_SRC" ]]; then
    for theme in breeze breeze-dark; do
        for size_dir in /usr/share/icons/"$theme"/apps/*; do
            if [[ -d "$size_dir" ]]; then
                if [[ -f "$APPS_SRC/org.kde.dolphin.svg" ]]; then
                    cp -f "$APPS_SRC/org.kde.dolphin.svg" "$size_dir/org.kde.dolphin.svg" 2>/dev/null || true
                    cp -f "$APPS_SRC/org.kde.dolphin.svg" "$size_dir/system-file-manager.svg" 2>/dev/null || true
                fi

                if [[ -f "$APPS_SRC/org.kde.konsole.svg" ]]; then
                    cp -f "$APPS_SRC/org.kde.konsole.svg" "$size_dir/utilities-terminal.svg" 2>/dev/null || true
                    cp -f "$APPS_SRC/org.kde.konsole.svg" "$size_dir/org.kde.konsole.svg" 2>/dev/null || true
                fi

                if [[ -f "$APPS_SRC/systemsettings.svg" ]]; then
                    cp -f "$APPS_SRC/systemsettings.svg" "$size_dir/preferences-system.svg" 2>/dev/null || true
                    cp -f "$APPS_SRC/systemsettings.svg" "$size_dir/systemsettings.svg" 2>/dev/null || true
                fi

                if [[ -f "$APPS_SRC/plasmadiscover.svg" ]]; then
                    cp -f "$APPS_SRC/plasmadiscover.svg" "$size_dir/plasmadiscover.svg" 2>/dev/null || true
                    cp -f "$APPS_SRC/plasmadiscover.svg" "$size_dir/org.kde.discover.svg" 2>/dev/null || true
                fi
            fi
        done
    done
fi

# -----------------------------------------------------------------------------
# 10. Rebuild Icon Caches and Desktop Databases
# -----------------------------------------------------------------------------

echo "[Sourceless] Regenerating system icon caches and application metadata..."
update-desktop-database /usr/share/applications 2>/dev/null || true

for theme_dir in /usr/share/icons/*; do
    if [[ -d "$theme_dir" ]]; then
        touch "$theme_dir" 2>/dev/null || true
        gtk-update-icon-cache -f -q "$theme_dir" 2>/dev/null || true
    fi
done

echo "[Sourceless] setup-permissions.sh completed successfully."