# În faza de build a imaginii:
# Redenumim binarul real al consolei
mv /usr/bin/konsole /usr/bin/konsole.real

# Creăm scriptul capcană inteligent
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

chmod +x /usr/bin/konsole