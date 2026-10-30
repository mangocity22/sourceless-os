// 1. Initializam ecranele si desktop-ul utilizatorului
for (var sIndex = 0; sIndex < screenCount; ++sIndex) {
    var d = new Activity("org.kde.plasma.folder");
    d.screen = sIndex;
    d.wallpaperPlugin = "org.kde.image";
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    d.writeConfig("Image", "/usr/share/wallpapers/SourceLess/contents/images/3840x2160.jpg");

    // 2. Curatam eventuale panouri preexistente pe acest ecran
    var pList = panels();
    for (var p = pList.length - 1; p >= 0; p--) {
        if (pList[p].screen === sIndex) {
            pList[p].remove();
        }
    }

    // 3. Cream Capsula Flotanta Sourceless (52px)
    var bar = new Panel("org.kde.plasma.panel");
    bar.screen = sIndex;
    bar.location = "bottom";
    bar.height = 52;
    bar.floating = true;
    bar.hiding = "windowsgobelow";

    // 4. Kickoff Start Launcher (Logo Sourceless)
    var kickoff = bar.addWidget("org.kde.plasma.kickoff");
    kickoff.currentConfigGroup = ["General"];
    kickoff.writeConfig("icon", "sourceless-logo");

    // 5. Distantier elastic stanga (impinge aplicatiile pe centru)
    bar.addWidget("org.kde.plasma.panelspacer");

    // 6. Icons-Only Task Manager (centrat)
    var tasks = bar.addWidget("org.kde.plasma.icontasks");
    tasks.currentConfigGroup = ["General"];
    tasks.writeConfig("launchers", [
        "preferred://filemanager",
        "preferred://browser"
    ]);

    // 7. Distantier elastic dreapta
    bar.addWidget("org.kde.plasma.panelspacer");

    // 8. System Tray compact
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

    // 9. Digital Clock calibrat
    var clock = bar.addWidget("org.kde.plasma.digitalclock");
    clock.currentConfigGroup = ["Appearance"];
    clock.writeConfig("autoFontAndSize", false);
    clock.writeConfig("fontSize", 10.5);
    clock.writeConfig("boldText", true);
    clock.writeConfig("showDate", true);
    clock.writeConfig("dateFormat", "shortDate");
    clock.writeConfig("showSeconds", "Never");
    clock.writeConfig("use24hFormat", "2");
}