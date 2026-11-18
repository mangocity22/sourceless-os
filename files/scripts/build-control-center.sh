#!/usr/bin/env bash
# =============================================================================
# Sourceless OS - Native C++/Qt6 Control Center Build Script
# Compiles and installs sourceless-control-center into /usr during image build
# =============================================================================
set -euo pipefail

echo "=== Building Sourceless Control Center (C++20 / Qt6 / Kirigami) ==="

SRC=/tmp/files/sourceless-control-center
BUILD=/tmp/sourceless-cc-build

# Configure, compile using all available cores, and install into root tree
cmake -S "$SRC" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "$BUILD" -j"$(nproc)"
DESTDIR=/ cmake --install "$BUILD"

# Clean temporary build artifacts
rm -rf "$BUILD"

echo "=== Sourceless Control Center build completed successfully ==="
