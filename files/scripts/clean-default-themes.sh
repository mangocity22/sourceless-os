#!/usr/bin/env bash
# =============================================================================
# Sourceless OS - Default Look-and-Feel Theme Cleanup
# Removes upstream Breeze and Fedora global themes so only org.sourceless.desktop remains
# =============================================================================
set -oue pipefail

echo "=== Removing upstream default Look-and-Feel packages (Breeze / Fedora) ==="

# Purge default global themes from /usr/share/plasma/look-and-feel
rm -rf /usr/share/plasma/look-and-feel/org.kde.breeze*
rm -rf /usr/share/plasma/look-and-feel/org.fedoraproject*

echo "=== Default themes removed; org.sourceless.desktop is now exclusive ==="
