// 1. Configurarea spatiului de lucru (Desktop / Wallpaper)
var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    desktopsArray[j].wallpaperPlugin = "org.kde.image";
}

// 2. Capsula flotanta Sourceless (52px)
var bar = new Panel;
bar.location = "bottom";
bar.height = 52;
bar.floating = true;
bar.hiding = "windowsgobelow";

// 3. Buton Start (Kickoff cu logo Sourceless)
var kickoff = bar.addWidget("org.kde.plasma.kickoff");
kickoff.currentConfigGroup = ["General"];
kickoff.writeConfig("icon", "sourceless-logo");

// 4. Distantier elastic stanga
bar.addWidget("org.kde.plasma.panelspacer");

// 5. Icons-Only Task Manager centrat
var tasks = bar.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "preferred://filemanager",
    "preferred://browser"
]);

// 6. Distantier elastic dreapta
bar.addWidget("org.kde.plasma.panelspacer");

// 7. System Tray compact
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

// 8. Ceas Digital (text alb, lizibil)
var clock = bar.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("autoFontAndSize", false);
clock.writeConfig("fontSize", 10.5);
clock.writeConfig("boldText", true);
clock.writeConfig("showDate", true);
clock.writeConfig("dateFormat", "shortDate");
clock.writeConfig("showSeconds", "Never");
clock.writeConfig("use24hFormat", "2");