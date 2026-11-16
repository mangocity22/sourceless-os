/*
    SPDX-FileCopyrightText: 2026 Sourceless OS
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Window
import org.kde.plasma.core as PlasmaCore

Item {
    id: lockScreenRoot

    // kscreenlocker_greet attaches the wallpaper item behind LockScreen.
    // Keep the root transparent so the user's configured or Sourceless wallpaper shows through,
    // while LockScreenUi handles the Liquid Glass blur & frosted overlay.
    anchors.fill: parent

    property bool uiVisible: true
    property alias lockScreenUi: ui

    LockScreenUi {
        id: ui
        anchors.fill: parent
    }
}
