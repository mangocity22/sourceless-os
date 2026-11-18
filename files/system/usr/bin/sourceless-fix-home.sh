#!/usr/bin/bash
# /usr/bin/sourceless-fix-home.sh
# Configures Live USB sessions or enforces installed home ownership, Plasma layout, and SELinux contexts
set -euo pipefail

# 0. Ensure OSTree BLS boot entries retain SourceLess OS branding across upgrades
for bls_file in /boot/loader/entries/*.conf; do
    if [ -f "$bls_file" ]; then
        sed -i '/^title /s/Fedora Linux/SourceLess OS/g; /^title /s/Fedora/SourceLess OS/g; /^title /s/Sourceless OS/SourceLess OS/g; /^title /s/ (Kinoite)//g' "$bls_file" 2>/dev/null || true
    fi
done

# 1. Handle Live USB session when booted with rd.live.image
if grep -qw "rd.live.image" /proc/cmdline 2>/dev/null; then
    mkdir -p /var/home /var/roothome /var/lib/sddm /var/tmp /var/log
    chmod 1777 /var/tmp 2>/dev/null || true
    chown -R sddm:sddm /var/lib/sddm 2>/dev/null || true

    # Create passwordless liveuser account with wheel access for installer execution
    if ! id liveuser >/dev/null 2>&1; then
        useradd -m -d /var/home/liveuser -G wheel -s /bin/bash -c "SourceLess OS Live User" liveuser 2>/dev/null || true
        passwd -d liveuser 2>/dev/null || true
    fi

    mkdir -p /etc/sudoers.d
    echo "liveuser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-liveuser
    chmod 440 /etc/sudoers.d/99-liveuser

    # Populate skeleton desktop configuration, dark GTK settings, and lock screen theme
    if [ ! -f /var/home/liveuser/.config/plasma-org.kde.plasma.desktop-appletsrc ]; then
        cp -a /etc/skel/. /var/home/liveuser/ 2>/dev/null || true
    fi
    mkdir -p /var/home/liveuser/.config/Kvantum /var/home/liveuser/.config/gtk-3.0 /var/home/liveuser/.config/gtk-4.0
    cp -f /etc/xdg/kscreenlockerrc /var/home/liveuser/.config/kscreenlockerrc 2>/dev/null || true
    cp -f /etc/xdg/kdeglobals /var/home/liveuser/.config/kdeglobals 2>/dev/null || true
    cp -f /etc/xdg/plasmarc /var/home/liveuser/.config/plasmarc 2>/dev/null || true
    cp -f /etc/xdg/kwinrc /var/home/liveuser/.config/kwinrc 2>/dev/null || true
    cp -f /etc/xdg/Kvantum/kvantum.kvconfig /var/home/liveuser/.config/Kvantum/kvantum.kvconfig 2>/dev/null || true
    cp -f /etc/gtk-3.0/settings.ini /var/home/liveuser/.config/gtk-3.0/settings.ini 2>/dev/null || true
    cp -f /etc/gtk-4.0/settings.ini /var/home/liveuser/.config/gtk-4.0/settings.ini 2>/dev/null || true

    for root_cfg in /root/.config /var/roothome/.config; do
        mkdir -p "$root_cfg/gtk-3.0" "$root_cfg/gtk-4.0"
        cp -f /etc/gtk-3.0/settings.ini "$root_cfg/gtk-3.0/settings.ini" 2>/dev/null || true
        cp -f /etc/gtk-4.0/settings.ini "$root_cfg/gtk-4.0/settings.ini" 2>/dev/null || true
    done

    # Expose Anaconda installer on Desktop and autostart when booted with liveinst
    mkdir -p /var/home/liveuser/Desktop /var/home/liveuser/.config/autostart
    if [ -f /usr/share/applications/liveinst.desktop ]; then
        sed -i 's/^Name=.*/Name=Install SourceLess OS/; s/^GenericName=.*/GenericName=Install SourceLess OS/; s/^Comment=.*/Comment=Install SourceLess OS to Hard Drive/; s/^Icon=.*/Icon=sourceless-logo/; s/Fedora/SourceLess OS/g' /usr/share/applications/liveinst.desktop 2>/dev/null || true
        cp -f /usr/share/applications/liveinst.desktop /var/home/liveuser/Desktop/liveinst.desktop
        chmod +x /var/home/liveuser/Desktop/liveinst.desktop
        if grep -qw "liveinst" /proc/cmdline 2>/dev/null; then
            cp -f /usr/share/applications/liveinst.desktop /var/home/liveuser/.config/autostart/liveinst.desktop
        fi
    fi

    chown -R liveuser:liveuser /var/home/liveuser 2>/dev/null || true

    # Configure SDDM autologin for the live session
    mkdir -p /etc/sddm.conf.d
    cat << 'EOF' > /etc/sddm.conf.d/99-live-autologin.conf
[Autologin]
User=liveuser
Session=plasma
Relogin=false
EOF
    exit 0
else
    # Clean up live-only autologin and sudoers drop-ins on installed systems
    rm -f /etc/sddm.conf.d/99-live-autologin.conf /etc/sudoers.d/99-liveuser 2>/dev/null || true
fi

# 2. Wait for /var/home/sourceless mount on installed OSTree systems
for i in {1..10}; do
    if [ -d /var/home/sourceless ]; then
        break
    fi
    sleep 0.5
done

# 3. Repair user skeleton, Plasma panel layout, lock screen config, permissions, and SELinux labels
if [ -d /var/home/sourceless ]; then
    # Populate missing skeleton files (e.g. .bashrc)
    if [ ! -f /var/home/sourceless/.bashrc ]; then
        cp -a /etc/skel/. /var/home/sourceless/ 2>/dev/null || true
    fi

    # Restore default Plasma panel layout when missing or explicitly requested via reset-ui
    if [ ! -f /var/home/sourceless/.config/plasma-org.kde.plasma.desktop-appletsrc ] || [ "${1:-}" == "reset-ui" ]; then
        echo "Applying Factory Reset for KDE Plasma UI..."
        mkdir -p /var/home/sourceless/.config/
        cp -f /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc /var/home/sourceless/.config/
        chown sourceless:sourceless /var/home/sourceless/.config/plasma-org.kde.plasma.desktop-appletsrc
        chmod 600 /var/home/sourceless/.config/plasma-org.kde.plasma.desktop-appletsrc

        if pgrep -u sourceless plasmashell > /dev/null; then
            sudo -u sourceless DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u sourceless)/bus" systemctl --user restart plasma-plasmashell 2>/dev/null || true
        fi
    fi

    # Sync global SourcelessGlass lock screen configuration
    if [ -f /etc/xdg/kscreenlockerrc ]; then
        mkdir -p /var/home/sourceless/.config
        cp -f /etc/xdg/kscreenlockerrc /var/home/sourceless/.config/kscreenlockerrc
    fi

    # Ensure Starship prompt initialization and lock down autostart directory ownership
    if ! grep -q "starship init bash" /var/home/sourceless/.bashrc 2>/dev/null; then
        echo 'eval "$(starship init bash)"' >> /var/home/sourceless/.bashrc
    fi

    chown -R 1000:1000 /var/home/sourceless
    chmod 700 /var/home/sourceless
    chmod 755 /var/home/sourceless/.config 2>/dev/null || true
    mkdir -p /var/home/sourceless/.config/autostart
    chown root:root /var/home/sourceless/.config/autostart 2>/dev/null || true
    chmod 555 /var/home/sourceless/.config/autostart 2>/dev/null || true
    restorecon -RF /var/home/sourceless 2>/dev/null || true
fi
