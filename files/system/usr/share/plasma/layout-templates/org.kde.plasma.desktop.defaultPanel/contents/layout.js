// Curățăm orice panou vechi
var existingPanels = panels();
for (var i = 0; i < existingPanels.length; i++) {
    existingPanels[i].remove();
}

// 1. COLȚUL STÂNGA JOS (Start)
var startPanel = new Panel;
startPanel.location = "bottom";
startPanel.alignment = "left";
startPanel.lengthMode = "custom";
startPanel.length = 90;
startPanel.minimumLength = 90;
startPanel.maximumLength = 90;
startPanel.height = 90;
startPanel.floating = false;
startPanel.addWidget("org.sourceless.start");

// 2. INSULA CENTRALĂ (Dock Aplicații Plutitor)
var dockPanel = new Panel;
dockPanel.location = "bottom";
dockPanel.alignment = "center";
dockPanel.lengthMode = "fit"; // Se ajustează dinamic după câte iconițe ai deschise
dockPanel.height = 56;
dockPanel.floating = true;
var tasks = dockPanel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:firefox.desktop"
]);

// 3. COLȚUL DREAPTA JOS (Ceas)
var clockPanel = new Panel;
clockPanel.location = "bottom";
clockPanel.alignment = "right";
clockPanel.lengthMode = "custom";
clockPanel.length = 110;
clockPanel.minimumLength = 110;
clockPanel.maximumLength = 110;
clockPanel.height = 90;
clockPanel.floating = false;
clockPanel.addWidget("org.sourceless.clock");

// 4. PASTILA DE STATUS (Tray vertical dreapta)
var trayPanel = new Panel;
trayPanel.location = "right";
trayPanel.alignment = "bottom";
trayPanel.lengthMode = "fit";
trayPanel.height = 44;
trayPanel.floating = true;
trayPanel.addWidget("org.kde.plasma.systemtray");