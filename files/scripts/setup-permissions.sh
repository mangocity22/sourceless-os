#!/usr/bin/bash
# =============================================================================
# SourceLess OS Build-Time Security and System Branding Setup
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
    kdialog --error "Access Denied. Terminal execution is restricted on SourceLess OS." --title "Security Policy"
    exit 1
fi
EOF

chmod +x /usr/bin/konsole

# Unhide native Konsole desktop launcher and mask Flatpak
KONSOLE_DESKTOP="/usr/share/applications/org.kde.konsole.desktop"
if [ -f "$KONSOLE_DESKTOP" ]; then
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
chmod 700 /usr/bin/sourceless-cert-verify.sh 2>/dev/null || true
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
chmod +x /usr/bin/sourceless-support-dialog.py 2>/dev/null || true
chmod 755 /usr/bin/sourceless-installer-helper.py /usr/bin/sourceless-oobe.py /usr/bin/sourceless-oobe-apply /usr/bin/sourceless-direct-installer /usr/bin/sourceless-direct-installer-inner 2>/dev/null || true
chmod 755 /etc/xdg/plasma-workspace/env/sourceless-vm-cursor.sh 2>/dev/null || true

# -----------------------------------------------------------------------------
# 3. User Privilege and Clean Home Directory Permissions
# -----------------------------------------------------------------------------

systemctl --global mask kdeconnectd.service 2>/dev/null || true
systemctl --global mask drkonqi-coredump-pickup.service drkonqi-coredump-launcher.socket 2>/dev/null || true
rm -f /etc/xdg/autostart/*drkonqi*.desktop 2>/dev/null || true

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
flatpak remote-delete --system --force fedora 2>/dev/null || true
flatpak remote-delete --system --force fedora-testing 2>/dev/null || true
rm -f /etc/flatpak/remotes.d/fedora*.flatpakrepo /usr/share/flatpak/remotes.d/fedora*.flatpakrepo 2>/dev/null || true
systemctl mask flatpak-add-fedora-repos.service 2>/dev/null || true
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
systemctl enable sourceless-shield.service 2>/dev/null || true
systemctl enable systemd-resolved.service 2>/dev/null || true

systemctl mask fedora-atomic-desktop-appstream-cache-refresh.service 2>/dev/null || true
systemctl enable rustdesk.service 2>/dev/null || true

# -----------------------------------------------------------------------------
# 6. Official OS Release Identification & Anaconda / Release Rebranding
# -----------------------------------------------------------------------------

echo "[Sourceless] Patching OS release metadata to SourceLess OS..."
VER_ID="$(grep -m1 '^VERSION_ID=' /usr/lib/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')"
[ -z "$VER_ID" ] && VER_ID="45"

set_os_key() {
    local file="$1"
    local key="$2"
    local val="$3"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed -i --follow-symlinks "s|^${key}=.*|${key}=${val}|" "$file" 2>/dev/null || true
    else
        echo "${key}=${val}" >> "$file"
    fi
}

for os_target in /usr/lib/os-release /etc/os-release; do
    if [ -f "$os_target" ] && [ ! -L "$os_target" ]; then
        sed -i '/^REDHAT_BUGZILLA_/d; /^REDHAT_SUPPORT_/d' "$os_target" 2>/dev/null || true
        set_os_key "$os_target" "NAME" '"SourceLess OS"'
        set_os_key "$os_target" "PRETTY_NAME" '"SourceLess OS"'
        set_os_key "$os_target" "VERSION" "\"${VER_ID} (SourceLess OS)\""
        set_os_key "$os_target" "ID" "sourceless"
        set_os_key "$os_target" "ID_LIKE" '"fedora"'
        set_os_key "$os_target" "VARIANT" '"SourceLess OS"'
        set_os_key "$os_target" "VARIANT_ID" "sourceless"
        set_os_key "$os_target" "VENDOR_NAME" '"SourceLess"'
        set_os_key "$os_target" "VENDOR_URL" '"https://sourceless.net"'
        set_os_key "$os_target" "HOME_URL" '"https://sourceless.net"'
        set_os_key "$os_target" "DOCUMENTATION_URL" '"https://sourceless.net"'
        set_os_key "$os_target" "SUPPORT_URL" '"https://sourceless.net"'
        set_os_key "$os_target" "BUG_REPORT_URL" '"https://sourceless.net"'
        set_os_key "$os_target" "PRIVACY_POLICY_URL" '"https://sourceless.net"'
        set_os_key "$os_target" "CPE_NAME" "\"cpe:/o:sourceless:sourceless_os:${VER_ID}\""
        set_os_key "$os_target" "LOGO" "sourceless-logo"
        set_os_key "$os_target" "DEFAULT_HOSTNAME" "sourceless"
        sed -i 's/Fedora/SourceLess OS/g; s/Kinoite/SourceLess OS/g' "$os_target" 2>/dev/null || true
    fi
done

for rel_file in /usr/lib/fedora-release /etc/fedora-release /usr/lib/system-release /etc/system-release /usr/lib/redhat-release /etc/redhat-release; do
    if [ -f "$rel_file" ] && [ ! -L "$rel_file" ]; then
        echo "SourceLess OS release ${VER_ID}" > "$rel_file"
    fi
done

for cpe_file in /usr/lib/system-release-cpe /etc/system-release-cpe; do
    if [ -f "$cpe_file" ] && [ ! -L "$cpe_file" ]; then
        echo "cpe:/o:sourceless:sourceless_os:${VER_ID}" > "$cpe_file"
    fi
done

for issue_file in /usr/lib/issue /etc/issue; do
    if [ -f "$issue_file" ] && [ ! -L "$issue_file" ]; then
        printf 'SourceLess OS \\S\nKernel \\r on an \\m (\\l)\n\n' > "$issue_file"
    fi
done
if [ -f /etc/issue.net ] && [ ! -L /etc/issue.net ]; then
    echo "SourceLess OS" > /etc/issue.net
fi

if [ -f /usr/share/applications/liveinst.desktop ]; then
    sed -i 's/^Name=.*/Name=Install SourceLess OS/; s/^GenericName=.*/GenericName=Install SourceLess OS/; s/^Comment=.*/Comment=Install SourceLess OS to Hard Drive/; s/^Icon=.*/Icon=sourceless-logo/; s/Fedora/SourceLess OS/g' /usr/share/applications/liveinst.desktop 2>/dev/null || true
fi
if [ -f /usr/bin/liveinst ]; then
    sed -i 's/ANACONDA_PRODUCTNAME=.*/ANACONDA_PRODUCTNAME="SourceLess OS"/g; s/Fedora/SourceLess OS/g' /usr/bin/liveinst 2>/dev/null || true
fi
for anaconda_conf in /etc/anaconda/profile.d/*.conf; do
    if [ -f "$anaconda_conf" ]; then
        sed -i 's/product_name = .*/product_name = SourceLess OS/g; s/Fedora/SourceLess OS/g' "$anaconda_conf" 2>/dev/null || true
    fi
done

if [ -f /etc/anaconda/anaconda.conf ]; then
    if grep -q "^profile_id\s*=" /etc/anaconda/anaconda.conf; then
        sed -i 's/^profile_id\s*=.*/profile_id = sourceless/' /etc/anaconda/anaconda.conf 2>/dev/null || true
    elif grep -q "^\[Profile\]" /etc/anaconda/anaconda.conf; then
        sed -i '/^\[Profile\]/a profile_id = sourceless' /etc/anaconda/anaconda.conf 2>/dev/null || true
    fi
fi

# Propagate dark GTK3/GTK4 settings to root, roothome, and user skeleton
for gtk_home in /root/.config /var/roothome/.config /etc/skel/.config; do
    mkdir -p "$gtk_home/gtk-3.0" "$gtk_home/gtk-4.0"
    cp -f /etc/gtk-3.0/settings.ini "$gtk_home/gtk-3.0/settings.ini" 2>/dev/null || true
    cp -f /etc/gtk-4.0/settings.ini "$gtk_home/gtk-4.0/settings.ini" 2>/dev/null || true
done

# Apply SourceLess OS GTK stylesheet and logo assets for Anaconda & Cockpit branding
if [ -f /usr/share/sourceless/installer/anaconda-gtk.css ] && [ -d /usr/share/anaconda ]; then
    cp -f /usr/share/sourceless/installer/anaconda-gtk.css /usr/share/anaconda/anaconda-gtk.css 2>/dev/null || true
fi

LOGO_SVG="/usr/share/icons/hicolor/scalable/apps/sourceless-logo.svg"
LOGO_PNG="/usr/share/icons/hicolor/scalable/apps/sourceless-logo.png"

if [ -d /usr/share/anaconda/pixmaps ]; then
    for f in /usr/share/anaconda/pixmaps/*logo* /usr/share/anaconda/pixmaps/*sidebar* /usr/share/anaconda/pixmaps/*fedora*; do
        if [ -f "$f" ]; then
            case "$f" in
                *.svg) [ -f "$LOGO_SVG" ] && cp -f "$LOGO_SVG" "$f" 2>/dev/null || true ;;
                *.png) [ -f "$LOGO_PNG" ] && cp -f "$LOGO_PNG" "$f" 2>/dev/null || true ;;
            esac
        fi
    done
fi

for brand_dir in /usr/share/cockpit/branding/*; do
    if [ -d "$brand_dir" ]; then
        for f in "$brand_dir"/*.svg "$brand_dir"/*.png; do
            if [ -f "$f" ]; then
                case "$f" in
                    *logo*.svg|*fedora*.svg) [ -f "$LOGO_SVG" ] && cp -f "$LOGO_SVG" "$f" 2>/dev/null || true ;;
                    *logo*.png|*fedora*.png) [ -f "$LOGO_PNG" ] && cp -f "$LOGO_PNG" "$f" 2>/dev/null || true ;;
                esac
            fi
        done
    fi
done

# Theme and rebrand Anaconda WebUI (Fedora 45 Cockpit / PatternFly 5 & 6)
WEBUI_DIR="/usr/share/cockpit/anaconda-webui"
if [ -d "$WEBUI_DIR" ]; then
    echo "[Sourceless] Applying LockScreen-inspired Cyber Dark theme to Anaconda WebUI..."
    find "$WEBUI_DIR" -type f -name "*.gz" -exec gunzip -f {} + 2>/dev/null || true

    cp -f /usr/share/sourceless/installer/sourceless-webui.css "$WEBUI_DIR/sourceless-webui.css" 2>/dev/null || true
    cp -f /usr/share/sourceless/installer/sourceless-webui.js "$WEBUI_DIR/sourceless-webui.js" 2>/dev/null || true
    if [ -f "$LOGO_SVG" ]; then
        cp -f "$LOGO_SVG" "$WEBUI_DIR/sourceless-logo.svg" 2>/dev/null || true
        cp -f "$LOGO_SVG" "$WEBUI_DIR/logo.svg" 2>/dev/null || true
    fi

    find "$WEBUI_DIR" -type f \( -iname "*fedora*.svg" -o -iname "*logo*.svg" \) ! -name "sourceless-logo.svg" ! -name "logo.svg" | while read -r asset; do
        [ -f "$LOGO_SVG" ] && cp -f "$LOGO_SVG" "$asset" 2>/dev/null || true
    done
    find "$WEBUI_DIR" -type f \( -iname "*fedora*.png" -o -iname "*logo*.png" \) | while read -r asset; do
        [ -f "$LOGO_PNG" ] && cp -f "$LOGO_PNG" "$asset" 2>/dev/null || true
    done

    if [ -f "$WEBUI_DIR/index.css" ] && [ -f "$WEBUI_DIR/sourceless-webui.css" ]; then
        cat "$WEBUI_DIR/sourceless-webui.css" >> "$WEBUI_DIR/index.css"
    fi

    if [ -f "$WEBUI_DIR/index.html" ]; then
        if ! grep -qE '<html[^>]*class=' "$WEBUI_DIR/index.html"; then
            sed -i 's/<html/<html class="pf-v5-theme-dark pf-v6-theme-dark"/g' "$WEBUI_DIR/index.html" 2>/dev/null || true
        else
            sed -i 's/\(<html[^>]*class=["'\'']\)/\1pf-v5-theme-dark pf-v6-theme-dark /g' "$WEBUI_DIR/index.html" 2>/dev/null || true
        fi
        sed -i 's|<title>[^<]*</title>|<title>SourceLess OS Installer</title>|g' "$WEBUI_DIR/index.html" 2>/dev/null || true
        if ! grep -q "sourceless-webui.css" "$WEBUI_DIR/index.html"; then
            sed -i 's|</head>|<link rel="stylesheet" href="sourceless-webui.css">\n<script src="sourceless-webui.js" defer></script>\n</head>|g' "$WEBUI_DIR/index.html" 2>/dev/null || true
        fi
    fi

    find "$WEBUI_DIR" -type f \( -name "*.js" -o -name "*.json" -o -name "*.html" \) ! -name "sourceless-webui.js" | while read -r webfile; do
        sed -i 's/Fedora Linux/SourceLess OS/g; s/Fedora Kinoite/SourceLess OS/g; s/Fedora/SourceLess OS/g; s/Kinoite/SourceLess OS/g' "$webfile" 2>/dev/null || true
    done

    for gz_target in "$WEBUI_DIR/index.html" "$WEBUI_DIR/index.css" "$WEBUI_DIR/index.js" "$WEBUI_DIR"/po.*.js; do
        if [ -f "$gz_target" ]; then
            gzip -k -f "$gz_target" 2>/dev/null || true
        fi
    done
fi

# Enforce English (US) as system default locale
printf 'LANG="en_US.UTF-8"\n' > /etc/locale.conf
chmod 644 /etc/locale.conf 2>/dev/null || true

# Inject optional custom disk allocation ceiling into Blivet for Installation method slider
for blivet_py in /usr/lib/python3.*/site-packages/blivet/blivet.py; do
    if [ -f "$blivet_py" ] && ! grep -q "SOURCELESS_DISK_LIMIT_HOOK" "$blivet_py"; then
        cat << 'EOF' >> "$blivet_py"

# --- SOURCELESS_DISK_LIMIT_HOOK ---
try:
    import inspect as _sl_inspect
    import os as _sl_os
    from blivet.devices import PartitionDevice as _sl_PartitionDevice
    from blivet.size import Size as _sl_Size

    _sl_orig_new_partition = Blivet.new_partition
    _sl_pd_params = _sl_inspect.signature(_sl_PartitionDevice.__init__).parameters
    _sl_np_params = _sl_inspect.signature(_sl_orig_new_partition).parameters
    _sl_max_kw = "max_size" if ("max_size" in _sl_np_params or "max_size" in _sl_pd_params) else "maxsize"

    def _sl_capped_new_partition(self, *args, **kwargs):
        limit_file = "/run/anaconda/sourceless_max_disk_gib"
        if kwargs.get("grow") and _sl_os.path.exists(limit_file):
            try:
                with open(limit_file, "r", encoding="utf-8") as _fh:
                    limit_gib = float(_fh.read().strip())
                if limit_gib >= 16:
                    target_gib = max(12.0, limit_gib - 2.0)
                    cap = _sl_Size(f"{int(target_gib * 1024)} MiB")
                    cur_max = kwargs.get(_sl_max_kw)
                    if cur_max is None or cur_max > cap:
                        kwargs[_sl_max_kw] = cap
            except Exception:
                pass
        return _sl_orig_new_partition(self, *args, **kwargs)

    Blivet.new_partition = _sl_capped_new_partition
except Exception:
    pass
EOF
    fi
done

chmod 644 /etc/xdg/kcm-about-distrorc 2>/dev/null || true

# -----------------------------------------------------------------------------
# 7. GRUB Bootloader Configuration & Compilation
# -----------------------------------------------------------------------------

echo "[Sourceless] Configuring GRUB theme and compiling configuration..."
if [ -f /etc/default/grub ]; then
    sed -i 's|^GRUB_THEME=.*|GRUB_THEME="/usr/share/grub/themes/sourceless/theme.txt"|' /etc/default/grub 2>/dev/null || true
    if ! grep -q "^GRUB_THEME=" /etc/default/grub; then
        echo 'GRUB_THEME="/usr/share/grub/themes/sourceless/theme.txt"' >> /etc/default/grub
    fi
    sed -i 's|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR="SourceLess OS"|' /etc/default/grub 2>/dev/null || true
    if ! grep -q "^GRUB_DISTRIBUTOR=" /etc/default/grub; then
        echo 'GRUB_DISTRIBUTOR="SourceLess OS"' >> /etc/default/grub
    fi
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub 2>/dev/null || true
    sed -i 's/^GRUB_TERMINAL_OUTPUT=.*/GRUB_TERMINAL_OUTPUT="gfxterm"/' /etc/default/grub 2>/dev/null || true
fi

THEME_DIR="/usr/share/grub/themes/sourceless"
if [ -d "$THEME_DIR" ]; then
    TTF_SRC=$(find /usr/share/fonts -name "DejaVuSans.ttf" 2>/dev/null | head -n 1)
    if [ -n "$TTF_SRC" ] && command -v grub2-mkfont >/dev/null 2>&1; then
        grub2-mkfont -s 16 -n "Sourceless Regular" -o "$THEME_DIR/font-16.pf2" "$TTF_SRC" 2>/dev/null || true
        grub2-mkfont -s 14 -n "Sourceless Regular" -o "$THEME_DIR/font-14.pf2" "$TTF_SRC" 2>/dev/null || true
    fi
    if [ ! -f "$THEME_DIR/font-16.pf2" ] && [ -f /usr/share/grub/unicode.pf2 ]; then
        cp -f /usr/share/grub/unicode.pf2 "$THEME_DIR/font-16.pf2" 2>/dev/null || true
    fi
fi

if command -v grub2-mkconfig >/dev/null 2>&1; then
    echo "[Sourceless] Running grub2-mkconfig..."
    grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
    if [ -d /boot/efi/EFI/fedora ]; then
        grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg 2>/dev/null || true
    fi
fi

for bls_file in /boot/loader/entries/*.conf /usr/lib/ostree-boot/loader/entries/*.conf /usr/lib/modules/*/bls.conf; do
    if [ -f "$bls_file" ]; then
        sed -i '/^title /s/Fedora Linux/SourceLess OS/g; /^title /s/Fedora/SourceLess OS/g; /^title /s/Sourceless OS/SourceLess OS/g; /^title /s/ (Kinoite)//g' "$bls_file" 2>/dev/null || true
    fi
done

for grub_cfg in /boot/grub2/grub.cfg /boot/efi/EFI/fedora/grub.cfg; do
    if [ -f "$grub_cfg" ]; then
        sed -i '/menuentry \|submenu \|^set /s/Fedora Linux/SourceLess OS/g; /menuentry \|submenu \|^set /s/Fedora/SourceLess OS/g; /menuentry \|submenu \|^set /s/Sourceless OS/SourceLess OS/g; /menuentry \|submenu \|^set /s/ (Kinoite)//g' "$grub_cfg" 2>/dev/null || true
    fi
done

# -----------------------------------------------------------------------------
# 8. Wallpaper Packaging & Safe Global KDE Enforcement
# -----------------------------------------------------------------------------

echo "[Sourceless] Applying custom wallpapers safely..."
WALLPAPER_DARK="/usr/share/wallpapers/SourceLess/contents/images_dark/3840x2160.jpg"
chmod 644 /usr/share/wallpapers/SourceLess/metadata.json 2>/dev/null || true

# Lock Screen, SDDM & Plasma Login Manager Liquid Glass Enforcement
mkdir -p /etc/xdg
cat << 'EOF' > /etc/xdg/kscreenlockerrc
[Greeter]
Theme=org.sourceless.desktop
WallpaperPlugin=org.kde.image

[Greeter][Wallpaper][org.kde.image][General]
Image=/usr/share/wallpapers/SourceLess/contents/images_dark/3840x2160.jpg
PreviewImage=/usr/share/wallpapers/SourceLess/contents/images_dark/3840x2160.jpg
EOF
chmod 644 /etc/xdg/kscreenlockerrc 2>/dev/null || true
cp -f /etc/xdg/kscreenlockerrc /etc/skel/.config/kscreenlockerrc 2>/dev/null || true

# Integrate Sourceless Liquid Glass Lock Screen & Logout Screen into Plasma 6 Desktop Shell fallback (preserve qmldir/config.xml)
SOURCELESS_LOCKSCREEN="/usr/share/plasma/look-and-feel/org.sourceless.desktop/contents/lockscreen"
SHELL_LOCKSCREEN="/usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen"
if [ -d "$SOURCELESS_LOCKSCREEN" ] && [ -d "$SHELL_LOCKSCREEN" ]; then
    cp -f "$SOURCELESS_LOCKSCREEN/LockScreen.qml" "$SHELL_LOCKSCREEN/LockScreen.qml" 2>/dev/null || true
    cp -f "$SOURCELESS_LOCKSCREEN/LockScreenUi.qml" "$SHELL_LOCKSCREEN/LockScreenUi.qml" 2>/dev/null || true
fi

SOURCELESS_LOGOUT="/usr/share/plasma/look-and-feel/org.sourceless.desktop/contents/logout"
SHELL_LOGOUT="/usr/share/plasma/shells/org.kde.plasma.desktop/contents/logout"
if [ -f "$SOURCELESS_LOGOUT/Logout.qml" ] && [ -d "$SHELL_LOGOUT" ]; then
    cp -f "$SOURCELESS_LOGOUT/Logout.qml" "$SHELL_LOGOUT/Logout.qml" 2>/dev/null || true
fi

# Switch Display Manager from plasmalogin (no custom QML themes) to SDDM (SourcelessGlass Liquid Glass theme)
systemctl disable plasmalogin.service 2>/dev/null || true
systemctl enable sddm.service 2>/dev/null || true
ln -sf /usr/lib/systemd/system/sddm.service /etc/systemd/system/display-manager.service 2>/dev/null || true

for sddm_theme in /usr/share/sddm/themes/*; do
    if [ -d "$sddm_theme" ]; then
        cat << EOF > "$sddm_theme/theme.conf.user"
[General]
background=$WALLPAPER_DARK
EOF
    fi
done

mkdir -p /etc/plasmalogin.conf.d
cat << 'EOF' > /etc/plasmalogin.conf.d/10-sourceless.conf
[Greeter]
WallpaperPlugin=org.kde.image
WallpaperPluginId=org.kde.image

[Greeter][Wallpaper][org.kde.image][General]
Image=/usr/share/wallpapers/SourceLess/contents/images_dark/3840x2160.jpg
PreviewImage=/usr/share/wallpapers/SourceLess/contents/images_dark/3840x2160.jpg
EOF
chmod 644 /etc/plasmalogin.conf.d/10-sourceless.conf 2>/dev/null || true
cp -f /etc/plasmalogin.conf.d/10-sourceless.conf /etc/xdg/plasmaloginrc 2>/dev/null || true

# Sync SourcelessGlass theme, color scheme & KWin blur into Plasma Login Manager greeter config
if id "plasmalogin" &>/dev/null || [ -d /var/lib/plasmalogin ]; then
    mkdir -p /var/lib/plasmalogin/.config
    cp -f /etc/xdg/kdeglobals /var/lib/plasmalogin/.config/kdeglobals 2>/dev/null || true
    cp -f /etc/xdg/plasmarc /var/lib/plasmalogin/.config/plasmarc 2>/dev/null || true
    cp -f /etc/xdg/kwinrc /var/lib/plasmalogin/.config/kwinrc 2>/dev/null || true
    chown -R plasmalogin:plasmalogin /var/lib/plasmalogin 2>/dev/null || true
fi

# Purge upstream default wallpapers and replace with symlinks to SourceLess
rm -rf /usr/share/backgrounds/* 2>/dev/null || true
UPSTREAM_DEFAULTS=("Waterfall" "Next" "Breeze" "Altai" "Flow" "Shell" "Opal" "Kay" "Sub-Arctic" "Horos" "Fedora" "F44" "F45")
MAIN_TARGET="/usr/share/wallpapers/SourceLess"

for wp in "${UPSTREAM_DEFAULTS[@]}"; do
    WP_PATH="/usr/share/wallpapers/$wp"
    if [ -d "$WP_PATH" ] || [ -L "$WP_PATH" ]; then
        rm -rf "$WP_PATH"
        if [ -d "$MAIN_TARGET" ]; then
            ln -sf "$MAIN_TARGET" "$WP_PATH"
        fi
    fi
done

shopt -s nocasematch
for wp_dir in /usr/share/wallpapers/*; do
    dir_name=$(basename "$wp_dir")
    if [[ ! "$dir_name" =~ sourceless ]] && [[ ! " ${UPSTREAM_DEFAULTS[*]} " =~ " ${dir_name} " ]]; then
        rm -rf "$wp_dir"
    fi
done
shopt -u nocasematch

for custom_wp in /usr/share/wallpapers/*; do
    if [ -d "$custom_wp" ] && [ ! -L "$custom_wp" ]; then
        name=$(basename "$custom_wp")
        if [ ! -f "$custom_wp/metadata.json" ]; then
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

cat << 'EOF' >> /etc/xdg/kdeglobals

[Wallpaper]
defaultWallpaperTheme=SourceLess
defaultFile=/usr/share/wallpapers/SourceLess/contents/images_dark/3840x2160.jpg
EOF

# -----------------------------------------------------------------------------
# 9. Visual Branding & Desktop Layout Enforcement for Fresh ISO Installs
# -----------------------------------------------------------------------------

echo "[Sourceless] Injecting branding icons into Breeze themes..."
START_SRC="/usr/share/icons/hicolor/scalable/apps/start-here.svg"
LOGO_SVG="/usr/share/icons/hicolor/scalable/apps/sourceless-logo.svg"
LOGO_PNG="/usr/share/icons/hicolor/scalable/apps/sourceless-logo.png"
APPS_SRC="/usr/share/icons/breeze/apps/scalable"

if [ -f "$START_SRC" ]; then
    for theme in breeze breeze-dark; do
        for size_dir in /usr/share/icons/"$theme"/places/*; do
            if [ -d "$size_dir" ]; then
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

if [ -f "$LOGO_SVG" ]; then
    for theme in breeze breeze-dark; do
        for size_dir in /usr/share/icons/"$theme"/apps/*; do
            if [ -d "$size_dir" ]; then
                cp -f "$LOGO_SVG" "$size_dir/sourceless-logo.svg" 2>/dev/null || true
                cp -f "$LOGO_SVG" "$size_dir/distributor-logo.svg" 2>/dev/null || true
                cp -f "$LOGO_SVG" "$size_dir/distributor-logo-fedora.svg" 2>/dev/null || true
                cp -f "$LOGO_SVG" "$size_dir/fedora-logo-icon.svg" 2>/dev/null || true
            fi
        done

        if [ -d "/usr/share/icons/$theme/places/scalable" ]; then
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

if [ -f "$LOGO_PNG" ]; then
    cp -f "$LOGO_PNG" /usr/share/pixmaps/sourceless-logo.png 2>/dev/null || true
    cp -f "$LOGO_PNG" /usr/share/pixmaps/distributor-logo.png 2>/dev/null || true
    cp -f "$LOGO_PNG" /usr/share/pixmaps/fedora-logo.png 2>/dev/null || true
    cp -f "$LOGO_PNG" /usr/share/pixmaps/system-logo-white.png 2>/dev/null || true
fi

if [ -d "$APPS_SRC" ]; then
    for theme in breeze breeze-dark; do
        for size_dir in /usr/share/icons/"$theme"/apps/*; do
            if [ -d "$size_dir" ]; then
                [ -f "$APPS_SRC/org.kde.dolphin.svg" ] && cp -f "$APPS_SRC/org.kde.dolphin.svg" "$size_dir/org.kde.dolphin.svg" 2>/dev/null || true
                [ -f "$APPS_SRC/org.kde.dolphin.svg" ] && cp -f "$APPS_SRC/org.kde.dolphin.svg" "$size_dir/system-file-manager.svg" 2>/dev/null || true
                [ -f "$APPS_SRC/org.kde.konsole.svg" ] && cp -f "$APPS_SRC/org.kde.konsole.svg" "$size_dir/utilities-terminal.svg" 2>/dev/null || true
                [ -f "$APPS_SRC/org.kde.konsole.svg" ] && cp -f "$APPS_SRC/org.kde.konsole.svg" "$size_dir/org.kde.konsole.svg" 2>/dev/null || true
                [ -f "$APPS_SRC/systemsettings.svg" ] && cp -f "$APPS_SRC/systemsettings.svg" "$size_dir/preferences-system.svg" 2>/dev/null || true
                [ -f "$APPS_SRC/systemsettings.svg" ] && cp -f "$APPS_SRC/systemsettings.svg" "$size_dir/systemsettings.svg" 2>/dev/null || true
                [ -f "$APPS_SRC/plasmadiscover.svg" ] && cp -f "$APPS_SRC/plasmadiscover.svg" "$size_dir/plasmadiscover.svg" 2>/dev/null || true
                [ -f "$APPS_SRC/plasmadiscover.svg" ] && cp -f "$APPS_SRC/plasmadiscover.svg" "$size_dir/org.kde.discover.svg" 2>/dev/null || true
            fi
        done
    done
fi

# Enforce global SourcelessGlass theme and KWin compositor effects
echo "[Sourceless] Enforcing SourcelessGlass desktop theme and GPU blur..."
mkdir -p /etc/xdg
kwriteconfig6 --file /etc/xdg/plasmarc --group Theme --key name "SourcelessGlass" 2>/dev/null || true
kwriteconfig6 --file /etc/xdg/kwinrc --group Plugins --key blurEnabled "true" 2>/dev/null || true
kwriteconfig6 --file /etc/xdg/kwinrc --group Plugins --key contrastEnabled "true" 2>/dev/null || true
kwriteconfig6 --file /etc/xdg/kwinrc --group Plugins --key invertEnabled "true" 2>/dev/null || true

# Sync the default panel layout.js into all Look-and-Feel packages for clean ISO installs
LAYOUT_SRC="/usr/share/plasma/layout-templates/org.kde.plasma.desktop.defaultPanel/contents/layout.js"
if [ -f "$LAYOUT_SRC" ]; then
    echo "[Sourceless] Linking Sourceless multi-panel layout to Look-and-Feel packages..."
    for lnf in /usr/share/plasma/look-and-feel/*; do
        if [ -d "$lnf" ]; then
            TARGET_DIR="$lnf/contents/layouts/org.kde.plasma.desktop.defaultPanel/contents"
            mkdir -p "$TARGET_DIR"
            cp -f "$LAYOUT_SRC" "$TARGET_DIR/layout.js" 2>/dev/null || true
        fi
    done
fi

# -----------------------------------------------------------------------------
# 10. Ensure UEFI Boot Binaries Exist at /boot/efi/EFI for Titanoboa Live ISO
# -----------------------------------------------------------------------------

mkdir -p /boot/efi/EFI/fedora /boot/efi/EFI/BOOT
if [ ! -f /boot/efi/EFI/BOOT/BOOTX64.EFI ] || [ ! -f /boot/efi/EFI/fedora/grubx64.efi ]; then
    echo "[Sourceless] Populating /boot/efi/EFI for Titanoboa Live ISO..."
    find /usr /boot -maxdepth 6 -type f \( -iname "BOOTX64.EFI" -o -iname "fbx64.efi" \) -exec cp -af {} /boot/efi/EFI/BOOT/ \; 2>/dev/null || true
    find /usr /boot -maxdepth 6 -type f \( -iname "shimx64.efi" -o -iname "shim.efi" -o -iname "mmx64.efi" -o -iname "grubx64.efi" -o -iname "gcdx64.efi" -o -iname "BOOTX64.CSV" \) -exec cp -af {} /boot/efi/EFI/fedora/ \; 2>/dev/null || true
fi

if [ ! -f /boot/efi/EFI/BOOT/BOOTX64.EFI ] || [ ! -f /boot/efi/EFI/fedora/grubx64.efi ]; then
    echo "[Sourceless] Reinstalling shim-x64 and grub2-efi-x64 to populate /boot/efi/EFI..."
    dnf reinstall -y shim-x64 grub2-efi-x64 grub2-efi-x64-cdboot 2>/dev/null || true
fi

if [ ! -f /boot/efi/EFI/BOOT/BOOTX64.EFI ] && [ -f /boot/efi/EFI/fedora/shimx64.efi ]; then
    cp -af /boot/efi/EFI/fedora/shimx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI
fi
if [ ! -f /boot/efi/EFI/BOOT/grubx64.efi ] && [ -f /boot/efi/EFI/fedora/grubx64.efi ]; then
    cp -af /boot/efi/EFI/fedora/grubx64.efi /boot/efi/EFI/BOOT/grubx64.efi
fi
ls -la /boot/efi/EFI/BOOT/ /boot/efi/EFI/fedora/ || true

if [ -d /usr/share/plymouth/themes/bgrt ]; then
    cp -f /usr/share/plymouth/themes/spinner/watermark.png /usr/share/plymouth/themes/bgrt/watermark.png 2>/dev/null || true
    cp -f /usr/share/plymouth/themes/spinner/sourceless-logo.png /usr/share/plymouth/themes/bgrt/sourceless-logo.png 2>/dev/null || true
fi

if command -v dracut >/dev/null 2>&1; then
    mkdir -p /var/tmp /tmp /etc/dracut.conf.d
    for conf in /etc/dracut.conf.d/*.conf /usr/lib/dracut/dracut.conf.d/*.conf; do
        if [ -f "$conf" ] && grep -q "dmsquash-live\|pollcdrom" "$conf" 2>/dev/null; then
            sed -i 's/dmsquash-live-autooverlay//g; s/dmsquash-live//g; s/pollcdrom//g' "$conf" || true
        fi
    done
    cat << 'EOF' > /etc/dracut.conf.d/99-sourceless-live.conf
add_dracutmodules+=" dmsquash-live dmsquash-live-autooverlay pollcdrom "
add_drivers+=" squashfs overlay loop isofs sr_mod cdrom btrfs ext4 xfs vfat nvme "
hostonly="no"
hostonly_cmdline="no"
EOF
    for kver_dir in /usr/lib/modules/*; do
        if [ -d "$kver_dir" ] && [ -f "$kver_dir/vmlinuz" ]; then
            kver="$(basename "$kver_dir")"
            echo "[Sourceless] Regenerating initramfs for $kver with dmsquash-live..."
            dracut --no-hostonly --no-hostonly-cmdline --kver "$kver" --force --force-add "dmsquash-live dmsquash-live-autooverlay pollcdrom" --add-drivers "squashfs overlay loop isofs sr_mod cdrom btrfs ext4 xfs vfat nvme" "$kver_dir/initramfs.img" > /tmp/dracut.log 2>&1 || {
                echo "[Sourceless] ERROR: dracut exited non-zero!"
                tail -n 30 /tmp/dracut.log
                exit 1
            }
            MODULES_LIST="$(lsinitrd -m "$kver_dir/initramfs.img" 2>/dev/null || true)"
            if ! echo "$MODULES_LIST" | grep -F "dmsquash-live" >/dev/null; then
                echo "[Sourceless] ERROR: dmsquash-live missing from $kver_dir/initramfs.img!"
                echo "$MODULES_LIST"
                exit 1
            fi
            echo "[Sourceless] Verified dmsquash-live in $kver_dir/initramfs.img"

            # Populate /boot with kernel and initramfs for LiveOS rsync installs and grub2-mkconfig
            mkdir -p /boot
            cp -f "$kver_dir/vmlinuz" "/boot/vmlinuz-${kver}" 2>/dev/null || true
            cp -f "$kver_dir/initramfs.img" "/boot/initramfs-${kver}.img" 2>/dev/null || true
            [ -f "$kver_dir/System.map" ] && cp -f "$kver_dir/System.map" "/boot/System.map-${kver}" 2>/dev/null || true
            [ -f "$kver_dir/config" ] && cp -f "$kver_dir/config" "/boot/config-${kver}" 2>/dev/null || true
        fi
    done
fi

# -----------------------------------------------------------------------------
# 11. Rebuild Icon Caches and Desktop Databases
# -----------------------------------------------------------------------------

echo "[Sourceless] Regenerating system icon caches and application metadata..."
update-desktop-database /usr/share/applications 2>/dev/null || true

for theme_dir in /usr/share/icons/*; do
    if [ -d "$theme_dir" ]; then
        touch "$theme_dir" 2>/dev/null || true
        gtk-update-icon-cache -f -q "$theme_dir" 2>/dev/null || true
    fi
done

echo "[Sourceless] setup-permissions.sh completed successfully."