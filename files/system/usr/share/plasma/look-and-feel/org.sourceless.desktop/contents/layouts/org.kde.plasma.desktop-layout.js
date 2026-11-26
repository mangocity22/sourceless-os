// 1. Configure image wallpaper plugin across all desktops (avoids currentActivity issues)
var d = desktops();
for (var i = 0; i < d.length; i++) {
    d[i].wallpaperPlugin = "org.kde.image";
}

// 2. Create the floating Sourceless bottom panel (52px)
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

// 3. Add Sourceless Start Menu launcher
var kickoff = bar.addWidget("org.sourceless.start");
kickoff.currentConfigGroup = ["General"];
kickoff.writeConfig("icon", "sourceless-logo");

// 4. Left flexible spacer
bar.addWidget("org.kde.plasma.panelspacer");

// 5. Centered Icons-Only Task Manager (use comma-separated string for DBus/KConfig compatibility)
var tasks = bar.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", "preferred://filemanager,preferred://browser");

// 6. Right flexible spacer
bar.addWidget("org.kde.plasma.panelspacer");

// 7. Compact System Tray (use comma-separated strings for native KConfig serialization)
var tray = bar.addWidget("org.kde.plasma.systemtray");
tray.currentConfigGroup = ["General"];
tray.writeConfig("scaleIconsToFit", "false");
tray.writeConfig("shownItems", "org.kde.plasma.networkmanagement,org.kde.plasma.volume");
tray.writeConfig("hiddenItems", "org.kde.plasma.clipboard,org.kde.plasma.brightness,org.kde.plasma.devicenotifier,org.kde.plasma.notifications");

// 8. Add Sourceless digital clock widget
bar.addWidget("org.sourceless.clock");
