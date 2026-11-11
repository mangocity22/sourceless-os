#!/usr/bin/env bash
set -eueo pipefail

echo "=== Compilare Sourceless Control Center ==="

# Ne mutăm în directorul sursă (presupunând că BlueBuild copiază repo-ul în build env)
# Ajustează calea /tmp/sourceless-control-center dacă fișierele sursă ajung altundeva în timpul build-ului
cd /sourceless-control-center || exit 1

# Compilăm aplicația
mkdir -p build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=/usr
make -j$(nproc)

# Instalăm binarul în structura temporară a imaginii OS-ului
# Destinația depinde de modul în care BlueBuild mapează sistemul de fișiere final
make install DESTDIR=/