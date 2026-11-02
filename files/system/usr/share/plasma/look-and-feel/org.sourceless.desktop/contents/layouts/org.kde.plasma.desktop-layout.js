// 1. Setare activitate curenta
var activityId = currentActivity();

// 2. Configurarea spatiului de lucru (Desktop / Wallpaper)
var desktopsArray = desktopsForActivity(activityId);
for (var j = 0; j < desktopsArray.length; j++) {
    desktopsArray[j].wallpaperPlugin = "org.kde.image";
}

// 3. Creare Panou cu asociere explicita de template
var bar = new Panel("org.kde.panel");
bar.location = "bottom";
bar.thickness = 52;
bar.floating = true;
bar.hiding = "windowsgobelow";

// Scriem activitatea explicit ca sa nu mai rateze System Settings
bar.writeConfig("activityId", activityId);
bar.writeConfig("panelOpacity", 2);

// 4. Populam widget-urile
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

bar.addWidget("org.sourceless.clock");