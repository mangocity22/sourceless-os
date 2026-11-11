#!/usr/bin/env bash

echo "=== Pornire asamblare C++ prin shell nativ ==="

/bin/bash -c "mkdir -p /tmp/files/sourceless-control-center/build && cd /tmp/files/sourceless-control-center/build && cmake .. -DCMAKE_INSTALL_PREFIX=/usr && make -j$(nproc) && make install DESTDIR=/"

echo "=== Compilare finalizata cu succes ==="