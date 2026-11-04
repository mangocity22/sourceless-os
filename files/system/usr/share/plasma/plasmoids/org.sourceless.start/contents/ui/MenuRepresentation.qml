/*****************************************************************************
 *   Copyright (C) 2014 by Weng Xuetian <wengxt@gmail.com>                   *
 *   Copyright (C) 2013-2017 by Eike Hein <hein@kde.org>                     *
 *   Copyright (C) 2021 by Prateek SU <pankajsunal123@gmail.com>             *
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

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQml 2.15

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents

import org.kde.plasma.plasmoid 2.0
import org.kde.kirigami as Kirigami

PlasmaCore.Dialog {
    id: root

    objectName: "popupWindow"
    flags: Qt.WindowStaysOnTopHint

    location: Plasmoid.configuration.floating || Plasmoid.configuration.launcherPosition == 2 ? "Floating" : Plasmoid.location
    hideOnWindowDeactivate: true

    Plasmoid.status: root.visible ? PlasmaCore.Types.RequiresAttentionStatus : PlasmaCore.Types.PassiveStatus

    property int iconSize: { 
      switch(Plasmoid.configuration.appsIconSize){
        case 0: return Kirigami.Units.iconSizes.smallMedium;
        case 1: return Kirigami.Units.iconSizes.medium;
        case 2: return Kirigami.Units.iconSizes.large;
        case 3: return Kirigami.Units.iconSizes.huge;
        default: return 64
      }
    }

    property int cellSizeHeight: iconSize
                                     + Kirigami.Units.gridUnit * 2
                                     + (2 * Math.max(highlightItemSvg.margins.top + highlightItemSvg.margins.bottom,
                                                     highlightItemSvg.margins.left + highlightItemSvg.margins.right))
    property int cellSizeWidth: cellSizeHeight //+ Kirigami.Units.gridUnit
    
    property int rows: Plasmoid.configuration.numberOfRows
    // Fixed number of app columns (apps per row)
    property int columns: 4
    
    onVisibleChanged: {
        if (!visible) {
            reset();
        } else {
            var pos = popupPosition(width, height);
            x = pos.x;
            y = pos.y;
            requestActivate();
        }
    }

    onHeightChanged: {
        var pos = popupPosition(width, height);
        x = pos.x;
        y = pos.y;
    }

    onWidthChanged: {
        var pos = popupPosition(width, height);
        x = pos.x;
        y = pos.y;
    }

    function toggle() {
      root.visible = false;
    }

    function reset() {
        main.reset()
    }

    // Fixed popup offsets from the screen edges (px)
    property int marginLeft: 20
    property int marginBottom: 72

    function popupPosition(width, height) {
        var screen = kicker.screenGeometry;

        var x = screen.x + marginLeft;
        var y = screen.y + screen.height - height - marginBottom;

        return Qt.point(x, y);
    }

    FocusScope {
        id: fs
        focus: true
        Layout.minimumWidth:  (root.cellSizeWidth * root.columns) + scrollBarMetrics.width + innerPadding*2
        Layout.minimumHeight: main.headerLabelRow.height
                              + main.searchBar.height
                              + main.contentY.y
                              + main.itemSpacing * 3
                              + root.cellSizeHeight * rows
                              + innerPadding / 2
        Layout.maximumWidth: Layout.minimumWidth
        Layout.maximumHeight: Layout.minimumHeight
        
        // We want the MainView to have an uniform margin through different plasma themes
        property real innerPadding: 15 

        Item {
          id: mainItem
          x: - dialogSvg.margins.left
          y: - dialogSvg.margins.top
          width: parent.width + dialogSvg.margins.left + dialogSvg.margins.right
          height: parent.height + dialogSvg.margins.top + dialogSvg.margins.bottom

          MainView {
            id: main
            
            anchors.fill: parent
            anchors.margins: fs.innerPadding
          }
        }

        Keys.onPressed: event => {
            if (event.key == Qt.Key_Escape) {
                root.visible = false;
            }
        }
    }

    Component.onCompleted: {
        kicker.reset.connect(reset);
       // windowSystem.hidden.connect(reset);
        rootModel.refresh();
    }
}
