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

chmod +x /usr/bin/konsole

# Unhide native Konsole desktop launcher and mask Flatpak
KONSOLE_DESKTOP="/usr/share/applications/org.kde.konsole.desktop"
if [[ -f "$KONSOLE_DESKTOP" ]]; then
    echo "[Sourceless] Unhiding Konsole desktop entry..."
    sed -i '/^NoDisplay=/d' "$KONSOLE_DESKTOP" 2>/dev/null || true
    sed -i 's/^Hidden=.*/Hidden=false/' "$KONSOLE_DESKTOP" 2>/dev/null || true
fi
flatpak mask org.kde.konsole 2>/dev/null || true

# Force global Starship config for all users
if ! grep -q "STARSHIP_CONFIG" /etc/bashrc; then
    echo 'export STARSHIP_CONFIG="/etc/starship.toml"' >> /etc/bashrc
fi

if ! grep -q "starship init bash" /etc/bashrc; then
    echo 'eval "$(starship init bash)"' >> /etc/bashrc
fi

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
mkdir -p /etc/skel/.config/autostart
chmod 755 /etc/skel/.config
chmod 755 /etc/skel/.config/autostart

# Enable runtime ownership repair service
systemctl enable sourceless-fix-home.service 2>/dev/null || true

# Pre-apply numeric UID 1000 ownership to any existing home tree
if [ -d "/var/home/sourceless" ]; then
    chown -R 1000:1000 /var/home/sourceless 2>/dev/null || true
    chmod 755 /var/home/sourceless/.config 2>/dev/null || true
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
    if [[ -f "$os_target" \vert{}\vert{} -L "$os_target" ]]; then
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
        cp -f /usr/share/grub/unicode