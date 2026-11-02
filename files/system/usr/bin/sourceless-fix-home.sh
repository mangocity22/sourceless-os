#!/usr/bin/bash
set -euo pipefail

# Wait for the home directory to be mounted (essential for ostree systems)
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
    # Verificam daca lipseste configul sau daca scriptul e rulat cu argumentul "reset-ui"
    if [ ! -f /var/home/sourceless/.config/plasma-org.kde.plasma.desktop-appletsrc ] || [ "${1:-}" == "reset-ui" ]; then
        echo "Applying Factory Reset for KDE Plasma UI..."
        
        # Ne asiguram ca folderul .config exista
        mkdir -p /var/home/sourceless/.config/
        
        # Suprascriem fisierul cu versiunea perfecta din skel
        cp -f /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc /var/home/sourceless/.config/
        
        # Ne asiguram ca permisiunile raman in regula dupa copiere
        chown sourceless:sourceless /var/home/sourceless/.config/plasma-org.kde.plasma.desktop-appletsrc
        chmod 600 /var/home/sourceless/.config/plasma-org.kde.plasma.desktop-appletsrc
        
        # Daca un utilizator este logat in GUI, repornim shell-ul ca sa vada instant schimbarile
        if pgrep -u sourceless plasmashell > /dev/null; then
            sudo -u sourceless DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u sourceless)/bus" systemctl --user restart plasma-plasmashell 2>/dev/null || true
        fi
    fi

    # 3. Activam Starship si restauram contextul SELinux (partea ta existenta)
    if ! grep -q "starship init bash" /var/home/sourceless/.bashrc 2>/dev/null; then
         echo 'eval "$(starship init bash)"' >> /var/home/sourceless/.bashrc
    fi

    chown -R 1000:1000 /var/home/sourceless
    chmod 700 /var/home/sourceless
    chmod 755 /var/home/sourceless/.config 2>/dev/null || true
    restorecon -RF /var/home/sourceless 2>/dev/null || true
fi