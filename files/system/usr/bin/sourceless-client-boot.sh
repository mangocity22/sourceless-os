#!/usr/bin/bash
# /usr/bin/sourceless-client-boot.sh
# Versiunea 4.1 - Obscurizată + Auto-mTLS + Anti-Tamper Native Check

CERT_DIR="/etc/sourceless/certs"
CLIENT_KEY="$CERT_DIR/client.key"
CLIENT_CERT="$CERT_DIR/client.crt"

D_B64="aHR0cDovLzE5Mi4xNjguMS4xNTcvYXBpL3JlcG9ydA=="
R_B64="aHR0cDovLzE5Mi4xNjguMS4xNTcvYXBpL3JlZ2lzdGVy"

DASHBOARD_URL=$(echo "$D_B64" | base64 -d)
REGISTER_URL=$(echo "$R_B64" | base64 -d)

mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

# 1. Extragere HWID unic din BIOS
HWID=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null)
if [ -z "$HWID" ]; then
    HWID=$(cat /etc/machine-id)
fi
HOSTNAME=$(hostname)

# 2. ÎNROLARE AUTOMATĂ (Dacă lipsește certificatul de securitate)
if [ ! -f "$CLIENT_CERT" ]; then
    echo "[Sourceless] Generare identitate unică..."
    
    if [ ! -f "$CLIENT_KEY" ]; then
        openssl genrsa -out "$CLIENT_KEY" 2048
        chmod 600 "$CLIENT_KEY"
    fi
    
    # Generăm cererea de certificat (CSR)
    openssl req -new -key "$CLIENT_KEY" -out /tmp/client.csr -subj "/CN=$HOSTNAME/O=SourcelessNodes"
    
    # Împachetăm payload-ul JSON securizat
    JSON_PAYLOAD=$(python3 -c 'import json, sys; print(json.dumps({"hwid": sys.argv[1], "csr": sys.argv[2]}))' "$HWID" "$(cat /tmp/client.csr)")
    
    # Trimitem CSR-ul la serverul de management pentru semnare
    echo "[Sourceless] Solicitare semnare certificat de la autoritate..."
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$JSON_PAYLOAD" \
        "$REGISTER_URL")
        
    # Extragem certificatul primit înapoi
    CERT_DATA=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('certificate', ''))")
    
    if [ -n "$CERT_DATA" ] && [[ "$CERT_DATA" == *"BEGIN CERTIFICATE"* ]]; then
        echo "$CERT_DATA" > "$CLIENT_CERT"
        chmod 600 "$CLIENT_CERT"
        echo "[Sourceless] Înrolare mTLS finalizată cu succes!"
    else
        echo "[Sourceless] Eroare critică la înrolare: Certificat invalid primit de la server."
    fi
    
    rm -f /tmp/client.csr
fi

# 3. Logica de verificare a integrității (Anti-Tamper & Config Drift)
STATUS="Integru"

# Monitorizăm strict doar dacă cineva modifică regulile de sudo sau scriptul nostru de audit.
# Excludem passwd/shadow/group deoarece utilizatorul local creat la instalare va apărea mereu ca modificare.
CONFIG_DRIFT=$(ostree admin config-diff | grep -E "(^| )(sudoers|profile.d/sourceless-audit.sh)$")

if [ -n "$CONFIG_DRIFT" ] || [ -f "/etc/sourceless/.tamper_detected" ]; then
    STATUS="Modificat"
    logger -t "sourceless-security" -p user.warn "Tamper detected! Critical config changed: $CONFIG_DRIFT"
fi

if [ ! -f "$CLIENT_CERT" ]; then
    STATUS="Modificat"
fi

# 4. Raportare stare către Dashboard și procesare comenzi la distanță
RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"hwid\":\"$HWID\", \"hostname\":\"$HOSTNAME\", \"status\":\"$STATUS\"}" \
    "$DASHBOARD_URL")

# Extragem comanda din răspunsul JSON primit de la server folosind parserul tău nativ cu Python 3
CMD=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('command', 'none'))" 2>/dev/null)

# Dacă administratorul a apăsat "Reinstate" în Dashboard, serverul ne trimite comanda dedicată
if [ "$CMD" = "clear_tamper" ]; then
    echo "[Sourceless] Comandă de Reinstate recepționată. Se resetează integritatea locală..."
    
    # Ștergem fizic fișierul capcană creat la deblocare
    rm -f /etc/sourceless/.tamper_detected
    
    # Trimitem un log curat în sistem pentru audit
    logger -t "sourceless-security" -p user.info "System integrity successfully restored via remote Reinstate command."
fi

SERVER_IP="192.168.1.157"
HWID=$(cat /sys/class/dmi/id/product_uuid)

echo "[Sourceless] Se interoghează panoul de control central..."
RESPONSE=$(curl -s --max-time 5 "http://${SERVER_IP}:8080/api/client/status?hwid=${HWID}")
CMD=$(echo "$RESPONSE" | grep -o '"cmd":"[^"]*' | grep -o '[^"]*$')

if [ "$CMD" = "start_support" ]; then
    echo "[Sourceless] Se activează sesiunea de suport la distanță..."
    
    # 1. Cream flag-ul din /var/run (care este o zonă temporară în RAM, dispare la restart)
    touch /var/run/sourceless_support_active
    
    # 2. Pornim serviciul RustDesk ca tehnicianul să se poată conecta din Windows
    systemctl start rustdesk.service

elif [ "$CMD" = "stop_support" ] || [ "$CMD" = "clear_tamper" ]; then
    echo "[Sourceless] Se închide sesiunea de suport..."
    
    # Ștergem flag-ul (Konsole devine din nou complet blocată)
    rm -f /var/run/sourceless_support_active
    rm -f /etc/sourceless/.tamper_detected
    
    # Oprim serviciul RustDesk ca să nu lăsăm porturi deschise degeaba
    systemctl stop rustdesk.service
fi

exit 0