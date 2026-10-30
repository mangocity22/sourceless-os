// Daca exista deja panouri, nu le distrugem
if (panels().length === 0) {
    loadTemplate("org.kde.plasma.desktop.defaultPanel");
}