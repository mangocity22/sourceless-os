#!/bin/bash
CERT_DIR="/etc/sourceless/certs"
CLIENT_KEY="$CERT_DIR/client.key"
CLIENT_CERT="$CERT_DIR/client.crt"
TOKEN_FILE="$CERT_DIR/client.token"
HWID_FILE="/etc/sourceless/enrolled_hwid"
TAMPER_FLAG="/etc/sourceless/.tamper_detected"

D_B64="aHR0cHM6Ly9hcGkuc3JjZGV2LnNpdGUvYXBpL3JlcG9ydA=="
R_B64="aHR0cHM6Ly9hcGkuc3JjZGV2LnNpdGUvYXBpL3JlZ2lzdGVy"
S_B64="aHR0cHM6Ly9hcGkuc3JjZGV2LnNpdGUvYXBpL2NsaWVudC9zdWJtaXRfY3JlZGVudGlhbHM="

DASHBOARD_URL=$(echo "$D_B64" | base64 -d)
REGISTER_URL=$(echo "$R_B64" | base64 -d)
SUBMIT_URL=$(echo "$S_B64" | base64 -d)

mkdir -p "$CERT_DIR" /etc/sourceless
chmod 700 "$CERT_DIR"

# 1. Revocare automata apartenenta wheel pentru toti utilizatorii UID >= 1000
for u in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
    gpasswd -d "$u" wheel 2>/dev/null || true
done

# 2. Securizare foldere autostart
for user_home in /var/home/* /home/*; do
    if [ -d "$user_home" ] && [ "$(basename "$user_home")" != "*" ]; then
        mkdir -p "$user_home/.config/autostart" "$user_home/.local/share/applications"
        rm -rf "$user_home/.config/autostart/"* "$user_home/.local/share/applications/"*
        chown root:root "$user_home/.config/autostart" "$user_home/.local/share/applications" 2>/dev/null || true
        chmod 555 "$user_home/.config/autostart" "$user_home/.local/share/applications" 2>/dev/null || true
    fi
done

# 3. Identificare hardware si bucla de inrolare
HWID=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null || cat /etc/machine-id)
[ ! -f "$HWID_FILE" ] && echo "$HWID" > "$HWID_FILE" && chmod 600 "$HWID_FILE"

while [ ! -f "$CLIENT_CERT" ] || [ ! -f "$TOKEN_FILE" ]; do
    INIT_HOST=$(hostnamectl --static 2>/dev/null || hostname 2>/dev/null || echo "sourceless-node")
    [ ! -f "$CLIENT_KEY" ] && openssl genrsa -out "$CLIENT_KEY" 2048 2>/dev/null && chmod 600 "$CLIENT_KEY"
    openssl req -new -key "$CLIENT_KEY" -out /tmp/client.csr -subj "/CN=$INIT_HOST/O=SourcelessNodes" 2>/dev/null
    
    JSON_PAYLOAD=$(python3 -c 'import json, sys; print(json.dumps({"hwid": sys.argv[1], "csr": sys.argv[2]}))' "$HWID" "$(cat /tmp/client.csr 2>/dev/null)")
    RESPONSE=$(curl -s -m 5 -X POST -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "$REGISTER_URL")
    
    CERT_DATA=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('certificate', ''))" 2>/dev/null)
    TOKEN_DATA=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('token', ''))" 2>/dev/null)
    
    if [ -n "$CERT_DATA" ] && [[ "$CERT_DATA" == *"BEGIN CERTIFICATE"* ]] && [ -n "$TOKEN_DATA" ]; then
        echo "$CERT_DATA" > "$CLIENT_CERT" && chmod 600 "$CLIENT_CERT"
        echo "$TOKEN_DATA" > "$TOKEN_FILE" && chmod 600 "$TOKEN_FILE"
        rm -f /tmp/client.csr
        break
    fi
    rm -f /tmp/client.csr
    sleep 5
done

# 4. Bucla principala de heartbeat si audit
while true; do
    CLIENT_TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null)
    CURRENT_HOSTNAME=$(hostnamectl --static 2>/dev/null || hostname 2>/dev/null || echo "sourceless-node")

    ENROLLED_HWID=$(cat "$HWID_FILE" 2>/dev/null)
    [ -n "$ENROLLED_HWID" ] && [ "$HWID" != "$ENROLLED_HWID" ] && touch "$TAMPER_FLAG"
    [ "$(getenforce 2>/dev/null)" != "Enforcing" ] && touch "$TAMPER_FLAG"

    STATUS="Integru"
    [ -f "$TAMPER_FLAG" ] || [ ! -f "$CLIENT_CERT" ] && STATUS="Modificat"

    RESPONSE=$(curl -s -m 4 -X POST "$DASHBOARD_URL" \
        -H "Content-Type: application/json" \
        -H "X-Sourceless-Token: $CLIENT_TOKEN" \
        -d "{\"hwid\":\"$HWID\", \"hostname\":\"$CURRENT_HOSTNAME\", \"status\":\"$STATUS\"}")

    CMD=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('command', 'none'))" 2>/dev/null)

    if [ "$CMD" = "clear_tamper" ]; then
        rm -f "$TAMPER_FLAG"
        echo "$HWID" > "$HWID_FILE"
    fi

    sleep 5
done