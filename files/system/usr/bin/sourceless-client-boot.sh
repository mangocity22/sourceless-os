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
chmod 755 /etc/sourceless
chmod 700 "$CERT_DIR"

# 1. Automatic wheel membership revocation for all standard users UID >= 1000
for u in $(awk -F: '$3 >= 1000 && $1 != "nobody" && $1 != "liveuser" && $1 != "sourceless-setup" {print $1}' /etc/passwd); do
    gpasswd -d "$u" wheel 2>/dev/null || true
done

# 2. Secure autostart directories
for user_home in /var/home/* /home/*; do
    [ -d "$user_home" ] || continue
    home_name="$(basename "$user_home")"
    case "$home_name" in
        "*"|liveuser|sourceless-setup|lost+found) continue ;;
    esac
    mkdir -p "$user_home/.config/autostart" "$user_home/.local/share/applications"
    rm -rf "$user_home/.config/autostart/"* "$user_home/.local/share/applications/"*
    chown root:root "$user_home/.config/autostart" "$user_home/.local/share/applications" 2>/dev/null || true
    chmod 555 "$user_home/.config/autostart" "$user_home/.local/share/applications" 2>/dev/null || true
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
    [ -n "$ENROLLED_HWID" ] && [ "$HWID" != "$ENROLLED_HWID" ] && touch "$TAMPER_FLAG" && chmod 644 "$TAMPER_FLAG"
    [ "$(getenforce 2>/dev/null)" != "Enforcing" ] && touch "$TAMPER_FLAG" && chmod 644 "$TAMPER_FLAG"

    # Check for local emergency terminal activation trigger
    if [ -f /tmp/.sourceless_tamper_trigger ]; then
        touch "$TAMPER_FLAG"
        chmod 644 "$TAMPER_FLAG"
        rm -f /tmp/.sourceless_tamper_trigger
    fi

    STATUS="Integru"
    [ -f "$TAMPER_FLAG" ] || [ ! -f "$CLIENT_CERT" ] && STATUS="Modificat"

    # --- COLLECT EXTENDED TELEMETRY ---
    SELINUX_MODE=$(getenforce 2>/dev/null || echo "Disabled")
    YARA_ACTIVE="false"
    systemctl is-active --quiet sourceless-shield.service 2>/dev/null && YARA_ACTIVE="true"

    REPORT_JSON=$(python3 - "$HWID" "$CURRENT_HOSTNAME" "$STATUS" "$SELINUX_MODE" "$YARA_ACTIVE" << 'PYEOF'
import json, os, re, shutil, sys
hwid, hostname, status, selinux_mode, yara_flag = sys.argv[1:6]

def read_txt(path, default=""):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read().strip()
    except Exception:
        return default

os_version = read_txt("/usr/lib/sourceless-version", "")
update_channel = "stable"
conf_txt = read_txt("/etc/sourceless/update.conf", "")
m = re.search(r'^UPDATE_CHANNEL=["\']?(stable|testing)["\']?', conf_txt, re.M)
if m:
    update_channel = m.group(1)

update_status = ""
try:
    state_raw = read_txt("/var/lib/sourceless-update/state.json", "")
    if state_raw:
        update_status = json.loads(state_raw).get("status", "")
except Exception:
    pass
if not update_status and os.path.exists("/var/lib/sourceless-update/pending"):
    update_status = "pending_restart"

lockdown = "Unknown"
ld_raw = read_txt("/sys/kernel/security/lockdown", "")
lm = re.search(r'\[([^\]]+)\]', ld_raw)
if lm:
    lockdown = lm.group(1).capitalize()

ram_percent = 0
try:
    meminfo = {}
    with open("/proc/meminfo", "r", encoding="utf-8") as fh:
        for line in fh:
            k, v = line.split(":", 1)
            meminfo[k.strip()] = int(v.strip().split()[0])
    total = meminfo.get("MemTotal", 0)
    avail = meminfo.get("MemAvailable", 0)
    if total > 0:
        ram_percent = max(0, min(100, round(((total - avail) * 100.0) / total)))
except Exception:
    pass

disk_percent = 0
try:
    target = "/var" if os.path.isdir("/var") else "/"
    usage = shutil.disk_usage(target)
    if usage.total > 0:
        disk_percent = max(0, min(100, round((usage.used * 100.0) / usage.total)))
except Exception:
    pass

uptime_str = ""
try:
    secs = int(float(read_txt("/proc/uptime", "0").split()[0]))
    days, rem = divmod(secs, 86400)
    hours, rem = divmod(rem, 3600)
    mins = rem // 60
    uptime_str = f"{days}d {hours}h {mins}m" if days > 0 else f"{hours}h {mins}m"
except Exception:
    pass

print(json.dumps({
    "hwid": hwid,
    "hostname": hostname,
    "status": status,
    "os_version": os_version,
    "update_channel": update_channel,
    "update_status": update_status,
    "selinux": selinux_mode,
    "lockdown": lockdown,
    "yara_active": (yara_flag == "true"),
    "ram_percent": ram_percent,
    "disk_percent": disk_percent,
    "uptime": uptime_str,
}))
PYEOF
)

    # --- TRANSMIT HEARTBEAT & FETCH COMMAND ---
    RESPONSE=$(curl -s -m 4 -X POST "$DASHBOARD_URL" \
        -H "Content-Type: application/json" \
        -H "X-Sourceless-Token: $CLIENT_TOKEN" \
        -d "$REPORT_JSON")

    CMD=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('command', 'none'))" 2>/dev/null)

    # --- PROCESS COMMANDS ---
    if [ "$CMD" = "clear_tamper" ]; then
        rm -f "$TAMPER_FLAG"
        echo "$HWID" > "$HWID_FILE"

    elif [ "$CMD" = "check_update" ]; then
        if [ -x /usr/bin/sourceless-os-updater ]; then
            systemd-run --no-block --unit=sourceless-remote-update /usr/bin/sourceless-os-updater check-and-stage >/dev/null 2>&1 || \
                nohup /usr/bin/sourceless-os-updater check-and-stage >/dev/null 2>&1 &
        fi

    elif [ "$CMD" = "set_channel_stable" ]; then
        if [ -x /usr/bin/sourceless-os-updater ]; then
            /usr/bin/sourceless-os-updater set-channel stable >/dev/null 2>&1 || true
            systemd-run --no-block --unit=sourceless-remote-update /usr/bin/sourceless-os-updater check-and-stage >/dev/null 2>&1 || \
                nohup /usr/bin/sourceless-os-updater check-and-stage >/dev/null 2>&1 &
        fi

    elif [ "$CMD" = "set_channel_testing" ]; then
        if [ -x /usr/bin/sourceless-os-updater ]; then
            /usr/bin/sourceless-os-updater set-channel testing >/dev/null 2>&1 || true
            systemd-run --no-block --unit=sourceless-remote-update /usr/bin/sourceless-os-updater check-and-stage >/dev/null 2>&1 || \
                nohup /usr/bin/sourceless-os-updater check-and-stage >/dev/null 2>&1 &
        fi

    elif [ "$CMD" = "reboot_device" ]; then
        systemctl reboot || true

    elif [ "$CMD" = "start_support" ]; then
        rm -f /tmp/sourceless_support_active
        pkill -f zenity 2>/dev/null || true

        # Resolve active graphical session parameters (strictly filter for interactive user sessions UID >= 1000)
        ACTIVE_USER=$(loginctl list-sessions --no-legend 2>/dev/null | awk '$2 >= 1000 && $6 == "user" {print $3; exit}')
        [ -z "$ACTIVE_USER" ] && ACTIVE_USER=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1; exit}' /etc/passwd)
        [ -z "$ACTIVE_USER" ] && ACTIVE_USER="sourceless"

        ACTIVE_UID=$(id -u "$ACTIVE_USER" 2>/dev/null)
        [ -z "$ACTIVE_UID" ] && ACTIVE_UID="1000"

        WAYLAND_SOCK=$(ls /run/user/${ACTIVE_UID}/wayland-* 2>/dev/null | grep -E 'wayland-[0-9]+$' | head -n 1)
        WAYLAND_NAME=$(basename "$WAYLAND_SOCK" 2>/dev/null)
        [ -z "$WAYLAND_NAME" ] && WAYLAND_NAME="wayland-0"

        if systemd-run --machine="${ACTIVE_USER}@.host" --user --pipe --wait \
            --setenv=WAYLAND_DISPLAY="$WAYLAND_NAME" \
            --setenv=XDG_RUNTIME_DIR="/run/user/${ACTIVE_UID}" \
            --setenv=DISPLAY=":0" \
            --setenv=QT_QPA_PLATFORM="wayland;xcb" \
            /usr/bin/sourceless-support-dialog.py; then

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