// 1. Wallpaper pentru toate desktop-urile (Metoda sigură, fără currentActivity)
var d = desktops();
for (var i = 0; i < d.length; i++) {
    d[i].wallpaperPlugin = "org.kde.image";
}

// 2. Creare capsulă flotantă
var bar = new Panel;
bar.location = "bottom";
bar.thickness = 52;
bar.floating = true;
bar.hiding = "windowsgobelow";

// 3. Buton Start 
var kickoff = bar.addWidget("org.sourceless.start");
kickoff.currentConfigGroup = ["General"];
kickoff.writeConfig("icon", "sourceless-logo");

// 4. Distanțier stânga
bar.addWidget("org.kde.plasma.panelspacer");

// 5. Task Manager
var tasks = bar.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
// Transformat in string pentru a nu bloca serializarea DBus
tasks.writeConfig("launchers", "preferred://filemanager,preferred://browser");

// 6. Distanțier dreapta
bar.addWidget("org.kde.plasma.panelspacer");

// 7. System Tray
var tray = bar.addWidget("org.kde.plasma.systemtray");
tray.currentConfigGroup = ["General"];
tray.writeConfig("scaleIconsToFit", "false");
// Transformate din array-uri in string-uri separate prin virgula (nativ pentru KConfig)
tray.writeConfig("shownItems", "org.kde.plasma.networkmanagement,org.kde.plasma.volume");
tray.writeConfig("hiddenItems", "org.kde.plasma.clipboard,org.kde.plasma.brightness,org.kde.plasma.devicenotifier,org.kde.plasma.notifications");

// 8. Ceasul Sourceless
bar.addWidget("org.sourceless.clock");