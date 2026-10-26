#!/usr/bin/bash
# =============================================================================
# Sourceless-OS Build-Time Security and System Branding Setup
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# 1. Terminal Lockdown & Execution Isolation
# -----------------------------------------------------------------------------

# Defensively verify and isolate the original Konsole binary
if [ -f /usr/bin/konsole ] && [ ! -f /usr/bin/konsole.real ]; then
    echo "[Sourceless] Relocating original Konsole binary..."
    mv /usr/bin/konsole /usr/bin/konsole.real
else
    echo "[Sourceless] Original Konsole binary not found or already relocated. Skipping."
fi

# Generate security trap wrapper for Konsole
echo "[Sourceless] Generating Konsole security wrapper..."
cat << 'EOF' > /usr/bin/konsole
#!/usr/bin/bash

# Verify if an active support session token exists
if [ -f /tmp/sourceless_support_active ] || [ -f /var/run/sourceless_support_active ]; then
    # Support session is active. Grant execution to the technician.
    exec /usr/bin/konsole.real "$@"
else
    # Deny unauthorized interactive terminal launch
    kdialog --error "Access Denied. Terminal execution is restricted on Sourceless-OS." --title "Security Policy"
    exit 1
fi
EOF

chmod +x /usr/bin/konsole

# -----------------------------------------------------------------------------
# 2. System Permissions and Security Access Controls
# -----------------------------------------------------------------------------

# Restrict critical internal scripts to root execution only
chmod 700 /usr/bin/sourceless-unlock 2>/dev/null || true
chmod 700 /usr/bin/sourceless-client-boot.sh 2>/dev/null || true
chmod 644 /etc/profile.d/sourceless-shell-guard.sh 2>/dev/null || true
chmod +x /etc/grub.d/40_custom_sourceless 2>/dev/null || true

# Apply strict permissions on security policies and sudoers
chmod 0440 /etc/sudoers.d/sourceless-lockdown 2>/dev/null || true
chmod 0644 /etc/polkit-1/rules.d/10-sourceless-security.rules 2>/dev/null || true

# Configure offline emergency terminal launcher permissions
chmod 755 /usr/bin/sourceless-emergency-terminal 2>/dev/null || true
chmod 644 /usr/share/applications/sourceless-emergency-terminal.desktop 2>/dev/null || true

# Allow users group to write tamper flag into configuration directory
mkdir -p /etc/sourceless
chown root:users /etc/sourceless 2>/dev/null || true
chmod 775 /etc/sourceless 2>/dev/null || true

chmod 755 /usr/bin/sourceless-autoupdate 2>/dev/null || true
chmod +x /usr/bin/sourceless-first-login.sh 2>/dev/null || true

# -----------------------------------------------------------------------------
# 3. User Privilege Neutralization and Autostart Hardening
# -----------------------------------------------------------------------------

# Mask unnecessary network services (KDE Connect)
systemctl --global mask kdeconnectd.service 2>/dev/null || true

# Revoke administrative privileges from standard user
if id "sourceless" &>/dev/null; then
    gpasswd -d sourceless wheel 2>/dev/null || true
    usermod -g sourceless -G users sourceless 2>/dev/null || true
fi

# Lock down user autostart directory to prevent startup persistence
mkdir -p /etc/skel/.config/autostart
chmod 555 /etc/skel/.config/autostart

if [ -d "/var/home/sourceless" ]; then
    mkdir -p /var/home/sourceless/.config/autostart
    chown root:root /var/home/sourceless/.config/autostart 2>/dev/null || true
    chmod 555 /var/home/sourceless/.config/autostart 2>/dev/null || true
fi

# Neutralize sudo privileges for wheel group
sed -i 's/^%wheel\s\+ALL=(ALL)\s\+ALL/# %wheel ALL=(ALL) ALL/' /etc/sudoers 2>/dev/null || true

# -----------------------------------------------------------------------------
# 4. Secure Flatpak Configuration & PackageKit Removal
# -----------------------------------------------------------------------------

echo "[Sourceless] Configuring secure Flatpak remotes..."

# Add official Fedora Flatpaks OCI registry
flatpak remote-add --system --if-not-exists fedora oci+https://registry.fedoraproject.org 2>/dev/null || true

# Add Flathub filtered strictly to verified upstream applications
flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
flatpak remote-modify --system --subset=verified flathub 2>/dev/null || true

# Ensure Discover and Flatpak system paths are accessible
chmod 755 /var/lib/flatpak 2>/dev/null || true

# Forcefully purge PackageKit backend from Discover to prevent unmanaged updates
echo "[Sourceless] Purging PackageKit backend from Discover..."
rpm -e --nodeps plasma-discover-packagekit plasma-discover-offline-updates 2>/dev/null || true
rm -f /usr/lib64/qt6/plugins/discover/packagekit-backend.so 2>/dev/null || true
rm -f /usr/share/dbus-1/system-services/org.freedesktop.PackageKit.service 2>/dev/null || true

# -----------------------------------------------------------------------------
# 5. Security Daemons & Services Configuration
# -----------------------------------------------------------------------------

# Set executable rights for internal security daemons
chmod 755 /usr/bin/sourceless-guard 2>/dev/null || true
chmod 755 /usr/bin/sourceless-downloads-watcher 2>/dev/null || true
chmod 755 /usr/bin/sourceless-sandbox 2>/dev/null || true

# Ensure quarantine directory exists with restricted access
mkdir -p /var/quarantine
chmod 700 /var/quarantine

# Enable core client agent and security services
systemctl enable sourceless-client.service 2>/dev/null || true
systemctl enable freshclam.service 2>/dev/null || true
systemctl enable clamd@scan.service 2>/dev/null || true
systemctl enable sourceless-shield.service 2>/dev/null || true
systemctl enable systemd-resolved.service 2>/dev/null || true

# Mask intrusive upstream service that causes boot delay timeouts
systemctl mask fedora-atomic-desktop-appstream-cache-refresh.service 2>/dev/null || true

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
        sed -i 's/^HOME_URL=.*/HOME_URL="https:\/\/sourceless.net"/' "$os_target" 2>/dev/null || true
        sed -i 's/^DOCUMENTATION_URL=.*/DOCUMENTATION_URL="https:\/\/sourceless.net"/' "$os_target" 2>/dev/null || true
        sed -i 's/^SUPPORT_URL=.*/SUPPORT_URL="https:\/\/sourceless.net"/' "$os_target" 2>/dev/null || true
        sed -i 's/^BUG_REPORT_URL=.*/BUG_REPORT_URL="https:\/\/sourceless.net"/' "$os_target" 2>/dev/null || true
        sed -i 's/^LOGO=.*/LOGO=sourceless-logo/' "$os_target" 2>/dev/null || true
        sed -i 's/^DEFAULT_HOSTNAME=.*/DEFAULT_HOSTNAME=sourceless/' "$os_target" 2>/dev/null || true
    fi
done

# Ensure KInfoCenter configuration has correct read permissions
chmod 644 /etc/xdg/kcm-about-distrorc 2>/dev/null || true

# -----------------------------------------------------------------------------
# 7. GRUB Bootloader Configuration & Styling
# -----------------------------------------------------------------------------

echo "[Sourceless] Configuring GRUB theme and fonts..."
if [[ -f /etc/default/grub ]]; then
    if grep -q "^GRUB_THEME=" /etc/default/grub; then
        sed -i 's|^GRUB_THEME=.*|GRUB_THEME="/boot/grub2/themes/sourceless/theme.txt"|' /etc/default/grub 2>/dev/null || true
    else
        echo 'GRUB_THEME="/boot/grub2/themes/sourceless/theme.txt"' >> /etc/default/grub
    fi
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub 2>/dev/null || true
    sed -i 's/^GRUB_TERMINAL_OUTPUT=.*/GRUB_TERMINAL_OUTPUT="gfxterm"/' /etc/default/grub 2>/dev/null || true
fi

# Compile GRUB theme fonts from system fonts
THEME_DIR="/boot/grub2/themes/sourceless"
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

# -----------------------------------------------------------------------------
# 8. Wallpaper Packaging & Default Overrides
# -----------------------------------------------------------------------------

echo "[Sourceless] Configuring system wallpapers..."

# Purge default upstream Fedora wallpapers
rm -rf /usr/share/wallpapers/Fedora* 2>/dev/null || true
rm -rf /usr/share/wallpapers/f[0-9]* 2>/dev/null || true

# Enforce Sourceless Dark as the system fallback wallpaper for the Next package
WALLPAPER_DARK="/usr/share/wallpapers/SourceLess/contents/images_dark/3840x2160.png"
if [[ -f "$WALLPAPER_DARK" ]]; then
    mkdir -p /usr/share/wallpapers/Next/contents/images
    mkdir -p /usr/share/wallpapers/Next/contents/images_dark
    for size in 3840x2160.png 5120x2880.png 1920x1080.png; do
        cp -f "$WALLPAPER_DARK" "/usr/share/wallpapers/Next/contents/images/$size" 2>/dev/null || true
        cp -f "$WALLPAPER_DARK" "/usr/share/wallpapers/Next/contents/images_dark/$size" 2>/dev/null || true
    done
fi

# -----------------------------------------------------------------------------
# 9. Visual Branding & Desktop Icon Overrides
# -----------------------------------------------------------------------------

echo "[Sourceless] Injecting branding icons into Breeze themes..."

START_SRC="/usr/share/icons/hicolor/scalable/apps/start-here.svg"
LOGO_SVG="/usr/share/icons/hicolor/scalable/apps/sourceless-logo.svg"
LOGO_PNG="/usr/share/icons/hicolor/scalable/apps/sourceless-logo.png"
APPS_SRC="/usr/share/icons/breeze/apps/scalable"

# 9.1 Overwrite Start Menu launcher across all Breeze themes and sizes
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

# 9.2 Overwrite OS and Distributor logos across Breeze, hicolor and pixmaps
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

# 9.3 Overwrite core application icons across all resolution directories
if [[ -d "$APPS_SRC" ]]; then
    for theme in breeze breeze-dark; do
        for size_dir in /usr/share/icons/"$theme"/apps/*; do
            if [[ -d "$size_dir" ]]; then
                # Dolphin (org.kde.dolphin)
                if [[ -f "$APPS_SRC/org.kde.dolphin.svg" ]]; then
                    cp -f "$APPS_SRC/org.kde.dolphin.svg" "$size_dir/org.kde.dolphin.svg" 2>/dev/null || true
                    cp -f "$APPS_SRC/org.kde.dolphin.svg" "$size_dir/system-file-manager.svg" 2>/dev/null || true
                fi

                # Konsole (utilities-terminal)
                if [[ -f "$APPS_SRC/org.kde.konsole.svg" ]]; then
                    cp -f "$APPS_SRC/org.kde.konsole.svg" "$size_dir/utilities-terminal.svg" 2>/dev/null || true
                    cp -f "$APPS_SRC/org.kde.konsole.svg" "$size_dir/org.kde.konsole.svg" 2>/dev/null || true
                fi

                # System Settings (preferences-system)
                if [[ -f "$APPS_SRC/systemsettings.svg" ]]; then
                    cp -f "$APPS_SRC/systemsettings.svg" "$size_dir/preferences-system.svg" 2>/dev/null || true
                    cp -f "$APPS_SRC/systemsettings.svg" "$size_dir/systemsettings.svg" 2>/dev/null || true
                fi

                # Discover (plasmadiscover)
                if [[ -f "$APPS_SRC/plasmadiscover.svg" ]]; then
                    cp -f "$APPS_SRC/plasmadiscover.svg" "$size_dir/plasmadiscover.svg" 2>/dev/null || true
                    cp -f "$APPS_SRC/plasmadiscover.svg" "$size_dir/org.kde.discover.svg" 2>/dev/null || true
                fi
            fi
        done
    done
fi

# -----------------------------------------------------------------------------
# 10. Rebuild Icon Caches and Desktop Databases (Executed Last)
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