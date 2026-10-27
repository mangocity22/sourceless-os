#!/usr/bin/bash
set -euo pipefail

for i in {1..10}; do
    if [ -d /var/home/sourceless ]; then
        break
    fi
    sleep 0.5
done

if [ -d /var/home/sourceless ]; then
    # Daca .bashrc lipseste din home, copiem structura standard din /etc/skel
    if [ ! -f /var/home/sourceless/.bashrc ]; then
        cp -a /etc/skel/. /var/home/sourceless/ 2>/dev/null || true
    fi

    # Activam Starship prompt daca nu este deja injectat
    if ! grep -q "starship init bash" /var/home/sourceless/.bashrc 2>/dev/null; then
        echo 'eval "$(starship init bash)"' >> /var/home/sourceless/.bashrc
    fi

    chown -R 1000:1000 /var/home/sourceless
    chmod 700 /var/home/sourceless
    chmod 755 /var/home/sourceless/.config 2>/dev/null || true
    restorecon -RF /var/home/sourceless 2>/dev/null || true
fi