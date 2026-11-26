// Default floating bottom panel template for SourceLess OS (Plasma 6)
var bar = new Panel("org.kde.panel");
bar.location = "bottom";
bar.height = 52;
bar.floating = true;
bar.hiding = "windowsgobelow";

// Write native Plasma 6 containment keys directly in the root config group
bar.currentConfigGroup = [];
bar.writeConfig("thickness", 52);
bar.writeConfig("floating", 1);
bar.writeConfig("panelVisibility", 2);
bar.writeConfig("panelOpacity", 2);
bar.writeConfig("panelLengthMode", 0);

// Sourceless Start Menu launcher
var kickoff = bar.addWidget("org.sourceless.start");
kickoff.currentConfigGroup = ["General"];
kickoff.writeConfig("icon", "sourceless-logo");

// Left flexible spacer to center the task manager
bar.addWidget("org.kde.plasma.panelspacer");

// Centered Icons-Only Task Manager with pinned file manager and browser
var tasks = bar.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", "preferred://filemanager,preferred://browser");

// Right flexible spacer
bar.addWidget("org.kde.plasma.panelspacer");

// Compact system tray showing network and volume by default
var tray = bar.addWidget("org.kde.plasma.systemtray");
tray.currentConfigGroup = ["General"];
tray.writeConfig("scaleIconsToFit", "false");
tray.writeConfig("shownItems", "org.kde.plasma.networkmanagement,org.kde.plasma.volume");
tray.writeConfig("hiddenItems", "org.kde.plasma.clipboard,org.kde.plasma.brightness,org.kde.plasma.devicenotifier,org.kde.plasma.notifications");

// Sourceless digital clock and calendar widget
bar.addWidget("org.sourceless.clock");
