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
    # Enforce English (US) system locale for the live installer session
    printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf
    export LANG=en_US.UTF-8

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

    # Ensure Starship prompt initialization for live terminal sessions
    if [ -f /var/home/liveuser/.bashrc ] && ! grep -q "starship init bash" /var/home/liveuser/.bashrc 2>/dev/null; then
        echo 'eval "$(starship init bash)"' >> /var/home/liveuser/.bashrc
    fi

    for root_cfg in /root/.config /var/roothome/.config; do
        mkdir -p "$root_cfg/gtk-3.0" "$root_cfg/gtk-4.0"
        cp -f /etc/gtk-3.0/settings.ini "$root_cfg/gtk-3.0/settings.ini" 2>/dev/null || true
        cp -f /etc/gtk-4.0/settings.ini "$root_cfg/gtk-4.0/settings.ini" 2>/dev/null || true
    done

    # Expose Anaconda installer on Desktop in Live session; direct BIOS install mode uses dedicated kiosk session
    mkdir -p /var/home/liveuser/Desktop /var/home/liveuser/.config/autostart
    rm -f /var/home/liveuser/.config/autostart/liveinst.desktop 2>/dev/null || true
    if [ -f /usr/share/applications/liveinst.desktop ]; then
        sed -i 's/^Name=.*/Name=Install SourceLess OS/; s/^GenericName=.*/GenericName=Install SourceLess OS/; s/^Comment=.*/Comment=Install SourceLess OS to Hard Drive/; s/^Icon=.*/Icon=sourceless-logo/; s/Fedora/SourceLess OS/g' /usr/share/applications/liveinst.desktop 2>/dev/null || true
        cp -f /usr/share/applications/liveinst.desktop /var/home/liveuser/Desktop/liveinst.desktop
        chmod +x /var/home/liveuser/Desktop/liveinst.desktop
    fi

    # Determine SDDM autologin session: standalone fullscreen installer for 'liveinst', full KDE Plasma desktop otherwise
    if grep -qw "liveinst" /proc/cmdline 2>/dev/null && [ -f /usr/share/wayland-sessions/sourceless-installer.desktop ]; then
        LIVE_SESSION="sourceless-installer"
    else
        LIVE_SESSION="plasma"
        rm -f /var/home/liveuser/.config/kwinrulesrc 2>/dev/null || true
    fi

    chown -R liveuser:liveuser /var/home/liveuser 2>/dev/null || true

    # Start the root-level installer helper API outside this oneshot cgroup
    if [ -x /usr/bin/sourceless-installer-helper.py ] && ! pgrep -f "/usr/bin/sourceless-installer-helper.py" >/dev/null 2>&1; then
        if command -v systemd-run >/dev/null 2>&1; then
            systemd-run --no-block --unit=sourceless-installer-helper /usr/bin/sourceless-installer-helper.py >/dev/null 2>&1 || \
                nohup /usr/bin/sourceless-installer-helper.py >/var/log/sourceless-installer-helper.log 2>&1 &
        else
            nohup /usr/bin/sourceless-installer-helper.py >/var/log/sourceless-installer-helper.log 2>&1 &
        fi
    fi

    # Configure SDDM autologin for the chosen Live or Direct Installer session
    mkdir -p /etc/sddm.conf.d
    cat << EOF > /etc/sddm.conf.d/99-live-autologin.conf
[Autologin]
User=liveuser
Session=${LIVE_SESSION}
Relogin=false
EOF
    exit 0
else
    # Clean up live-only autologin and sudoers drop-ins on installed systems
    rm -f /etc/sddm.conf.d/99-live-autologin.conf /etc/sudoers.d/99-liveuser 2>/dev/null || true
fi

# 2. First-Boot Windows-style OOBE check (when .oobe_completed marker is absent)
mkdir -p /etc/sourceless
if [ ! -f /etc/sourceless/.oobe_completed ]; then
    # Preserve upgraded legacy systems where an existing real human account is present without sourceless-setup
    HAS_EXISTING_HUMAN=0
    for h in /var/home/*; do
        [ -d "$h" ] || continue
        hn=$(basename "$h")
        case "$hn" in
            liveuser|sourceless-setup|lost+found) continue ;;
        esac
        if id "$hn" >/dev/null 2>&1; then
            HAS_EXISTING_HUMAN=1
            break
        fi
    done

    if [ "$HAS_EXISTING_HUMAN" -eq 1 ] && ! id sourceless-setup >/dev/null 2>&1; then
        touch /etc/sourceless/.oobe_completed
    else
        # Provision temporary staging session and launch full-screen First-Boot OOBE
        if ! id sourceless-setup >/dev/null 2>&1; then
            useradd -m -d /var/home/sourceless-setup -G users -s /bin/bash -c "SourceLess Setup" sourceless-setup 2>/dev/null || true
            passwd -d sourceless-setup 2>/dev/null || true
        fi

        OOBE_HOME="/var/home/sourceless-setup"
        mkdir -p "${OOBE_HOME}/.config/autostart" "${OOBE_HOME}/.config/Kvantum"
        cp -a /etc/skel/. "${OOBE_HOME}/" 2>/dev/null || true
        cp -f /etc/xdg/kscreenlockerrc "${OOBE_HOME}/.config/kscreenlockerrc" 2>/dev/null || true
        cp -f /etc/xdg/kdeglobals "${OOBE_HOME}/.config/kdeglobals" 2>/dev/null || true
        cp -f /etc/xdg/plasmarc "${OOBE_HOME}/.config/plasmarc" 2>/dev/null || true
        cp -f /etc/xdg/kwinrc "${OOBE_HOME}/.config/kwinrc" 2>/dev/null || true
        cp -f /etc/xdg/Kvantum/kvantum.kvconfig "${OOBE_HOME}/.config/Kvantum/kvantum.kvconfig" 2>/dev/null || true

        cat << 'EOF' > "${OOBE_HOME}/.config/autostart/sourceless-oobe.desktop"
[Desktop Entry]
Type=Application
Name=SourceLess OS First-Boot Setup
Exec=/usr/bin/python3 /usr/bin/sourceless-oobe.py
X-KDE-autostart-phase=1
NoDisplay=true
EOF
        chmod 644 "${OOBE_HOME}/.config/autostart/sourceless-oobe.desktop"

        OOBE_GRP=$(id -gn sourceless-setup 2>/dev/null || echo "sourceless-setup")
        chown -R "sourceless-setup:${OOBE_GRP}" "$OOBE_HOME" 2>/dev/null || true
        chmod 700 "$OOBE_HOME"
        restorecon -RF "$OOBE_HOME" 2>/dev/null || true

        mkdir -p /etc/sddm.conf.d
        cat << 'EOF' > /etc/sddm.conf.d/99-oobe-autologin.conf
[Autologin]
User=sourceless-setup
Session=plasma
Relogin=false
EOF
        exit 0
    fi
fi

# Clean up any leftover OOBE staging files after completion
rm -f /etc/sddm.conf.d/99-oobe-autologin.conf 2>/dev/null || true
if id sourceless-setup >/dev/null 2>&1; then
    userdel -r sourceless-setup 2>/dev/null || true
fi

# 3. Repair user skeleton, Plasma panel layout, lock screen config, permissions, and SELinux labels across all real users
for USER_HOME in /var/home/*; do
    [ -d "$USER_HOME" ] || continue
    TARGET_USER=$(basename "$USER_HOME")
    case "$TARGET_USER" in
        liveuser|sourceless-setup|lost+found) continue ;;
    esac
    id "$TARGET_USER" >/dev/null 2>&1 || continue

    # Populate missing skeleton files (e.g. .bashrc)
    if [ ! -f "${USER_HOME}/.bashrc" ]; then
        cp -a /etc/skel/. "${USER_HOME}/" 2>/dev/null || true
    fi

    PRIMARY_GRP=$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")

    # Restore default Plasma panel layout when missing or explicitly requested via reset-ui
    if [ ! -f "${USER_HOME}/.config/plasma-org.kde.plasma.desktop-appletsrc" ] || [ "${1:-}" == "reset-ui" ]; then
        echo "Applying Factory Reset for KDE Plasma UI (${TARGET_USER})..."
        mkdir -p "${USER_HOME}/.config/"
        cp -f /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc "${USER_HOME}/.config/"
        chown "${TARGET_USER}:${PRIMARY_GRP}" "${USER_HOME}/.config/plasma-org.kde.plasma.desktop-appletsrc"
        chmod 600 "${USER_HOME}/.config/plasma-org.kde.plasma.desktop-appletsrc"

        if pgrep -u "$TARGET_USER" plasmashell > /dev/null; then
            sudo -u "$TARGET_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$TARGET_USER")/bus" systemctl --user restart plasma-plasmashell 2>/dev/null || true
        fi
    fi

    # Sync global SourcelessGlass lock screen configuration
    if [ -f /etc/xdg/kscreenlockerrc ]; then
        mkdir -p "${USER_HOME}/.config"
        cp -f /etc/xdg/kscreenlockerrc "${USER_HOME}/.config/kscreenlockerrc"
    fi

    # Ensure Starship prompt initialization and lock down autostart directory ownership
    if ! grep -q "starship init bash" "${USER_HOME}/.bashrc" 2>/dev/null; then
        echo 'eval "$(starship init bash)"' >> "${USER_HOME}/.bashrc"
    fi

    chown -R "${TARGET_USER}:${PRIMARY_GRP}" "$USER_HOME"
    chmod 700 "$USER_HOME"
    chmod 755 "${USER_HOME}/.config" 2>/dev/null || true
    mkdir -p "${USER_HOME}/.config/autostart"
    chown root:root "${USER_HOME}/.config/autostart" 2>/dev/null || true
    chmod 555 "${USER_HOME}/.config/autostart" 2>/dev/null || true
    restorecon -RF "$USER_HOME" 2>/dev/null || true
done
