#!/usr/bin/env bash
set -oue pipefail

echo "=== Curatare Global Themes default (Breeze / Fedora) ==="

# Pastram animatia de splash personalizata in tema globala activa org.sourceless.desktop
if [ -d /usr/share/plasma/look-and-feel/org.kde.breeze.desktop/contents/splash ] && [ -d /usr/share/plasma/look-and-feel/org.sourceless.desktop/contents ]; then
    rm -rf /usr/share/plasma/look-and-feel/org.sourceless.desktop/contents/splash
    cp -a /usr/share/plasma/look-and-feel/org.kde.breeze.desktop/contents/splash /usr/share/plasma/look-and-feel/org.sourceless.desktop/contents/splash
fi

# Stergem pachetele de Look-and-Feel default ca sa dispara complet din System Settings
rm -rf /usr/share/plasma/look-and-feel/org.kde.breeze*
rm -rf /usr/share/plasma/look-and-feel/org.fedoraproject*

echo "=== Temele implicite au fost eliminate. A ramas exclusiv org.sourceless.desktop ==="