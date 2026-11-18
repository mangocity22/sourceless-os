# Sourceless OS &nbsp; [![bluebuild build badge](https://github.com/blue-build/template/actions/workflows/build.yml/badge.svg)](../../actions/workflows/build.yml)

**Sourceless OS** is a hardened, immutable desktop Linux image built with [BlueBuild](https://blue-build.org/) on top of Universal Blue's **Fedora Kinoite** (`ghcr.io/ublue-os/kinoite-main`), featuring **KDE Plasma 6 (Wayland)**, custom **SourcelessGlass** theming, kernel/user-space lockdown controls, real-time YARA threat scanning, and a native **Sourceless Control Center**.

---

## Repository Structure

```text
.
├── .github/workflows/
│   ├── build.yml                 # Daily & push-triggered OCI image build + Cosign signing
│   └── build-iso.yml             # Manual 2-in-1 Live + Installer ISO build (Titanoboa -> 7z volumes)
├── recipes/
│   └── recipe.yml                # Main BlueBuild image recipe (packages, Flatpaks, systemd, kargs)
├── files/
│   ├── scripts/
│   │   ├── setup-permissions.sh  # Terminal wrapper, permissions, Flatpak setup, branding, GRUB & dracut
│   │   ├── clean-default-themes.sh # Removes upstream Breeze/Fedora look-and-feel packages
│   │   └── build-control-center.sh # Builds & installs Sourceless Control Center during image build
│   ├── sourceless-control-center/ # Native Qt6 / KF6 / C++20 / QML Settings & Security app
│   │   ├── CMakeLists.txt
│   │   └── src/
│   │       ├── main.cpp          # CLI page routing & QML engine bootstrap
│   │       ├── SystemBackend.{h,cpp} # System, Display, Network, Bluetooth, CUPS, Apps, Security, A11y
│   │       ├── ControlCenter.qml # Frameless 10-page UI with instant setting search
│   │       └── icons/            # Embedded SVG icon resources
│   └── system/                   # Files copied directly onto `/` of the target OS image
│       ├── etc/                  # System configs: auditd, polkit, sudoers, sysctl, systemd, xdg, skel, YARA rules
│       └── usr/
│           ├── bin/              # Runtime daemons, guards, sandbox wrapper, support dialog & fix-home
│           ├── lib/              # bootc-image-builder iso.yaml & sourceless-fix-home.service
│           └── share/            # Desktop entries, GRUB/Plymouth/SDDM/Plasma/Aurorae/Kvantum themes & wallpapers
├── installer-config.toml         # Anaconda kickstart settings (graphical install, locked root account)
└── cosign.pub                    # Public key for verifying signed container images
```

---

## Key Architecture & Components

### Security & Lockdown
* **Kernel & Network Hardening**: Enforces `lockdown=integrity` via kernel arguments ([recipes/recipe.yml](recipes/recipe.yml)), restrictive `sysctl` parameters (`99-sourceless-security.conf`), disabled virtual TTYs (`disable-tty.conf`), and DNS-over-TLS + DNSSEC via Quad9/Cloudflare (`10-sourceless-dns.conf`).
* **Interactive Shell & Terminal Isolation**: Replaces `/usr/bin/konsole` with a gated wrapper (`konsole.real`) and enforces `sourceless-shell-guard.sh`, restricting interactive terminal access unless an authorized support session is active. Commands and `execve` calls are audited to `systemd-journald` and `auditd` (`sourceless.rules`).
* **Authorized Support & Tamper Seal**: Supports remote administrator assistance (`sourceless-client.service` + `sourceless-support-dialog.py` + RustDesk) and offline technician access (`sourceless-emergency-terminal` / `sourceless-unlock` via rolling UTC key), updating the tamper status monitored by the Control Center.
* **Real-Time Malware Protection & Sandboxing**: `sourceless-shield.service` watches `~/Downloads` and `~/.config/autostart` via `inotifywait` and invokes `sourceless-guard` with custom YARA signatures (`/etc/sourceless/rules/*.yar`), quarantining threats to `/var/quarantine`. `sourceless-sandbox` isolates untrusted binaries/AppImages with `bubblewrap`.
* **Application Policy**: Removes `PackageKit` and `fwupd`; enforces Flatpak from `verified` Flathub (`org.mozilla.firefox`, `com.github.tchx84.Flatseal`) with background updates via `sourceless-flatpak-update.timer`.

### Sourceless Control Center
A dedicated Qt6/Kirigami settings and telemetry center ([files/sourceless-control-center](files/sourceless-control-center)) compiled during image build via [files/scripts/build-control-center.sh](files/scripts/build-control-center.sh). It manages display scaling/rotation/Night Light, PipeWire audio, NetworkManager Wi-Fi, Bluetooth, CUPS printers, Flatpak apps, accessibility (KWin effects, Orca, AccessX), user account settings, and real-time security posture scoring.

### Desktop & Branding (`SourcelessGlass`)
* **Look-and-Feel**: `org.sourceless.desktop` (including Plasma 6 layout templates, custom lock screen, logout screen, and animated splash).
* **Display Manager**: SDDM with the `SourcelessGlass` QML theme.
* **Custom Plasmoids**: `org.sourceless.start` launcher and `org.sourceless.clock` widget.
* **First Boot & Live Session**: `sourceless-fix-home.service` handles both Live USB sessions (`liveuser` autologin + `liveinst` shortcut) and installed home directory ownership/SELinux context enforcement.

---

## Installation & ISO Generation

### Rebase an Existing Fedora Atomic System
1. Rebase to the unsigned image first to install signing keys and policies:
   ```bash
   rpm-ostree rebase ostree-unverified-registry:ghcr.io/<owner>/sourceless-os:latest
   systemctl reboot
   ```
2. Rebase to the signed image:
   ```bash
   rpm-ostree rebase ostree-image-signed:docker://ghcr.io/<owner>/sourceless-os:latest
   systemctl reboot
   ```

### Live + Installer ISO
Trigger the **Build ISO** workflow ([.github/workflows/build-iso.yml](.github/workflows/build-iso.yml)) via `workflow_dispatch`. It pulls the latest OCI image, builds a 2-in-1 Live/Installer ISO using `ublue-os/titanoboa`, splits it into 1.8 GB `.7z` volumes, and publishes them to the `latest-iso` GitHub Release.

### Image Signature Verification
```bash
cosign verify --key cosign.pub ghcr.io/<owner>/sourceless-os:latest
```
