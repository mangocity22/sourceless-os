// Clean up any pre-existing panels
var existingPanels = panels();
for (var i = existingPanels.length - 1; i >= 0; i--) {
    existingPanels[i].remove();
}

// 1. Unified Floating Liquid Glass Island (52px)
var bar = new Panel;
bar.location = "bottom";
bar.height = 52;
bar.floating = true;
bar.hiding = "windowsgobelow";

// 2. Kickoff Start Launcher (Sourceless Logo)
var kickoff = bar.addWidget("org.kde.plasma.kickoff");
kickoff.currentConfigGroup = ["General"];
kickoff.writeConfig("icon", "sourceless-logo");

// 3. Distantier elastic stanga (centreaza task manager-ul)
bar.addWidget("org.kde.plasma.panelspacer");

// 4. Centered Icons-Only Task Manager
var tasks = bar.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "preferred://filemanager",
    "preferred://browser"
]);

// 5. Distantier elastic dreapta
bar.addWidget("org.kde.plasma.panelspacer");

// 6. System Tray compact
var tray = bar.addWidget("org.kde.plasma.systemtray");
tray.currentConfigGroup = ["General"];
tray.writeConfig("scaleIconsToFit", false);
tray.writeConfig("shownItems", [
    "org.kde.plasma.networkmanagement",
    "org.kde.plasma.volume"
]);
tray.writeConfig("hiddenItems", [
    "org.kde.plasma.clipboard",
    "org.kde.plasma.brightness",
    "org.kde.plasma.devicenotifier",
    "org.kde.plasma.notifications"
]);

// 7. Ceas & Data (Digital Clock)
var clock = bar.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("autoFontAndSize", false);
clock.writeConfig("fontSize", 10.5);
clock.writeConfig("boldText", true);
clock.writeConfig("showDate", true);
clock.writeConfig("dateFormat", "shortDate");
clock.writeConfig("showSeconds", "Never");
clock.writeConfig("use24hFormat", "2");