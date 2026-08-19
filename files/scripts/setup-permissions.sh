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

# Neutralizare privilegii sudo pentru grupul wheel
sed -i 's/^%wheel\s\+ALL=(ALL)\s\+ALL/# %wheel ALL=(ALL) ALL/' /etc/sudoers

echo "[Sourceless] setup-permissions.sh completed successfully."