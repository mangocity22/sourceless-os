#!/bin/bash
# /usr/bin/sourceless-cert-verify.sh
# SourceLess OS local PKI initialization and mutual TLS (mTLS) certificate verification server

CERT_DIR="/etc/sourceless/certs"
PORT=8443

# 1. Auto-generate local PKI infrastructure if server certificate is missing
if [ ! -f "$CERT_DIR/server.crt" ]; then
    echo "[Sourceless] Initializing local cryptographic PKI infrastructure..."
    mkdir -p "$CERT_DIR"
    chmod 700 "$CERT_DIR"

    # Generate internal Root CA private key and self-signed certificate
    openssl genrsa -out "$CERT_DIR/ca.key" 4096
    openssl req -x509 -new -nodes -key "$CERT_DIR/ca.key" -sha256 -days 365 \
        -subj "/CN=Sourceless-Internal-Root-CA" -out "$CERT_DIR/ca.crt"

    # Generate server private key and Certificate Signing Request (CSR)
    openssl genrsa -out "$CERT_DIR/server.key" 2048
    openssl req -new -key "$CERT_DIR/server.key" \
        -subj "/CN=sourceless-auth-server" -out "$CERT_DIR/server.csr"

    # Sign the server certificate with the internal Root CA
    openssl x509 -req -in "$CERT_DIR/server.csr" -CA "$CERT_DIR/ca.crt" \
        -CAkey "$CERT_DIR/ca.key" -CAcreateserial -out "$CERT_DIR/server.crt" \
        -days 365 -sha256

    # Remove CSR and lock down private key and certificate permissions
    rm "$CERT_DIR/server.csr"
    chmod 600 "$CERT_DIR/"*
    echo "[Sourceless] Local PKI initialized successfully."
fi

# 2. Launch OpenSSL s_server listener with mandatory client certificate verification (mTLS)
echo "[Sourceless] Starting mTLS certificate verification server on port $PORT..."
openssl s_server -accept 127.0.0.1:8443 \
    -cert "$CERT_DIR/server.crt" \
    -key "$CERT_DIR/server.key" \
    -CAfile "$CERT_DIR/ca.crt" \
    -Verify 1 -www
