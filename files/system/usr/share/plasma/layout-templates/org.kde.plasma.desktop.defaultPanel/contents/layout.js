var bar = new Panel("org.kde.panel");
bar.location = "bottom";
bar.height = 52;
bar.floating = true;

// Scriem direct cheile native Plasma 6 în grupul de bază al Containment-ului
bar.currentConfigGroup = [];
bar.writeConfig("thickness", 52);
bar.writeConfig("floating", 1);
bar.writeConfig("panelVisibility", 2);
bar.writeConfig("panelOpacity", 2);
bar.writeConfig("panelLengthMode", 0);

var kickoff = bar.addWidget("org.kde.plasma.kickoff");
kickoff.currentConfigGroup = ["General"];
kickoff.writeConfig("icon", "sourceless-logo");

bar.addWidget("org.kde.plasma.panelspacer");

var tasks = bar.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", "preferred://filemanager,preferred://browser");

bar.addWidget("org.kde.plasma.panelspacer");

var tray = bar.addWidget("org.kde.plasma.systemtray");
tray.currentConfigGroup = ["General"];
tray.writeConfig("scaleIconsToFit", "false");
tray.writeConfig("shownItems", "org.kde.plasma.networkmanagement,org.kde.plasma.volume");
tray.writeConfig("hiddenItems", "org.kde.plasma.clipboard,org.kde.plasma.brightness,org.kde.plasma.devicenotifier,org.kde.plasma.notifications");

bar.addWidget("org.sourceless.clock");