#!/usr/bin/env bash
set -eueo pipefail

# Ne mutăm în directorul cu sursa aplicației (presupunând că BlueBuild copiază tot repo-ul în mediul de build)
cd /tmp/sourceless-control-center || exit 1

# Compilăm
mkdir -p build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=/usr
make -j$(nproc)

# Instalăm în structura de fișiere care va deveni imaginea
make install DESTDIR=/tmp/system