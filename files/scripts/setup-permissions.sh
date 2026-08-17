#!/usr/bin/bash
# În faza de build a imaginii:

# Verificăm defensiv dacă binarul există și nu a fost deja mutat
if [ -f /usr/bin/konsole ] && [ ! -f /usr/bin/konsole.real ]; then
    echo "[Sourceless] Se mută binarul Konsole original..."
    mv /usr/bin/konsole /usr/bin/konsole.real
else
    echo "[Sourceless] Konsole original nu a fost găsit sau a fost deja mutat. Skip."
fi

# Creăm scriptul capcană inteligent
echo "[Sourceless] Se generează wrapper-ul de securitate..."
cat << 'EOF' > /usr/bin/konsole
#!/usr/bin/bash

# Verificăm dacă există flag-ul de sesiune activă (în /tmp sau /var/run)
if [ -f /tmp/sourceless_support_active ] || [ -f /var/run/sourceless_support_active ]; then
    # Sesiunea de suport este activă! Tehnicianul are voie să folosească terminalul
    exec /usr/bin/konsole.real "$@"
else
    # Utilizatorul normal încearcă să deschidă terminalul fraudulos
    kdialog --error "Access Denied. Terminal execution is restricted on Sourceless-OS." --title "Security Policy"
    exit 1
fi
EOF

# Ne asigurăm că scriptul capcană are drepturi de execuție
chmod +x /usr/bin/konsole

# Drepturi stricte: doar root poate citi și executa scripturile interne
chmod 700 /usr/bin/sourceless-unlock
chmod 700 /usr/bin/sourceless-client-boot.sh
chmod 700 /usr/bin/sourceless-cert-verify.sh
chmod 644 /etc/profile.d/sourceless-shell-guard.sh
chmod +x /etc/grub.d/40_custom_sourceless

# Permisiuni pe regulile de securitate și sudoers
chmod 0440 /etc/sudoers.d/sourceless-lockdown
chmod 0644 /etc/polkit-1/rules.d/10-sourceless-security.rules

# Activare servicii de sistem
systemctl enable sourceless-client.service
systemctl enable sourceless-cert-server.service

# Dezactivare servicii de rețea neutilizate (KDE Connect)
systemctl --global mask kdeconnectd.service 2>/dev/null || true

# Scoate utilizatorul din grupul wheel (administratori)
if id "sourceless" &>/dev/null; then
    gpasswd -d sourceless wheel 2>/dev/null || true
    usermod -g sourceless -G users sourceless
fi

echo "[Sourceless] setup-permissions.sh s-a executat cu succes!"