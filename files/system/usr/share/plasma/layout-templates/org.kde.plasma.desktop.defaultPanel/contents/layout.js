// Curatam panourile existente
var existingPanels = panels();
for (var i = 0; i < existingPanels.length; i++) {
    existingPanels[i].remove();
}

// 1. PANOU STÂNGA JOS (Buton Start)
var startPanel = new Panel;
startPanel.location = "bottom";
startPanel.alignment = "left";
startPanel.height = 64;
startPanel.length = 80;
startPanel.floating = false;
var startWidget = startPanel.addWidget("org.kde.plasma.kickoff");
startWidget.currentConfigGroup = ["General"];
startWidget.writeConfig("icon", "sourceless");

// 2. INSULA CENTRALĂ (Dock Aplicații Plutitor)
var dockPanel = new Panel;
dockPanel.location = "bottom";
dockPanel.alignment = "center";
dockPanel.height = 56;
dockPanel.floating = true;
var tasks = dockPanel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:firefox.desktop"
]);

// 3. PANOU DREAPTA JOS (Ceas & Dată)
var clockPanel = new Panel;
clockPanel.location = "bottom";
clockPanel.alignment = "right";
clockPanel.height = 64;
clockPanel.length = 100;
clockPanel.floating = false;
clockPanel.addWidget("org.kde.plasma.digitalclock");

// 4. PASTILA DE STATUS (System Tray Plutitor deasupra ceasului)
var trayPanel = new Panel;
trayPanel.location = "right";
trayPanel.alignment = "bottom";
trayPanel.height = 44;
trayPanel.length = 120;
trayPanel.floating = true;
var tray = trayPanel.addWidget("org.kde.plasma.systemtray");