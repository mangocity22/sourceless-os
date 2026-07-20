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

# Verificăm dacă există flag-ul de sesiune activă pornit de Dashboard
if [ -f /var/run/sourceless_support_active ]; then
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

# Forțăm drepturile de execuție pentru toate scripturile administrative Sourceless
chmod +x /usr/bin/sourceless-unlock
chmod +x /usr/bin/sourceless-client-boot.sh
chmod +x /usr/bin/sourceless-cert-verify.sh

echo "[Sourceless] setup-permissions.sh s-a executat cu succes!"