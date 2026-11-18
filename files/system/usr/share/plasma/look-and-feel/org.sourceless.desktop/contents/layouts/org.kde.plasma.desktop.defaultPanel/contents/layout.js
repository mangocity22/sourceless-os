// Load the default Sourceless panel template only if no panels exist
if (panels().length === 0) {
    loadTemplate("org.kde.plasma.desktop.defaultPanel");
}
