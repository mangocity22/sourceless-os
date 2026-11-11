#!/usr/bin/env bash
set -eueo pipefail

echo "=== Cautam directorul sursa... ==="

# Caută oriunde în structura montată fișierul CMakeLists.txt
SOURCE_DIR=$(find / -type f -name "CMakeLists.txt" -path "*/sourceless-control-center/*" -exec dirname {} \; | head -n 1)

if [ -z "$SOURCE_DIR" ]; then
    echo "Error: CMakeLists.txt not found in the expected source directory."
    exit 1
fi

echo "Found source in: $SOURCE_DIR"

cd "$SOURCE_DIR"

# Compilăm aplicația
mkdir -p build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=/usr
make -j$(nproc)

# Instalăm binarul
make install DESTDIR=/