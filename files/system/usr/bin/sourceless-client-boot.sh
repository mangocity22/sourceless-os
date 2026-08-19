#!/bin/bash
# /usr/bin/sourceless-client-boot.sh
# Version 6.1 - Hardware-Bound Integrity Agent with Network-Resilient Enrollment

CERT_DIR="/etc/sourceless/certs"
CLIENT_KEY="$CERT_DIR/client.key"
CLIENT_CERT="$CERT_DIR/client.crt"
TOKEN_FILE="$CERT_DIR/client.token"
HWID_FILE="/etc/sourceless/enrolled_hwid"
TAMPER_FLAG="/etc/sourceless/.tamper_detected"

# Base64-encoded backend endpoints (api.srcdev.site)
D_B64="aHR0cHM6Ly9hcGkuc3JjZGV2LnNpdGUvYXBpL3JlcG9ydA=="
R_B64="aHR0cHM6Ly9hcGkuc3JjZGV2LnNpdGUvYXBpL3JlZ2lzdGVy"
S_B64="aHR0cHM6Ly9hcGkuc3JjZGV2LnNpdGUvYXBpL2NsaWVudC9zdWJtaXRfY3JlZGVudGlhbHM="

DASHBOARD_URL=$(echo "$D_B64" | base64 -d)
REGISTER_URL=$(echo "$R_B64" | base64 -d)
SUBMIT_URL=$(echo "$S_B64" | base64 -d)

mkdir -p "$CERT_DIR"
mkdir -p /etc/sourceless
chmod 700 "$CERT_DIR"

# ==============================================================================
# Runtime Security: Restrict persistence paths inside user profile
# ==============================================================================
USER_HOME="/var/home/sourceless"

if [ -d "$USER_HOME" ]; then
    mkdir -p "$USER_HOME/.config/autostart"
    rm -rf "$USER_HOME/.config/autostart/"*
    chown root:root "$USER_HOME/.config/autostart"
    chmod 555 "$USER_HOME/.config/autostart"

    mkdir -p "$USER_HOME/.local/share/applications"
    rm -rf "$USER_HOME/.local/share/applications/"*
    chown root:root "$USER_HOME/.local/share/applications"
    chmod 555 "$USER_HOME/.local/share/applications"
fi

# ==============================================================================
# 1. HARDWARE IDENTIFICATION & RESILIENT ENROLLMENT LOOP
# ==============================================================================
HWID=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null)
if [ -z "$HWID" ]; then
    HWID=$(cat /etc/machine-id)
fi
HOSTNAME=$(hostname)

# Persist initial hardware signature on first boot (Hardware Binding)
if [ ! -f "$HWID_FILE" ]; then
    echo "$HWID" > "$HWID_FILE"
    chmod 600 "$HWID_FILE"
fi

# Resilient enrollment loop: Retries until certificate and token are acquired
while [ ! -f "$CLIENT_CERT" ] || [ ! -f "$TOKEN_FILE" ]; do
    echo "[Sourceless] Attempting cryptographic enrollment with backend..."
    
    if [ ! -f "$CLIENT_KEY" ]; then
        openssl genrsa -out "$CLIENT_KEY" 2048 2>/dev/null
        chmod 600 "$CLIENT_KEY"
    fi
    
    openssl req -new -key "$CLIENT_KEY" -out /tmp/client.csr -subj "/CN=$HOSTNAME/O=SourcelessNodes" 2>/dev/null
    JSON_PAYLOAD=$(python3 -c 'import json, sys; print(json.dumps({"hwid": sys.argv[1], "csr": sys.argv[2]}))' "$HWID" "$(cat /tmp/client.csr 2>/dev/null)")
    
    RESPONSE=$(curl -s -m 5 -X POST -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "$REGISTER_URL")
    
    CERT_DATA=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('certificate', ''))" 2>/dev/null)
    TOKEN_DATA=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('token', ''))" 2>/dev/null)
    
    if [ -n "$CERT_DATA" ] && [[ "$CERT_DATA" == *"BEGIN CERTIFICATE"* ]] && [ -n "$TOKEN_DATA" ]; then
        echo "$CERT_DATA" > "$CLIENT_CERT"
        chmod 600 "$CLIENT_CERT"
        echo "$TOKEN_DATA" > "$TOKEN_FILE"
        chmod 600 "$TOKEN_FILE"
        rm -f /tmp/client.csr
        echo "[Sourceless] Enrollment successful. Identity established."
        break
    fi
    
    rm -f /tmp/client.csr
    sleep 5
done

echo "[Sourceless] Security and heartbeat agent initialized."

# ==============================================================================
# 2. CONTINUOUS HEARTBEAT & INTEGRITY AUDIT LOOP
# ==============================================================================
while true; do
    CLIENT_TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null)

    # --- ACTIVE INTEGRITY & TAMPER VERIFICATION ---
    
    # 1. Hardware binding verification
    ENROLLED_HWID=$(cat "$HWID_FILE" 2>/dev/null)
    if [ -n "$ENROLLED_HWID" ] && [ "$HWID" != "$ENROLLED_HWID" ]; then
        touch "$TAMPER_FLAG"
        logger -t "sourceless-security" -p user.err "Tamper detected: Motherboard UUID mismatch! Expected $ENROLLED_HWID, found $HWID"
    fi

    # 2. SELinux enforcement verification
    if [ "$(getenforce 2>/dev/null)" != "Enforcing" ]; then
        touch "$TAMPER_FLAG"
        logger -t "sourceless-security" -p user.err "Tamper detected: SELinux policy is not Enforcing!"
    fi

    # 3. Critical configuration drift audit (/etc)
    CONFIG_DRIFT=$(ostree admin config-diff 2>/dev/null | grep -E "sudoers|profile\.d/sourceless-audit\.sh")
    if [ -n "$CONFIG_DRIFT" ]; then
        touch "$TAMPER_FLAG"
        logger -t "sourceless-security" -p user.warn "Tamper detected! Critical configuration modified: $CONFIG_DRIFT"
    fi

    # 4. OSTree layer audit
    if rpm-ostree status --json 2>/dev/null | grep -qE '"requested-local-packages":\s*\[[^]]+\]|"unlocked":\s*"transient"'; then
        touch "$TAMPER_FLAG"
        logger -t "sourceless-security" -p user.err "Tamper detected: Unauthorized OSTree local overlay or package detected!"
    fi

    # --- EVALUATE STATUS ---
    if [ -f "$TAMPER_FLAG" ] || [ ! -f "$CLIENT_CERT" ]; then
        STATUS="Modificat"
    else
        STATUS="Integru"
    fi

    # Dispatch heartbeat payload
    RESPONSE=$(curl -s -m 4 -X POST "$DASHBOARD_URL" \
        -H "Content-Type: application/json" \
        -H "X-Sourceless-Token: $CLIENT_TOKEN" \
        -d "{\"hwid\":\"$HWID\", \"hostname\":\"$HOSTNAME\", \"status\":\"$STATUS\"}")

    CMD=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('command', 'none'))" 2>/dev/null)

    # --- COMMAND PROCESSING: REINSTATE ---
    if [ "$CMD" = "clear_tamper" ]; then
        echo "[Sourceless] Reinstate command received. Restoring system warranty status..."
        rm -f "$TAMPER_FLAG"
        echo "$HWID" > "$HWID_FILE"
        logger -t "sourceless-security" -p user.info "System integrity successfully restored via Reinstate command."
    fi

    # --- COMMAND PROCESSING: REMOTE SUPPORT (RUSTDESK) ---
    USER_NAME=$(who | grep -E '(:[0-9]|tty[0-9]|wayland)' | awk '{print $1}' | head -n 1)
    [ -z "$USER_NAME" ] && USER_NAME="sourceless"

    USER_ID=$(id -u "$USER_NAME" 2>/dev/null)
    [ -z "$USER_ID" ] && USER_ID="1000"

    if [ "$CMD" = "start_support" ]; then
        rm -f /tmp/sourceless_support_active
        pkill -f zenity 2>/dev/null || true
        
        if sudo -u "$USER_NAME" WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 XDG_RUNTIME_DIR="/run/user/${USER_ID}" zenity --question \
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
        pkill -u sourceless -f "/usr/bin/konsole" 2>/dev/null || true
        systemctl stop rustdesk.service || true
        pkill -f zenity 2>/dev/null || true

        if [ -n "$USER_DISPLAY" ]; then
            sudo -u sourceless DISPLAY="$USER_DISPLAY" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus" \
                kdialog --title "Sourceless Support" --passivepopup "Remote support session has been terminated." 5 2>/dev/null || true
        fi
    fi

    sleep 5
done