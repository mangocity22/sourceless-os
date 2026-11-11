#!/usr/bin/env bash
set -eueo pipefail

echo "=== Compilare Sourceless Control Center ==="

# Folderul tău este acum în files/, deci BlueBuild l-a adus în /tmp/files/
cd /tmp/files/sourceless-control-center || { echo "Eroare: Nu gasesc folderul in /tmp/files/"; exit 1; }

# Compilăm aplicația
mkdir -p build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=/usr
make -j$(nproc)

# Instalăm binarul pe rădăcina imaginii de build
make install DESTDIR=/