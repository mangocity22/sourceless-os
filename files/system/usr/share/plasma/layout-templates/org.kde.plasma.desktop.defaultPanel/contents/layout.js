// Clean up any pre-existing panels before applying the Liquid Glass layout
var existingPanels = panels();
for (var i = 0; i < existingPanels.length; i++) {
    existingPanels[i].remove();
}

// 1. BOTTOM-LEFT CORNER (Official Plasma Application Launcher)
var startPanel = new Panel;
startPanel.location = "bottom";
startPanel.alignment = "left";
startPanel.lengthMode = "custom";
startPanel.length = 90;
startPanel.minimumLength = 90;
startPanel.maximumLength = 90;
startPanel.height = 90;
startPanel.floating = false;

var kickoff = startPanel.addWidget("org.kde.plasma.kickoff");
kickoff.currentConfigGroup = ["General"];
kickoff.writeConfig("icon", "sourceless-logo");

// 2. CENTER FLOATING ISLAND (Application Dock)
var dockPanel = new Panel;
dockPanel.location = "bottom";
dockPanel.alignment = "center";
dockPanel.lengthMode = "fit";
dockPanel.writeConfig("panelLengthMode", 1);
dockPanel.height = 56;
dockPanel.floating = true;

var tasks = dockPanel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "preferred://filemanager",
    "preferred://browser"
]);

// 3. BOTTOM-RIGHT CORNER (Liquid Glass Clock & Date)
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

// 4. TOP-RIGHT FLOATING STATUS PILL (System Tray)
var trayPanel = new Panel;
trayPanel.location = "right";
// "left" on a vertical panel aligns to the top of the display
trayPanel.alignment = "left";
trayPanel.offset = 12;
trayPanel.lengthMode = "fit";
trayPanel.writeConfig("panelLengthMode", 1);
trayPanel.height = 44;
trayPanel.floating = true;
trayPanel.addWidget("org.kde.plasma.systemtray");