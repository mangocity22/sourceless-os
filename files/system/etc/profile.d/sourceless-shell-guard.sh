#!/usr/bin/bash
# /etc/profile.d/sourceless-shell-guard.sh
# Blochează orice sesiune interactivă de shell dacă suportul tehnic nu este activ.

# 1. Aplicăm regula DOAR pentru utilizatorii obișnuiți (UID >= 1000), NU și pentru root
if [ "$(id -u)" -ge 1000 ]; then

    # 2. Verificăm dacă shell-ul este interactiv (adică a fost deschis o consolă/terminal)
    if [[ $- == *i* ]]; then

        # 3. Verificăm dacă există flag-ul de sesiune de suport aprobată
        if [ ! -f /tmp/sourceless_support_active ] && [ ! -f /var/run/sourceless_support_active ]; then
            
            # Afișăm o eroare grafică dacă există sesiune X11/Wayland
            if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
                kdialog --error "Access Denied.\n\nInteractive terminal access is strictly disabled on Sourceless-OS." --title "Sourceless Security Policy" 2>/dev/null &
            else
                echo "[-] Access Denied: Interactive terminal execution is restricted."
            fi

            # Închidem instantaneu sesiunea de terminal
            exit 1
        fi
    fi
fi