#!/usr/bin/bash
# /usr/bin/sourceless-client-boot.sh
# Integrat nativ în straturile imutabile Sourceless-OS

CERT_DIR="/etc/sourceless/certs"
CLIENT_KEY="$CERT_DIR/client.key"
CLIENT_CERT="$CERT_DIR/client.crt"

# IP-ul containerului de management ridicat în Proxmox
DASHBOARD_URL="http://192.168.1.157/api/report" 
# IP-ul serverului tău central de OpenSSL (mTLS)
SERVER_MTLS_IP="IP_SERVER_CENTRAL" 
PORT_MTLS="8443"

# Ne asigurăm că directorul persistent există pe stație
mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

# 1. Extragere HWID unicat din placa de bază (seria de șasiu)
HWID=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null)
if [ -z "$HWID" ]; then
    HWID=$(cat /etc/machine-id)
fi
HOSTNAME=$(hostname)

# 2. Verificare / Generare chei mTLS locale
if [ ! -f "$CLIENT_KEY" ] || [ ! -f "$CLIENT_CERT" ]; then
    echo "[Sourceless Client] Lipsește certificatul unic. Inițiem înrolarea..."
    
    # Generăm cheia privată locală dacă nu există
    if [ ! -f "$CLIENT_KEY" ]; then
        openssl genrsa -out "$CLIENT_KEY" 4096
        chmod 600 "$CLIENT_KEY"
    fi
    
    # Generăm cererea de semnare (CSR)
    openssl req -new -key "$CLIENT_KEY" -out /tmp/client.csr -subj "/CN=$HOSTNAME/O=SourcelessNodes"
    
    # [Bootstrap/Handshake TLS] 
    # Aici clientul va trimite CSR-ul către serverul tău openssl s_server pe portul 8443.
    # Pentru că acum ai s_server pornit cu "-Verify 1", vom pune o linie temporară 
    # care lasă certificatul în așteptare până punem la punct puntea de descărcare.
    echo "[Sourceless Client] CSR generat în /tmp/client.csr. Așteaptă aprobare."
fi

# 3. Logica de verificare a sigiliului (Garanție)
STATUS="Integru"

# Dacă cineva a spart imutabilitatea sau dacă certificatul mTLS e invalid/lipsește:
if [ ! -f "$CLIENT_CERT" ] || [ -f "/etc/sourceless/.tamper_detected" ]; then
    STATUS="Modificat"
fi

# 4. Raportare automată instant către dashboard-ul din Proxmox
curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"hwid\":\"$HWID\", \"hostname\":\"$HOSTNAME\", \"status\":\"$STATUS\"}" \
    "$DASHBOARD_URL" > /dev/null

exit 0