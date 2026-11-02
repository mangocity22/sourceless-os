// Clean up any pre-existing panels
var existingPanels = panels();
for (var i = existingPanels.length - 1; i >= 0; i--) {
    existingPanels[i].remove();
}

// 1. Unified Floating Liquid Glass Panel (52px)
var bar = new Panel;
bar.location = "bottom";
bar.thickness = 52; // Modificat pentru Plasma 6
bar.floating = true;
bar.hiding = "windowsgobelow";
bar.writeConfig("panelOpacity", 2);

// 2. Sourceless Start Button (în loc de Kickoff)
var kickoff = bar.addWidget("org.sourceless.start");

// 3. Spacer elastic stanga
bar.addWidget("org.kde.plasma.panelspacer");

// 4. Icons-Only Task Manager centrat
var tasks = bar.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", "preferred://filemanager,preferred://browser");

// 5. Spacer elastic dreapta
bar.addWidget("org.kde.plasma.panelspacer");

// 6. System Tray compact
var tray = bar.addWidget("org.kde.plasma.systemtray");
tray.currentConfigGroup = ["General"];
tray.writeConfig("scaleIconsToFit", "false");
tray.writeConfig("shownItems", "org.kde.plasma.networkmanagement,org.kde.plasma.volume");
tray.writeConfig("hiddenItems", "org.kde.plasma.clipboard,org.kde.plasma.brightness,org.kde.plasma.devicenotifier,org.kde.plasma.notifications");

// 7. Ceas Digital Sourceless (în loc de digitalclock)
var clock = bar.addWidget("org.sourceless.clock");