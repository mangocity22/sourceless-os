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
    cp -f /etc/xdg/kwalletrc /var/home/liveuser/.config/kwalletrc 2>/dev/null || true

    # Ensure Starship prompt initialization for live terminal sessions
    if [ -f /var/home/liveuser/.bashrc ] && ! grep -q "starship init bash" /var/home/liveuser/.bashrc 2>/dev/null; then
        echo 'eval "$(starship init bash)"' >> /var/home/liveuser/.bashrc
    fi

    for root_cfg in /root/.config /var/roothome/.config; do
        mkdir -p "$root_cfg/gtk-3.0" "$root_cfg/gtk-4.0"
        cp -f /etc/gtk-3.0/settings.ini "$root_cfg/gtk-3.0/settings.ini" 2>/dev/null || true
        cp -f /etc/gtk-4.0/settings.ini "$root_cfg/gtk-4.0/settings.ini" 2>/dev/null || true
    done

    # Expose Anaconda installer on Desktop in Live session; launch native fullscreen installer on 'liveinst'
    mkdir -p /var/home/liveuser/Desktop /var/home/liveuser/.config/autostart /var/home/liveuser/.config/systemd/user
    if [ -f /usr/share/applications/liveinst.desktop ]; then
        sed -i 's/^Name=.*/Name=Install SourceLess OS/; s/^GenericName=.*/GenericName=Install SourceLess OS/; s/^Comment=.*/Comment=Install SourceLess OS to Hard Drive/; s/^Icon=.*/Icon=sourceless-logo/; s/Fedora/SourceLess OS/g' /usr/share/applications/liveinst.desktop 2>/dev/null || true
        cp -f /usr/share/applications/liveinst.desktop /var/home/liveuser/Desktop/liveinst.desktop
        chmod +x /var/home/liveuser/Desktop/liveinst.desktop
    fi

    # Prevent KWallet (ksecretd) crashes and DrKonqi popups cleanly via exit-0 stubs (never chmod 000)
    rm -f /var/home/liveuser/.config/systemd/user/plasma-plasmashell.service 2>/dev/null || true
    ln -sf /dev/null /var/home/liveuser/.config/systemd/user/drkonqi-coredump-pickup.service
    ln -sf /dev/null /var/home/liveuser/.config/systemd/user/drkonqi-coredump-launcher.socket
    ln -sf /dev/null /var/home/liveuser/.config/systemd/user/dbus-org.freedesktop.impl.portal.desktop.kwallet.service
    for stub_bin in /usr/bin/ksecretd /usr/bin/drkonqi-coredump-gui /usr/libexec/drkonqi; do
        if [ -f "$stub_bin" ]; then
            printf '#!/usr/bin/bash\nexit 0\n' > "$stub_bin" 2>/dev/null || true
            chmod 755 "$stub_bin" 2>/dev/null || true
        fi
    done
    rm -f /etc/xdg/autostart/*drkonqi*.desktop 2>/dev/null || true

    # Live-RAM guard for upstream Anaconda RHBZ#2412427 (non-fatal rsync exit 23/24 on container xattrs -> /mnt/sysroot)
    if [ -x /usr/bin/rsync ] && [ ! -f /usr/bin/rsync.real ]; then
        mv -f /usr/bin/rsync /usr/bin/rsync.real 2>/dev/null || true
    fi
    if [ -x /usr/bin/rsync.real ]; then
        cat << 'EOF' > /usr/bin/rsync
#!/usr/bin/bash
/usr/bin/rsync.real "$@"
rc=$?
is_sysroot=0
for arg in "$@"; do
    case "$arg" in
        */mnt/sysroot*|/mnt/sysroot*) is_sysroot=1; break ;;
    esac
done
if [ "$is_sysroot" -eq 1 ] && { [ "$rc" -eq 0 ] || [ "$rc" -eq 23 ] || [ "$rc" -eq 24 ]; }; then
    mkdir -p \
        /mnt/sysroot/var/roothome \
        /mnt/sysroot/var/home \
        /mnt/sysroot/var/tmp \
        /mnt/sysroot/var/log \
        /mnt/sysroot/var/opt \
        /mnt/sysroot/var/srv \
        /mnt/sysroot/var/mnt \
        /mnt/sysroot/var/usrlocal \
        /mnt/sysroot/var/lib/sddm \
        /mnt/sysroot/var/lib/sourceless-update \
        /mnt/sysroot/var/cache/sourceless-update \
        /mnt/sysroot/var/cache 2>/dev/null || true
    chmod 700 /mnt/sysroot/var/roothome 2>/dev/null || true
    chmod 1777 /mnt/sysroot/var/tmp 2>/dev/null || true
    if [ ! -d /mnt/sysroot/root ]; then
        rm -f /mnt/sysroot/root 2>/dev/null || true
        ln -s var/roothome /mnt/sysroot/root 2>/dev/null || mkdir -p /mnt/sysroot/root 2>/dev/null || true
    fi
    for kver_dir in /mnt/sysroot/usr/lib/modules/*; do
        [ -d "$kver_dir" ] && [ -f "$kver_dir/vmlinuz" ] || continue
        kver=$(basename "$kver_dir")
        mkdir -p /mnt/sysroot/boot 2>/dev/null || true
        [ -f "/mnt/sysroot/boot/vmlinuz-${kver}" ] || cp -f "$kver_dir/vmlinuz" "/mnt/sysroot/boot/vmlinuz-${kver}" 2>/dev/null || true
        if [ ! -f "/mnt/sysroot/boot/initramfs-${kver}.img" ] && [ -f "$kver_dir/initramfs.img" ]; then
            cp -f "$kver_dir/initramfs.img" "/mnt/sysroot/boot/initramfs-${kver}.img" 2>/dev/null || true
        fi
    done
    FC="/mnt/sysroot/etc/selinux/targeted/contexts/files/file_contexts"
    if [ -f "$FC" ]; then
        if [ -x /mnt/sysroot/usr/sbin/setfiles ]; then
            chroot /mnt/sysroot /usr/sbin/setfiles -F -e /proc -e /sys -e /dev -e /run -e /tmp -e /boot/efi /etc/selinux/targeted/contexts/files/file_contexts / >/dev/null 2>&1 || \
                setfiles -F -r /mnt/sysroot -e /mnt/sysroot/proc -e /mnt/sysroot/sys -e /mnt/sysroot/dev -e /mnt/sysroot/run -e /mnt/sysroot/tmp -e /mnt/sysroot/boot/efi "$FC" /mnt/sysroot >/dev/null 2>&1 || true
        elif command -v setfiles >/dev/null 2>&1; then
            setfiles -F -r /mnt/sysroot -e /mnt/sysroot/proc -e /mnt/sysroot/sys -e /mnt/sysroot/dev -e /mnt/sysroot/run -e /mnt/sysroot/tmp -e /mnt/sysroot/boot/efi "$FC" /mnt/sysroot >/dev/null 2>&1 || true
        fi
    fi
    exit 0
fi
exit "$rc"
EOF
        chmod 755 /usr/bin/rsync 2>/dev/null || true
    fi

    if grep -qw "liveinst" /proc/cmdline 2>/dev/null; then
        cat << 'EOF' > /var/home/liveuser/.config/kwinrulesrc
[1]
Description=SourceLess Direct Installer Fullscreen
fullscreen=true
fullscreenrule=2
maximizehoriz=true
maximizehorizrule=2
maximizevert=true
maximizevertrule=2
noborder=true
noborderrule=2
types=1
wmclass=slitherer|anaconda|webui|liveinst
wmclasscomplete=false
wmclassmatch=3

[General]
count=1
rules=1
EOF

        # Autostart native liveinst.desktop (no X-KDE-autostart-phase so systemd-xdg-autostart-generator runs it)
        if [ -f /usr/share/applications/liveinst.desktop ]; then
            cp -f /usr/share/applications/liveinst.desktop /var/home/liveuser/.config/autostart/liveinst.desktop
            chmod 644 /var/home/liveuser/.config/autostart/liveinst.desktop
        fi

        cat << 'EOF' > /var/home/liveuser/.config/autostart/sourceless-installer-watcher.desktop
[Desktop Entry]
Type=Application
Name=SourceLess OS Installer Session Watcher
Exec=/usr/bin/sourceless-direct-installer-inner
NoDisplay=true
EOF
        chmod 644 /var/home/liveuser/.config/autostart/sourceless-installer-watcher.desktop
    else
        rm -f /var/home/liveuser/.config/kwinrulesrc \
              /var/home/liveuser/.config/autostart/liveinst.desktop \
              /var/home/liveuser/.config/autostart/sourceless-installer-watcher.desktop 2>/dev/null || true
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

    # Configure SDDM autologin using Plasma Wayland session (handles bus, Polkit, and XWayland cleanly)
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
    if id liveuser >/dev/null 2>&1; then
        userdel -r liveuser 2>/dev/null || true
    fi

    # Ensure kernel integrity lockdown is active and persisted in installed BLS entries
    if [ -w /sys/kernel/security/lockdown ] && grep -q '\[none\]' /sys/kernel/security/lockdown 2>/dev/null; then
        printf 'integrity' > /sys/kernel/security/lockdown 2>/dev/null || true
    fi
    for bls_file in /boot/loader/entries/*.conf; do
        if [ -f "$bls_file" ]; then
            sed -i '/^options /{/lockdown=/!s/$/ lockdown=integrity/}' "$bls_file" 2>/dev/null || true
        fi
    done

    # Ensure Atomic /var runtime targets exist with proper permissions and SELinux labels before SDDM starts
    mkdir -p /var/home /var/roothome /var/lib/sddm /var/lib/sourceless-update /var/cache/sourceless-update /var/tmp /var/log /var/opt /var/srv /var/mnt /var/usrlocal
    chmod 700 /var/roothome 2>/dev/null || true
    chmod 1777 /var/tmp 2>/dev/null || true
    chown -R sddm:sddm /var/lib/sddm 2>/dev/null || true
    restorecon -RF /var/lib/sddm /var/roothome /var/tmp /var/log /etc/sddm.conf.d /etc/fstab /boot/loader 2>/dev/null || true
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
        mkdir -p "${OOBE_HOME}/.config/autostart" "${OOBE_HOME}/.config/Kvantum" "${OOBE_HOME}/.config/systemd/user"
        cp -a /etc/skel/. "${OOBE_HOME}/" 2>/dev/null || true
        cp -f /etc/xdg/kscreenlockerrc "${OOBE_HOME}/.config/kscreenlockerrc" 2>/dev/null || true
        cp -f /etc/xdg/kdeglobals "${OOBE_HOME}/.config/kdeglobals" 2>/dev/null || true
        cp -f /etc/xdg/plasmarc "${OOBE_HOME}/.config/plasmarc" 2>/dev/null || true
        cp -f /etc/xdg/kwinrc "${OOBE_HOME}/.config/kwinrc" 2>/dev/null || true
        cp -f /etc/xdg/Kvantum/kvantum.kvconfig "${OOBE_HOME}/.config/Kvantum/kvantum.kvconfig" 2>/dev/null || true
        cp -f /etc/xdg/kwalletrc "${OOBE_HOME}/.config/kwalletrc" 2>/dev/null || true
        ln -sf /dev/null "${OOBE_HOME}/.config/systemd/user/drkonqi-coredump-pickup.service"
        ln -sf /dev/null "${OOBE_HOME}/.config/systemd/user/drkonqi-coredump-launcher.socket"
        ln -sf /dev/null "${OOBE_HOME}/.config/systemd/user/dbus-org.freedesktop.impl.portal.desktop.kwallet.service"

        cat << 'EOF' > "${OOBE_HOME}/.config/autostart/sourceless-oobe.desktop"
[Desktop Entry]
Type=Application
Name=SourceLess OS First-Boot Setup
Exec=/usr/bin/python3 /usr/bin/sourceless-oobe.py
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
        restorecon -RF /etc/sddm.conf.d /etc/sourceless 2>/dev/null || true
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

    # Sync global SourcelessGlass lock screen theme without overwriting user [Daemon] timeouts
    if [ -f /etc/xdg/kscreenlockerrc ]; then
        mkdir -p "${USER_HOME}/.config"
        if [ ! -f "${USER_HOME}/.config/kscreenlockerrc" ]; then
            cp -f /etc/xdg/kscreenlockerrc "${USER_HOME}/.config/kscreenlockerrc"
        elif command -v kwriteconfig6 >/dev/null 2>&1; then
            kwriteconfig6 --file "${USER_HOME}/.config/kscreenlockerrc" --group Greeter --key Theme "org.sourceless.desktop" 2>/dev/null || true
            kwriteconfig6 --file "${USER_HOME}/.config/kscreenlockerrc" --group Greeter --key WallpaperPlugin "org.kde.image" 2>/dev/null || true
            kwriteconfig6 --file "${USER_HOME}/.config/kscreenlockerrc" --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "/usr/share/wallpapers/SourceLess/contents/images_dark/3840x2160.jpg" 2>/dev/null || true
            kwriteconfig6 --file "${USER_HOME}/.config/kscreenlockerrc" --group Greeter --group Wallpaper --group org.kde.image --group General --key PreviewImage "/usr/share/wallpapers/SourceLess/contents/images_dark/3840x2160.jpg" 2>/dev/null || true
        fi
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
