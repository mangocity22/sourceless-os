#!/usr/bin/env bash
set -euo pipefail

echo "=== Pornire asamblare C++ prin shell nativ ==="

SRC=/tmp/files/sourceless-control-center
BUILD=/tmp/sourceless-cc-build

cmake -S "$SRC" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "$BUILD" -j"$(nproc)"
DESTDIR=/ cmake --install "$BUILD"

rm -rf "$BUILD"

echo "=== Compilare finalizata cu succes ==="