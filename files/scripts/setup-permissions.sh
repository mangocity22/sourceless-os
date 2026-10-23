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

sed -i 's|^#LocalSocket /run/clamd.scan/clamd.sock|LocalSocket /run/clamd.scan/clamd.sock|' /etc/clamd.d/scan.conf 2>/dev/null || true

# -----------------------------------------------------------------------------
# 6. Official OS Release Identification (/usr/lib/os-release)
# -----------------------------------------------------------------------------

echo "[Sourceless] Patching OS release metadata..."
if [[ -f /usr/lib/os-release ]]; then
    sed -i 's/^NAME=.*/NAME="Sourceless OS"/' /usr/lib/os-release
    sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Sourceless OS"/' /usr/lib/os-release
    sed -i 's/^ID=.*/ID=sourceless/' /usr/lib/os-release
    sed -i 's/^HOME_URL=.*/HOME_URL="https:\/\/sourceless.io"/' /usr/lib/os-release
    sed -i 's/^DOCUMENTATION_URL=.*/DOCUMENTATION_URL="https:\/\/sourceless.io"/' /usr/lib/os-release
    sed -i 's/^SUPPORT_URL=.*/SUPPORT_URL="https:\/\/sourceless.io"/' /usr/lib/os-release
    sed -i 's/^BUG_REPORT_URL=.*/BUG_REPORT_URL="https:\/\/sourceless.io"/' /usr/lib/os-release
    sed -i 's/^LOGO=.*/LOGO=sourceless-logo/' /usr/lib/os-release
    sed -i 's/^DEFAULT_HOSTNAME=.*/DEFAULT_HOSTNAME=sourceless/' /usr/lib/os-release
fi

# -----------------------------------------------------------------------------
# 7. Visual Branding & Desktop Asset Overrides
# -----------------------------------------------------------------------------

echo "[Sourceless] Applying visual branding assets..."

# Remove default upstream Fedora wallpapers
rm -rf /usr/share/wallpapers/Fedora* 2>/dev/null || true
rm -rf /usr/share/wallpapers/f[0-9]* 2>/dev/null || true

# Define branding asset source paths
START_SRC="/usr/share/icons/hicolor/scalable/apps/start-here.svg"
LOGO_SVG="/usr/share/icons/hicolor/scalable/apps/sourceless-logo.svg"
LOGO_PNG="/usr/share/icons/hicolor/scalable/apps/sourceless-logo.png"

# Aggressively overwrite KDE Plasma 6 Start Menu launcher across all Breeze themes and sizes
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

# Distribute official OS logo to fallback icon themes and pixmaps for KInfoCenter
if [[ -f "$LOGO_SVG" ]]; then
    cp -f "$LOGO_SVG" /usr/share/icons/hicolor/scalable/apps/distributor-logo.svg 2>/dev/null || true
    cp -f "$LOGO_SVG" /usr/share/pixmaps/sourceless-logo.svg 2>/dev/null || true
    cp -f "$LOGO_SVG" /usr/share/pixmaps/distributor-logo.svg 2>/dev/null || true
fi

if [[ -f "$LOGO_PNG" ]]; then
    cp -f "$LOGO_PNG" /usr/share/pixmaps/sourceless-logo.png 2>/dev/null || true
    cp -f "$LOGO_PNG" /usr/share/pixmaps/distributor-logo.png 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# 8. Rebuild Icon Caches and Desktop Databases
# -----------------------------------------------------------------------------

echo "[Sourceless] Regenerating icon caches and application metadata..."
update-desktop-database /usr/share/applications 2>/dev/null || true

for theme_dir in /usr/share/icons/*; do
    if [[ -d "$theme_dir" ]]; then
        touch "$theme_dir" 2>/dev/null || true
        gtk-update-icon-cache -f -q "$theme_dir" 2>/dev/null || true
    fi
done

echo "[Sourceless] setup-permissions.sh completed successfully."