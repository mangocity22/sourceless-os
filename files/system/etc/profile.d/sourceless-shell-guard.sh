#!/usr/bin/bash
# /etc/profile.d/sourceless-shell-guard.sh
# Blocks interactive shell sessions for standard users unless an approved support session is active

# 1. Enforce restriction only for non-root users (UID >= 1000)
if [ "$(id -u)" -ge 1000 ]; then

    # 2. Check if the current shell is interactive
    if [[ $- == *i* ]]; then

        # 3. Require an active support session flag before allowing shell interaction
        if [ ! -f /tmp/sourceless_support_active ] && [ ! -f /var/run/sourceless_support_active ]; then

            # Display a graphical error under X11/Wayland, or print to stderr otherwise
            if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
                kdialog --error "Access Denied.\n\nInteractive terminal access is strictly disabled on Sourceless-OS." --title "Sourceless Security Policy" 2>/dev/null &
            else
                echo "[-] Access Denied: Interactive terminal execution is restricted."
            fi

            # Terminate the unauthorized interactive shell immediately
            exit 1
        fi
    fi
fi
