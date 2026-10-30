#!/usr/bin/env bash
set -oue pipefail

echo "=== Curatare Global Themes default (Breeze / Fedora) ==="

# Stergem pachetele de Look-and-Feel default ca sa dispara complet din System Settings
rm -rf /usr/share/plasma/look-and-feel/org.kde.breeze*
rm -rf /usr/share/plasma/look-and-feel/org.fedoraproject*

echo "=== Temele implicite au fost eliminate. A ramas exclusiv org.sourceless.desktop ==="