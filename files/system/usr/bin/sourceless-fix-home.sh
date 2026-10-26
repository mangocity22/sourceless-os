#!/usr/bin/bash
set -euo pipefail

# Wait defensively if /var/home is still mounting
for i in {1..10}; do
    if [ -d /var/home/sourceless ]; then
        break
    fi
    sleep 0.5
done

if [ -d /var/home/sourceless ]; then
    echo "[Sourceless] Restoring home ownership and SELinux contexts..."
    chown -R 1000:1000 /var/home/sourceless
    chmod 700 /var/home/sourceless
    chmod 755 /var/home/sourceless/.config 2>/dev/null || true
    
    # Restore standard SELinux labels so Qt/KDE processes can write
    restorecon -RF /var/home/sourceless 2>/dev/null || true
fi