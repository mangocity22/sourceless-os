#!/usr/bin/bash
set -euo pipefail

# 1. Live USB Session handling (only active when booted with rd.live.image)
if grep -qw "rd.live.image" /proc/cmdline 2>/dev/null; then
    mkdir -p /var/home /var/roothome /var/lib/sddm /var/tmp /var/log
    chmod 1777 /var/tmp 2>/dev/null || true
    chown -R sddm:sddm /var/lib/sddm 2>/dev/null || true

    if ! id liveuser >/dev/null 2>&1; then
        useradd -m -d /var/home/liveuser -G wheel -s /bin/bash -c "Sourceless Live User" liveuser 2>/dev/null || true
        passwd -d liveuser 2>/dev/null || true
    fi

    mkdir -p /etc/sudoers.d
    echo "liveuser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-liveuser
    chmod 440 /etc/sudoers.d/99-liveuser

    if [ ! -f /var/home/liveuser/.config/plasma-org.kde.plasma.desktop-appletsrc ]; then
        cp -a /etc/skel/. /var/home/liveuser/ 2>/dev/null || true
    fi
    if [ -f /etc/xdg/kscreenlockerrc ]; then
        mkdir -p /var/home/liveuser/.config
        cp -f /etc/xdg/kscreenlockerrc /var/home/liveuser/.config/kscreenlockerrc
    fi

    mkdir -p /var/home/liveuser/Desktop /var/home/liveuser/.config/autostart
    if [ -f /usr/share/applications/liveinst.desktop ]; then
        cp -f /usr/share/applications/liveinst.desktop /var/home/liveuser/Desktop/liveinst.desktop
        chmod +x /var/home/liveuser/Desktop/liveinst.desktop
        if grep -qw "liveinst" /proc/cmdline 2>/dev/null; then
            cp -f /usr/share/applications/liveinst.desktop /var/home/liveuser/.config/autostart/liveinst.desktop
        fi
    fi

    chown -R liveuser:liveuser /var/home/liveuser 2>/dev/null || true

    mkdir -p /etc/sddm.conf.d
    cat << 'EOF' > /etc/sddm.conf.d/99-live-autologin.conf
[Autologin]
User=liveuser
Session=plasma
Relogin=false
EOF
    exit 0
else
    rm -f /etc/sddm.conf.d/99-live-autologin.conf /etc/sudoers.d/99-liveuser 2>/dev/null || true
fi

# Wait for the home directory to be mounted (essential for installed ostree systems)
for i in {1..10}; do
    if [ -d /var/home/sourceless ]; then
        break
    fi
    sleep 0.5
done

if [ -d /var/home/sourceless ]; then
    # 1. Partea ta existenta pentru bash si skel de baza
    if [ ! -f /var/home/sourceless/.bashrc ]; then
        cp -a /etc/skel/. /var/home/sourceless/ 2>/dev/null || true
    fi
    
    # 2. Repararea interfetei KDE (Factory Reset)
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

    # 2b. Sync Sourceless Liquid Glass lock screen config for existing user homes
    if [ -f /etc/xdg/kscreenlockerrc ]; then
        mkdir -p /var/home/sourceless/.config
        cp -f /etc/xdg/kscreenlockerrc /var/home/sourceless/.config/kscreenlockerrc
    fi

    # 3. Activam Starship si restauram contextul SELinux
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
