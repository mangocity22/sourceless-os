#!/bin/bash
# /usr/bin/sourceless-client-boot.sh
# Versiunea 4.3 - Fixed HWID + AJAX state + Forced RustDesk Password

SERVER_IP="192.168.1.157"
CERT_DIR="/etc/sourceless/certs"
CLIENT_KEY="$CERT_DIR/client.key"
CLIENT_CERT="$CERT_DIR/client.crt"

D_B64="aHR0cDovLzE5Mi4xNjguMS4xNTcvYXBpL3JlcG9ydA=="
R_B64="aHR0cDovLzE5Mi4xNjguMS4xNTcvYXBpL3JlZ2lzdGVy"

DASHBOARD_URL=$(echo "$D_B64" | base64 -d)
REGISTER_URL=$(echo "$R_B64" | base64 -d)

mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

# 1. Extragere HWID unic original (cu cratime)
HWID=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null)
if [ -z "$HWID" ]; then
    HWID=$(cat /etc/machine-id)
fi
HOSTNAME=$(hostname)

# 2. ÎNROLARE AUTOMATĂ (Dacă lipsește certificatul de securitate)
if [ ! -f "$CLIENT_CERT" ]; then
    echo "[Sourceless] Generare identitate unică..."
    
    if [ ! -f "$CLIENT_KEY" ]; then
        openssl genrsa -out "$CLIENT_KEY" 2048 2>/dev/null
        chmod 600 "$CLIENT_KEY"
    fi
    
    openssl req -new -key "$CLIENT_KEY" -out /tmp/client.csr -subj "/CN=$HOSTNAME/O=SourcelessNodes" 2>/dev/null
    
    JSON_PAYLOAD=$(python3 -c 'import json, sys; print(json.dumps({"hwid": sys.argv[1], "csr": sys.argv[2]}))' "$HWID" "$(cat /tmp/client.csr 2>/dev/null)")
    
    echo "[Sourceless] Solicitare semnare certificat de la autoritate..."
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$JSON_PAYLOAD" \
        "$REGISTER_URL")
        
    CERT_DATA=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('certificate', ''))" 2>/dev/null)
    
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

CONFIG_DRIFT=$(ostree admin config-diff 2>/dev/null | grep -E "sudoers|profile\.d/sourceless-audit\.sh")

if [ -n "$CONFIG_DRIFT" ] || [ -f "/etc/sourceless/.tamper_detected" ]; then
    STATUS="Modificat"
    logger -t "sourceless-security" -p user.warn "Tamper detected! Critical config changed: $CONFIG_DRIFT"
fi

if [ ! -f "$CLIENT_CERT" ]; then
    STATUS="Modificat"
fi

# 4. Raportare stare către Dashboard și preluare comenzi
RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"hwid\":\"$HWID\", \"hostname\":\"$HOSTNAME\", \"status\":\"$STATUS\"}" \
    "$DASHBOARD_URL")

CMD=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('command', 'none'))" 2>/dev/null)

USER_NAME=$(who | grep -E '(\:[0-9]|tty[0-9]|wayland)' | awk '{print $1}' | head -n 1)
[ -z "$USER_NAME" ] && USER_NAME="sourceless"

USER_ID=$(id -u "$USER_NAME" 2>/dev/null)
[ -z "$USER_ID" ] && USER_ID="1000"

# 5. Executare Comenzi
if [ "$CMD" = "clear_tamper" ]; then
    echo "[Sourceless] Comandă de Reinstate recepționată..."
    rm -f /etc/sourceless/.tamper_detected
    logger -t "sourceless-security" -p user.info "System integrity successfully restored via remote Reinstate command."

elif [ "$CMD" = "start_support" ]; then
    echo "[Sourceless] Solicitare suport remote recepționată..."
    
    if sudo -u "$USER_NAME" WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR="/run/user/${USER_ID}" zenity --question --text="An administrator would like to initiate a remote support session. Do you approve?" --title="Sourceless-OS Support" --timeout=30; then
        
        # Generăm o parolă curată de 8 caractere
        TEMP_PW=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 8)
        
        systemctl start rustdesk || true
        sleep 2
        
        # Setează parola explicit în RustDesk CLI
        rustdesk --password "$TEMP_PW" 2>/dev/null || true
        sleep 1
        
        RUSTDESK_ID=$(rustdesk --get-id 2>/dev/null)
        [ -z "$RUSTDESK_ID" ] && RUSTDESK_ID="N/A"
        
        curl -s -X POST "http://${SERVER_IP}/api/client/submit_credentials" \
            -H "Content-Type: application/json" \
            -d "{\"hwid\": \"${HWID}\", \"status\": \"approved\", \"rustdesk_id\": \"${RUSTDESK_ID}\", \"rustdesk_pw\": \"${TEMP_PW}\"}"
            
        touch /var/run/sourceless_support_active
    else
        curl -s -X POST "http://${SERVER_IP}/api/client/submit_credentials" \
            -H "Content-Type: application/json" \
            -d "{\"hwid\": \"${HWID}\", \"status\": \"rejected\"}"
    fi

elif [ "$CMD" = "stop_support" ] && [ -f /var/run/sourceless_support_active ]; then
    echo "[Sourceless] Oprire sesiune de suport..."
    rm -f /var/run/sourceless_support_active
    systemctl stop rustdesk.service
fi

exit 0