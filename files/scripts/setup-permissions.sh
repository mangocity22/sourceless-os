#!/usr/bin/bash
# Build-time permission setup script for Sourceless-OS

# Defensively verify and isolate the original Konsole binary
if [ -f /usr/bin/konsole ] && [ ! -f /usr/bin/konsole.real ]; then
    echo "[Sourceless] Relocating original Konsole binary..."
    mv /usr/bin/konsole /usr/bin/konsole.real
else
    echo "[Sourceless] Original Konsole binary not found or already relocated. Skipping."
fi

# Generate security trap wrapper
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

# Restrict critical internal scripts to root execution only
chmod 700 /usr/bin/sourceless-unlock
chmod 700 /usr/bin/sourceless-client-boot.sh
chmod 644 /etc/profile.d/sourceless-shell-guard.sh
chmod +x /etc/grub.d/40_custom_sourceless

# Apply strict permissions on security policies and sudoers
chmod 0440 /etc/sudoers.d/sourceless-lockdown
chmod 0644 /etc/polkit-1/rules.d/10-sourceless-security.rules

# Configure offline emergency terminal launcher permissions
chmod 755 /usr/bin/sourceless-emergency-terminal 2>/dev/null || true
chmod 644 /usr/share/applications/sourceless-emergency-terminal.desktop 2>/dev/null || true

# Allow users group to write tamper flag into configuration directory
mkdir -p /etc/sourceless
chown root:users /etc/sourceless
chmod 775 /etc/sourceless

# Enable core client agent service
systemctl enable sourceless-client.service

# Mask unnecessary network services (KDE Connect)
systemctl --global mask kdeconnectd.service 2>/dev/null || true

# Revoke administrative privileges from standard user
if id "sourceless" &>/dev/null; then
    gpasswd -d sourceless wheel 2>/dev/null || true
    usermod -g sourceless -G users sourceless
fi

# Lock down user autostart directory to prevent startup persistence
mkdir -p /etc/skel/.config/autostart
chmod 555 /etc/skel/.config/autostart

if [ -d "/var/home/sourceless" ]; then
    mkdir -p /var/home/sourceless/.config/autostart
    chown root:root /var/home/sourceless/.config/autostart
    chmod 555 /var/home/sourceless/.config/autostart
fi

# Neutralize sudo privileges for wheel group
sed -i 's/^%wheel\s\+ALL=(ALL)\s\+ALL/# %wheel ALL=(ALL) ALL/' /etc/sudoers

# Configure secure Flatpak repositories
echo "[Sourceless] Configuring secure Flatpak remotes..."

# 1. Add official Fedora Flatpaks OCI registry
flatpak remote-add --system --if-not-exists fedora oci+https://registry.fedoraproject.org

# 2. Add Flathub filtered strictly to verified upstream applications
flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak remote-modify --system --subset=verified flathub

# 3. Ensure Discover and flatpak system paths are world-readable
chmod 755 /var/lib/flatpak 2>/dev/null || true

echo "[Sourceless] setup-permissions.sh completed successfully."