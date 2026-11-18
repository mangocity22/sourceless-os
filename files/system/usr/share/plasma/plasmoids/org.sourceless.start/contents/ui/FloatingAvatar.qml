/*****************************************************************************
 *   Copyright (C) 2022 by Friedrich Schriewer <friedrich.schriewer@gmx.net> *
 *                                                                           *
 *   This program is free software; you can redistribute it and/or modify    *
 *   it under the terms of the GNU General Public License as published by    *
 *   the Free Software Foundation; either version 2 of the License, or       *
 *   (at your option) any later version.                                     *
 *                                                                           *
 *   This program is distributed in the hope that it will be useful,         *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of          *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           *
 *   GNU General Public License for more details.                            *
 *                                                                           *
 *   You should have received a copy of the GNU General Public License       *
 *   along with this program; if not, write to the                           *
 *   Free Software Foundation, Inc.,                                         *
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA .          *
 ****************************************************************************/
import QtQuick 2.12
import QtQuick.Window 2.2
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.components 1.0 as KirigamiComponents
import org.kde.kcmutils as KCM

// Floating overlay dialog displaying the user avatar centered above the launcher top border
PlasmaCore.Dialog {
    id: avatarContainer

    property int avatarWidth
    property bool isTop: false

    type: "Notification"

    // Position dialog centered horizontally over the launcher top edge
    x: root.x + root.width / 2 - width / 2
    y: root.y - width / 2

    // Remove the default Plasma dialog background frame when the popup window attaches
    mainItem: Item {
        onParentChanged: {
            if (parent) {
                var popupWindow = Window.window
                if (typeof popupWindow.backgroundHints !== "undefined") {
                    popupWindow.backgroundHints = PlasmaCore.Types.NoBackground
                }
            }
        }
    }

    UserAvatar {
        id: avatarFrame
        anchors.centerIn: parent
        width: avatarWidth
        height: avatarWidth
    }
}
