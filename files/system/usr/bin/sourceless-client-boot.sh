#!/bin/bash
# /usr/bin/sourceless-client-boot.sh
# Version 6.2 - Dynamic User Support, Live Hostname Resolution & Resilient Enrollment

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
# 1. DYNAMIC USER SECURITY & WHEEL STRIPPING
# ==============================================================================
# Strip administrative (wheel) privileges from all standard users (UID >= 1000)
for u in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
    gpasswd -d "$u" wheel 2>/dev/null || true
done

# Secure persistence paths for all existing user home directories
for user_home in /var/home/* /home/*; do
    if [ -d "$user_home" ] && [ "$(basename "$user_home")" != "*" ]; then
        mkdir -p "$user_home/.config/autostart"
        rm -rf "$user_home/.config/autostart/"*
        chown root:root "$user_home/.config/autostart" 2>/dev/null || true
        chmod 555 "$user_home/.config/autostart" 2>/dev/null || true

        mkdir -p "$user_home/.local/share/applications"
        rm -rf "$user_home/.local/share/applications/"*
        chown root:root "$user_home/.local/share/applications" 2>/dev/null || true
        chmod 555 "$user_home/.local/share/applications" 2>/dev/null || true
    fi
done

# ==============================================================================
# 2. HARDWARE IDENTIFICATION & RESILIENT ENROLLMENT LOOP
# ==============================================================================
HWID=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null)
if [ -z "$HWID" ]; then
    HWID=$(cat /etc/machine-id)
fi

# Persist initial hardware signature on first boot (Hardware Binding)
if [ ! -f "$HWID_FILE" ]; then
    echo "$HWID" > "$HWID_FILE"
    chmod 600 "$HWID_FILE"
fi

# Resilient enrollment loop: retries continuously until network is up and token received
while [ ! -f "$CLIENT_CERT" ] || [ ! -f "$TOKEN_FILE" ]; do
    INITIAL_HOSTNAME=$(hostnamectl --static 2>/dev/null || hostname 2>/dev/null || echo "sourceless-node")
    echo "[Sourceless] Attempting cryptographic enrollment with backend ($INITIAL_HOSTNAME)..."
    
    if [ ! -f "$CLIENT_KEY" ]; then
        openssl genrsa -out "$CLIENT_KEY" 2048 2>/dev/null
        chmod 600 "$CLIENT_KEY"
    fi
    
    openssl req -new -key "$CLIENT_KEY" -out /tmp/client.csr -subj "/CN=$INITIAL_HOSTNAME/O=SourcelessNodes" 2>/dev/null
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
# 3. CONTINUOUS HEARTBEAT & INTEGRITY AUDIT LOOP
# ==============================================================================
while true; do
    CLIENT_TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null)
    
    # Live resolution of current hostname on every single heartbeat
    CURRENT_HOSTNAME=$(hostnamectl --static 2>/dev/null || hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "sourceless-node")
    [ -z "$CURRENT_HOSTNAME" ] && CURRENT_HOSTNAME="sourceless-node"

    # --- ACTIVE INTEGRITY & TAMPER VERIFICATION ---
    ENROLLED_HWID=$(cat "$HWID_FILE" 2>/dev/null)
    if [ -n "$ENROLLED_HWID" ] && [ "$HWID" != "$ENROLLED_HWID" ]; then
        touch "$TAMPER_FLAG"
        logger -t "sourceless-security" -p user.err "Tamper detected: Motherboard UUID mismatch! Expected $ENROLLED_HWID, found $HWID"
    fi

    if [ "$(getenforce 2>/dev/null)" != "Enforcing" ]; then
        touch "$TAMPER_FLAG"
        logger -t "sourceless-security" -p user.err "Tamper detected: SELinux policy is not Enforcing!"
    fi

    CONFIG_DRIFT=$(ostree admin config-diff 2>/dev/null | grep -E "sudoers|profile\.d/sourceless-audit\.sh")
    if [ -n "$CONFIG_DRIFT" ]; then
        touch "$TAMPER_FLAG"
        logger -t "sourceless-security" -p user.warn "Tamper detected! Critical configuration modified: $CONFIG_DRIFT"
    fi

    if rpm-ostree status --json 2>/dev/null | grep -qE '"requested-local-packages":\s*\[[^]]+\]|"unlocked":\s*"transient"'; then
        touch "$TAMPER_FLAG"
        logger -t "sourceless-security" -p user.err "Tamper detected: Unauthorized OSTree local overlay or package detected!"
    fi

    # --- STATUS DETERMINATION ---
    if [ -f "$TAMPER_FLAG" ] || [ ! -f "$CLIENT_CERT" ]; then
        STATUS="Modificat"
    else
        STATUS="Integru"
    fi

    # Dispatch dynamic heartbeat payload
    RESPONSE=$(curl -s -m 4 -X POST "$DASHBOARD_URL" \
        -H "Content-Type: application/json" \
        -H "X-Sourceless-Token: $CLIENT_TOKEN" \
        -d "{\"hwid\":\"$HWID\", \"hostname\":\"$CURRENT_HOSTNAME\", \"status\":\"$STATUS\"}")

    CMD=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('command', 'none'))" 2>/dev/null)

    # --- COMMAND: REINSTATE ---
    if [ "$CMD" = "clear_tamper" ]; then
        rm -f "$TAMPER_FLAG"
        echo "$HWID" > "$HWID_FILE"
        logger -t "sourceless-security" -p user.info "System integrity successfully restored via Reinstate command."
    fi

    # --- DYNAMIC ACTIVE USER DETECTION FOR SUPPORT ---
    ACTIVE_USER=$(who | grep -E '(:[0-9]|tty[0-9]|wayland)' | awk '{print $1}' | head -n 1)
    if [ -z "$ACTIVE_USER" ]; then
        ACTIVE_USER=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1; exit}' /etc/passwd)
    fi
    [ -z "$ACTIVE_USER" ] && ACTIVE_USER="sourceless"

    ACTIVE_UID=$(id -u "$ACTIVE_USER" 2>/dev/null)
    [ -z "$ACTIVE_UID" ] && ACTIVE_UID="1000"

    # --- COMMAND: REMOTE SUPPORT (RUSTDESK) ---
    if [ "$CMD" = "start_support" ]; then
        rm -f /tmp/sourceless_support_active
        pkill -f zenity 2>/dev/null || true
        
        if sudo -u "$ACTIVE_USER" WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 XDG_RUNTIME_DIR="/run/user/${ACTIVE_UID}" zenity --question \
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