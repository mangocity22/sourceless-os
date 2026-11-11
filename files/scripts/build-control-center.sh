#!/usr/bin/env bash
set -eueo pipefail

echo "=== Compilare Sourceless Control Center ==="

# În BlueBuild, fișierele din repo sunt montate în /tmp/
# Căutăm directorul sursă exact unde a fost copiat
cd /tmp/sourceless-control-center || { echo "Eroare: Nu gasesc folderul sourceless-control-center in /tmp/"; exit 1; }

# Compilăm aplicația
mkdir -p build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=/usr
make -j$(nproc)

# Instalăm binarul în structura temporară a imaginii OS-ului (care este montată de obicei în rădăcina sistemului de fișiere build)
make install DESTDIR=/