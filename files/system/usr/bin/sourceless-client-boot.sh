#!/bin/bash
# /usr/bin/sourceless-client-boot.sh
# Production Version - Full Heartbeat, Tamper Engine & Dynamic Remote Support

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

# 1. Automatic wheel membership revocation for all standard users UID >= 1000
for u in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
    gpasswd -d "$u" wheel 2>/dev/null || true
done

# 2. Secure autostart directories
for user_home in /var/home/* /home/*; do
    if [ -d "$user_home" ] && [ "$(basename "$user_home")" != "*" ]; then
        mkdir -p "$user_home/.config/autostart" "$user_home/.local/share/applications"
        rm -rf "$user_home/.config/autostart/"* "$user_home/.local/share/applications/"*
        chown root:root "$user_home/.config/autostart" "$user_home/.local/share/applications" 2>/dev/null || true
        chmod 555 "$user_home/.config/autostart" "$user_home/.local/share/applications" 2>/dev/null || true
    fi
done

# 3. Hardware identification and enrollment loop
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

# 4. Main Heartbeat, Audit and Remote Support Loop
while true; do
    CLIENT_TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null)
    CURRENT_HOSTNAME=$(hostnamectl --static 2>/dev/null || hostname 2>/dev/null || echo "sourceless-node")

    # --- INTEGRITY VERIFICATION ---
    ENROLLED_HWID=$(cat "$HWID_FILE" 2>/dev/null)
    [ -n "$ENROLLED_HWID" ] && [ "$HWID" != "$ENROLLED_HWID" ] && touch "$TAMPER_FLAG"
    [ "$(getenforce 2>/dev/null)" != "Enforcing" ] && touch "$TAMPER_FLAG"

    # Check for local emergency terminal activation trigger
    if [ -f /tmp/.sourceless_tamper_trigger ]; then
        touch "$TAMPER_FLAG"
        rm -f /tmp/.sourceless_tamper_trigger
    fi

    STATUS="Integru"
    [ -f "$TAMPER_FLAG" ] || [ ! -f "$CLIENT_CERT" ] && STATUS="Modificat"

    # --- TRANSMIT HEARTBEAT & FETCH COMMAND ---
    RESPONSE=$(curl -s -m 4 -X POST "$DASHBOARD_URL" \
        -H "Content-Type: application/json" \
        -H "X-Sourceless-Token: $CLIENT_TOKEN" \
        -d "{\"hwid\":\"$HWID\", \"hostname\":\"$CURRENT_HOSTNAME\", \"status\":\"$STATUS\"}")

    CMD=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('command', 'none'))" 2>/dev/null)

    # --- PROCESS COMMANDS ---
    if [ "$CMD" = "clear_tamper" ]; then
        rm -f "$TAMPER_FLAG"
        echo "$HWID" > "$HWID_FILE"

    elif [ "$CMD" = "start_support" ]; then
        rm -f /tmp/sourceless_support_active
        pkill -f zenity 2>/dev/null || true

        # Resolve graphical session parameters
        ACTIVE_USER=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v "root" | head -n 1)
        [ -z "$ACTIVE_USER" ] && ACTIVE_USER=$(who | grep -E '(:[0-9]|tty[0-9]|wayland|pts)' | awk '{print $1}' | head -n 1)
        [ -z "$ACTIVE_USER" ] && ACTIVE_USER=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1; exit}' /etc/passwd)
        [ -z "$ACTIVE_USER" ] && ACTIVE_USER="sourceless"

        ACTIVE_UID=$(id -u "$ACTIVE_USER" 2>/dev/null)
        [ -z "$ACTIVE_UID" ] && ACTIVE_UID="1000"

        WAYLAND_SOCK=$(ls /run/user/${ACTIVE_UID}/wayland-* 2>/dev/null | grep -E 'wayland-[0-9]+$' | head -n 1)
        WAYLAND_NAME=$(basename "$WAYLAND_SOCK" 2>/dev/null)
        [ -z "$WAYLAND_NAME" ] && WAYLAND_NAME="wayland-0"

        if sudo -u "$ACTIVE_USER" env \
            XDG_RUNTIME_DIR="/run/user/${ACTIVE_UID}" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${ACTIVE_UID}/bus" \
            WAYLAND_DISPLAY="$WAYLAND_NAME" \
            DISPLAY=:0 \
            zenity --question \
            --title="Sourceless OS // Support Request" \
            --text="An administrator would like to initiate a remote support session.\n\nDo you approve the RustDesk connection?" \
            --width=400 --timeout=30; then

            touch /tmp/sourceless_support_active
            systemctl start rustdesk.service
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
        rm -f /tmp/sourceless_support_active /tmp/.sourceless_support_active
        killall -9 konsole 2>/dev/null || true
        pkill -u "$ACTIVE_USER" -f "/usr/bin/konsole" 2>/dev/null || true
        systemctl stop rustdesk.service || true
        pkill -f zenity 2>/dev/null || true
    fi

    sleep 5
done