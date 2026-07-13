#!/bin/bash
# Sourceless OS - Cert Verification Daemon

CERT_DIR="/etc/sourceless/certs"
PORT=8443

# 1. Generare automata infrastructura PKI locala daca lipseste
if [ ! -f "$CERT_DIR/server.crt" ]; then
    echo "[Sourceless] Initializare infrastructura criptografica locala..."
    mkdir -p "$CERT_DIR"
    chmod 700 "$CERT_DIR"

    # Generare Cheie si Certificat Autoritate de Certificare (CA) interna
    openssl genrsa -out "$CERT_DIR/ca.key" 4096
    openssl req -x509 -new -nodes -key "$CERT_DIR/ca.key" -sha256 -days 365 \
        -subj "/CN=Sourceless-Internal-Root-CA" -out "$CERT_DIR/ca.crt"

    # Generare Cheie Server
    openssl genrsa -out "$CERT_DIR/server.key" 2048
    
    # Creare Cerere de Semnare Certificat (CSR) pentru server
    openssl req -new -key "$CERT_DIR/server.key" \
        -subj "/CN=sourceless-auth-server" -out "$CERT_DIR/server.csr"

    # Semnarea certificatului serverului folosind CA-ul local
    openssl x509 -req -in "$CERT_DIR/server.csr" -CA "$CERT_DIR/ca.crt" \
        -CAkey "$CERT_DIR/ca.key" -CAcreateserial -out "$CERT_DIR/server.crt" \
        -days 365 -sha256

    # Curatenie si securizare permisiuni
    rm "$CERT_DIR/server.csr"
    chmod 600 "$CERT_DIR/"*
    echo "[Sourceless] PKI local generat cu succes."
fi

# 2. Lansare server de ascultare TLS cu verificare reciproca (mTLS)
echo "[Sourceless] Serverul de verificare certificate porneste pe portul $PORT..."
# Utilizam utilitarul nativ OpenSSL s_server pentru a asculta conexiunile nodurilor
openssl s_server -accept $PORT \
    -cert "$CERT_DIR/server.crt" \
    -key "$CERT_DIR/server.key" \
    -CAfile "$CERT_DIR/ca.crt" \
    -Verify 1 -www