#!/bin/bash
# /usr/bin/sourceless-client-boot.sh
# Versiunea 4.3 - Cloudflare Tunnel HTTPS & Token Authentication

CERT_DIR="/etc/sourceless/certs"
CLIENT_KEY="$CERT_DIR/client.key"
CLIENT_CERT="$CERT_DIR/client.crt"
TOKEN_FILE="$CERT_DIR/client.token"

# Endpoints encodate Base64 (edges-sticky-clubs-implemented.trycloudflare.com)
D_B64="aHR0cHM6Ly9lZGdlcy1zdGlja3ktY2x1YnMtaW1wbGVtZW50ZWQudHJ5Y2xvdWRmbGFyZS5jb20vYXBpL3JlcG9ydA=="
R_B64="aHR0cHM6Ly9lZGdlcy1zdGlja3ktY2x1YnMtaW1wbGVtZW50ZWQudHJ5Y2xvdWRmbGFyZS5jb20vYXBpL3JlZ2lzdGVy"
S_B64="aHR0cHM6Ly9lZGdlcy1zdGlja3ktY2x1YnMtaW1wbGVtZW50ZWQudHJ5Y2xvdWRmbGFyZS5jb20vYXBpL2NsaWVudC9zdWJtaXRfY3JlZGVudGlhbHM="

DASHBOARD_URL=$(echo "$D_B64" | base64 -d)
REGISTER_URL=$(echo "$R_B64" | base64 -d)
SUBMIT_URL=$(echo "$S_B64" | base64 -d)

mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

# 1. Extragere HWID unic
HWID=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null)
if [ -z "$HWID" ]; then
    HWID=$(cat /etc/machine-id)
fi
HOSTNAME=$(hostname)

# 2. ÎNROLARE AUTOMATĂ mTLS & Generare Token
if [ ! -f "$CLIENT_CERT" ] || [ ! -f "$TOKEN_FILE" ]; then
    echo "[Sourceless] Generare identitate unică..."
    if [ ! -f "$CLIENT_KEY" ]; then
        openssl genrsa -out "$CLIENT_KEY" 2048 2>/dev/null
        chmod 600 "$CLIENT_KEY"
    fi
    
    openssl req -new -key "$CLIENT_KEY" -out /tmp/client.csr -subj "/CN=$HOSTNAME/O=SourcelessNodes" 2>/dev/null
    JSON_PAYLOAD=$(python3 -c 'import json, sys; print(json.dumps({"hwid": sys.argv[1], "csr": sys.argv[2]}))' "$HWID" "$(cat /tmp/client.csr 2>/dev/null)")
    
    RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "$REGISTER_URL")
    
    CERT_DATA=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('certificate', ''))" 2>/dev/null)
    TOKEN_DATA=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('token', ''))" 2>/dev/null)
    
    if [ -n "$CERT_DATA" ] && [[ "$CERT_DATA" == *"BEGIN CERTIFICATE"* ]]; then
        echo "$CERT_DATA" > "$CLIENT_CERT"
        chmod 600 "$CLIENT_CERT"
    fi
    
    if [ -n "$TOKEN_DATA" ]; then
        echo "$TOKEN_DATA" > "$TOKEN_FILE"
        chmod 600 "$TOKEN_FILE"
        echo "[Sourceless] Înrolare și token salvate cu succes!"
    fi
    rm -f /tmp/client.csr
fi

CLIENT_TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null)

# 3. Logica Anti-Tamper & Check
STATUS="Integru"
CONFIG_DRIFT=$(ostree admin config-diff 2>/dev/null | grep -E "sudoers|profile\.d/sourceless-audit\.sh")

if [ -n "$CONFIG_DRIFT" ] || [ -f "/etc/sourceless/.tamper_detected" ] || [ ! -f "$CLIENT_CERT" ]; then
    STATUS="Modificat"
    logger -t "sourceless-security" -p user.warn "Tamper detected! Critical config changed: $CONFIG_DRIFT"
fi

# 4. Raportare stare către Dashboard (Cu Token Auth)
RESPONSE=$(curl -s -X POST "$DASHBOARD_URL" \
    -H "Content-Type: application/json" \
    -H "X-Sourceless-Token: $CLIENT_TOKEN" \
    -d "{\"hwid\":\"$HWID\", \"hostname\":\"$HOSTNAME\", \"status\":\"$STATUS\"}")

CMD=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('command', 'none'))" 2>/dev/null)

if [ "$CMD" = "clear_tamper" ]; then
    echo "[Sourceless] Comandă de Reinstate recepționată."
    rm -f /etc/sourceless/.tamper_detected
    logger -t "sourceless-security" -p user.info "System integrity successfully restored."
fi

# 5. Detectare utilizator grafic activ
USER_NAME=$(who | grep -E '(\:[0-9]|tty[0-9]|wayland)' | awk '{print $1}' | head -n 1)
[ -z "$USER_NAME" ] && USER_NAME="sourceless"

USER_ID=$(id -u "$USER_NAME" 2>/dev/null)
[ -z "$USER_ID" ] && USER_ID="1000"

# 6. Executare comenzi de suport remote
if [ "$CMD" = "start_support" ]; then
    # Curățăm din start orice sesiune veche rămasă agățată
    rm -f /tmp/sourceless_support_active
    pkill -f zenity 2>/dev/null || true
    
    # Lansăm Zenity pe sesiunea grafică
    if sudo -u "$USER_NAME" WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 XDG_RUNTIME_DIR="/run/user/${USER_ID}" zenity --question \
        --title="Sourceless OS // Support Request" \
        --text="An administrator would like to initiate a remote support session.\n\nDo you approve the RustDesk connection?" \
        --width=400 --timeout=30; then
        
        touch /tmp/sourceless_support_active
        systemctl start rustdesk.service
        
        # Așteptăm 2 secunde ca daemonul IPC RustDesk să devină activ
        sleep 2
        
        RUSTDESK_PW=$(openssl rand -hex 4)
        rustdesk --password "$RUSTDESK_PW" 2>/dev/null || true
        sleep 1
        
        RUSTDESK_ID=""
        for i in {1..10}; do
            RUSTDESK_ID=$(rustdesk --get-id 2>/dev/null | tr -d '\r\n')
            [ -n "$RUSTDESK_ID" ] && [ "$RUSTDESK_ID" != "N/A" ] && break
            sleep 1
        done
        
        [ -z "$RUSTDESK_ID" ] && RUSTDESK_ID="N/A"

        curl -s -X POST "$SUBMIT_URL" \
            -H "Content-Type: application/json" \
            -H "X-Sourceless-Token: $CLIENT_TOKEN" \
            -d "{\"hwid\":\"${HWID}\", \"rustdesk_id\":\"${RUSTDESK_ID}\", \"rustdesk_pw\":\"${RUSTDESK_PW}\", \"status\":\"approved\"}"
    else
        curl -s -X POST "$SUBMIT_URL" \
            -H "Content-Type: application/json" \
            -H "X-Sourceless-Token: $CLIENT_TOKEN" \
            -d "{\"hwid\":\"${HWID}\", \"rustdesk_id\":\"N/A\", \"rustdesk_pw\":\"N/A\", \"status\":\"rejected\"}"
    fi

elif [ "$CMD" = "stop_support" ]; then
    # Oprire necondiționată și curățare completă
    rm -f /tmp/sourceless_support_active
    systemctl stop rustdesk.service || true
    pkill -f zenity 2>/dev/null || true
fi

exit 0