import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.coreaddons 1.0 as KCoreAddons
import org.kde.kirigamiaddons.components 1.0 as KirigamiComponents

ApplicationWindow {
    id: root
    width: 1160
    height: 780
    minimumWidth: 940
    minimumHeight: 640
    visible: true
    title: "Sourceless Control Center"
    color: "transparent"

    KCoreAddons.KUser {
        id: kuser
    }

    // Sourceless Glass Design Tokens (Windows 11 Mica/Acrylic Dark Inspired)
    readonly property color brandHighlight: "#6054F2"
    readonly property color brandHighlightHover: "#7368F7"
    readonly property color bgWindow: Qt.rgba(0.07, 0.08, 0.12, 0.88)
    readonly property color bgSidebar: Qt.rgba(0.05, 0.06, 0.09, 0.65)
    readonly property color bgCard: Qt.rgba(0.13, 0.15, 0.21, 0.72)
    readonly property color bgCardHover: Qt.rgba(0.16, 0.18, 0.26, 0.82)
    readonly property color bgInput: Qt.rgba(0.09, 0.10, 0.15, 0.92)
    readonly property color borderSubtle: Qt.rgba(1, 1, 1, 0.08)
    readonly property color textMain: "#E8ECFF"
    readonly property color textMuted: "#949BC0"
    readonly property color statusGreen: "#2AC3A2"
    readonly property color statusAmber: "#F5A623"
    readonly property color statusRed: "#F2546D"

    property int currentPage: 0
    property string selectedWifiSsid: ""

    Component.onCompleted: {
        const pageMap = {
            "home": 0,
            "system": 1,
            "bluetooth": 2,
            "network": 3,
            "personalization": 4,
            "apps": 5,
            "time": 6,
            "security": 7
        }
        if (backend && pageMap[backend.initialPage] !== undefined) {
            root.currentPage = pageMap[backend.initialPage]
        }
    }

    // 1. Reusable Windows 11 Setting Card Component
    component SettingCard : Rectangle {
        default property alias cardContent: innerCol.data
        Layout.fillWidth: true
        implicitHeight: innerCol.implicitHeight + 32
        color: root.bgCard
        radius: 10
        border.color: root.borderSubtle
        border.width: 1

        ColumnLayout {
            id: innerCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12
        }
    }

    // 2. Reusable Action Button
    component ActionButton : Rectangle {
        id: btnRoot
        property string labelText: ""
        property bool primary: false
        property bool danger: false
        property bool enabledBtn: true
        signal triggered()

        implicitWidth: Math.max(110, btnLbl.implicitWidth + 28)
        implicitHeight: 34
        radius: 6
        opacity: enabledBtn ? 1.0 : 0.45
        color: {
            if (!enabledBtn) return Qt.rgba(0.2, 0.22, 0.3, 0.5)
            if (danger) return btnMouse.containsMouse ? "#FF647C" : root.statusRed
            if (primary) return btnMouse.containsMouse ? root.brandHighlightHover : root.brandHighlight
            return btnMouse.containsMouse ? Qt.rgba(0.24, 0.27, 0.38, 0.9) : Qt.rgba(0.19, 0.21, 0.30, 0.85)
        }
        border.color: (primary || danger) ? "transparent" : root.borderSubtle
        border.width: 1

        Label {
            id: btnLbl
            anchors.centerIn: parent
            text: btnRoot.labelText
            color: "#FFFFFF"
            font.pixelSize: 13
            font.bold: btnRoot.primary || btnRoot.danger
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btnRoot.enabledBtn ? Qt.PointingHandCursor : Qt.ForbiddenCursor
            onClicked: {
                if (btnRoot.enabledBtn) btnRoot.triggered()
            }
        }
    }

    // 3. Reusable Toggle Pill (Windows 11 Switch)
    component WinSwitch : Rectangle {
        id: switchRoot
        property bool checkedState: false
        signal toggled(bool newValue)

        width: 46
        height: 24
        radius: 12
        color: checkedState ? root.brandHighlight : Qt.rgba(0.25, 0.28, 0.38, 0.9)
        border.color: checkedState ? root.brandHighlightHover : Qt.rgba(1, 1, 1, 0.2)
        border.width: 1

        Rectangle {
            width: 16
            height: 16
            radius: 8
            anchors.verticalCenter: parent.verticalCenter
            x: switchRoot.checkedState ? switchRoot.width - width - 4 : 4
            color: "#FFFFFF"
            Behavior on x { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: switchRoot.toggled(!switchRoot.checkedState)
        }
    }

    // 4. Reusable Windows 11 Slider (Styled with #6054F2 Brand Highlight)
    component WinSlider : Slider {
        id: sliderControl
        implicitWidth: 200
        implicitHeight: 26

        background: Rectangle {
            x: sliderControl.leftPadding
            y: sliderControl.topPadding + sliderControl.availableHeight / 2 - height / 2
            implicitWidth: 200
            implicitHeight: 6
            width: sliderControl.availableWidth
            height: implicitHeight
            radius: 3
            color: Qt.rgba(0.22, 0.25, 0.35, 0.95)

            Rectangle {
                width: sliderControl.visualPosition * parent.width
                height: parent.height
                color: root.brandHighlight
                radius: 3
            }
        }

        handle: Rectangle {
            x: sliderControl.leftPadding + sliderControl.visualPosition * (sliderControl.availableWidth - width)
            y: sliderControl.topPadding + sliderControl.availableHeight / 2 - height / 2
            implicitWidth: 18
            implicitHeight: 18
            radius: 9
            color: sliderControl.pressed ? root.brandHighlightHover : root.brandHighlight
            border.color: "#FFFFFF"
            border.width: 3
        }
    }

    // 5. Reusable Windows 11 ProgressBar (Styled with #6054F2 or Custom Color)
    component WinProgressBar : Item {
        id: progRoot
        property real percentValue: 0
        property color barColor: root.brandHighlight
        Layout.fillWidth: true
        implicitHeight: 8

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: Qt.rgba(0.22, 0.25, 0.35, 0.95)

            Rectangle {
                width: Math.max(6, Math.min(1.0, progRoot.percentValue / 100.0) * parent.width)
                height: parent.height
                radius: 4
                color: progRoot.barColor
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }
        }
    }

    // 6. Reusable Windows 11 Dropdown List (ComboBox)
    component WinComboBox : ComboBox {
        id: comboControl
        implicitWidth: 210
        implicitHeight: 36

        delegate: ItemDelegate {
            id: itemDlgt
            required property var model
            required property int index
            width: comboControl.width
            height: 34
            highlighted: comboControl.highlightedIndex === index

            contentItem: Label {
                text: itemDlgt.model[comboControl.textRole] !== undefined ? itemDlgt.model[comboControl.textRole] : itemDlgt.modelData
                color: "#FFFFFF"
                font.pixelSize: 13
                font.bold: comboControl.currentIndex === itemDlgt.index
                verticalAlignment: Text.AlignVCenter
                leftPadding: 10
            }

            background: Rectangle {
                radius: 6
                color: itemDlgt.highlighted ? root.brandHighlight : (comboControl.currentIndex === itemDlgt.index ? Qt.rgba(0.38, 0.33, 0.95, 0.30) : "transparent")
            }
        }

        indicator: Canvas {
            id: canvas
            x: comboControl.width - width - 12
            y: comboControl.topPadding + (comboControl.availableHeight - height) / 2
            width: 10
            height: 6
            contextType: "2d"

            onPaint: {
                context.reset();
                context.moveTo(0, 0);
                context.lineTo(width, 0);
                context.lineTo(width / 2, height);
                context.closePath();
                context.fillStyle = "#E8ECFF";
                context.fill();
            }
        }

        contentItem: Label {
            leftPadding: 12
            rightPadding: comboControl.indicator.width + 18
            text: comboControl.displayText
            font.pixelSize: 13
            font.bold: true
            color: root.textMain
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            implicitWidth: 210
            implicitHeight: 36
            color: comboControl.down || comboControl.popup.visible ? Qt.rgba(0.18, 0.20, 0.29, 0.98) : root.bgInput
            border.color: comboControl.popup.visible || comboControl. hovered ? root.brandHighlight : root.borderSubtle
            border.width: 1
            radius: 6
        }

        popup: Popup {
            y: comboControl.height + 4
            width: comboControl.width
            implicitHeight: Math.min(280, contentItem.implicitHeight + 12)
            padding: 6

            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: comboControl.popup.visible ? comboControl.delegateModel : null
                currentIndex: comboControl.highlightedIndex
                ScrollIndicator.vertical: ScrollIndicator { }
            }

            background: Rectangle {
                color: Qt.rgba(0.09, 0.10, 0.15, 0.98)
                border.color: root.brandHighlight
                border.width: 1
                radius: 8
            }
        }
    }

    // Main Translucent Window Container
    Rectangle {
        anchors.fill: parent
        color: root.bgWindow
        radius: 18
        clip: true

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // =================================================================
            // LEFT SIDEBAR (Windows 11 Navigation Pane)
            // =================================================================
            Item {
                Layout.preferredWidth: 280
                Layout.fillHeight: true
                clip: true

                // Rounded left corners (top-left & bottom-left = 18px) while keeping the right separator straight
                Rectangle {
                    x: 0
                    y: 0
                    width: parent.width + 18
                    height: parent.height
                    radius: 18
                    color: root.bgSidebar
                }

                Rectangle {
                    width: 1
                    height: parent.height
                    anchors.right: parent.right
                    color: root.borderSubtle
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    // 1. Dynamic User Profile Card with Real Profile Photo
                    Rectangle {
                        Layout.fillWidth: true
                        height: 68
                        radius: 10
                        color: profileMouse.containsMouse ? root.bgCardHover : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 12

                            // Real User Avatar (Matches Start Menu Dog Picture!)
                            Item {
                                width: 48
                                height: 48

                                KirigamiComponents.Avatar {
                                    id: sidebarAvatar
                                    anchors.fill: parent
                                    source: (backend && backend.userAvatar !== "") ? backend.userAvatar : kuser.faceIconUrl
                                    name: backend ? backend.userFullName : kuser.fullName
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    Layout.fillWidth: true
                                    text: (kuser.fullName && kuser.fullName !== "") ? kuser.fullName : (backend ? backend.userFullName : "User")
                                    color: root.textMain
                                    font.pixelSize: 15
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: backend ? (backend.userName + "@" + backend.hostname) : "@sourceless"
                                    color: root.textMuted
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: profileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentPage = 1 // Jump to System/About
                        }
                    }

                    // 2. Windows 11 Search Box
                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        radius: 8
                        color: root.bgInput
                        border.color: searchField.activeFocus ? root.brandHighlight : root.borderSubtle
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 8

                            Kirigami.Icon {
                                source: "search"
                                width: 16
                                height: 16
                                color: root.textMuted
                            }

                            TextField {
                                id: searchField
                                Layout.fillWidth: true
                                placeholderText: "Find a setting..."
                                placeholderTextColor: root.textMuted
                                color: root.textMain
                                font.pixelSize: 13
                                background: Item {}
                                onAccepted: {
                                    const q = text.toLowerCase().trim()
                                    if (!q) return
                                    if (q.includes("wifi") || q.includes("net") || q.includes("ip") || q.includes("dns")) root.currentPage = 3
                                    else if (q.includes("blue") || q.includes("mouse") || q.includes("touch")) root.currentPage = 2
                                    else if (q.includes("wall") || q.includes("theme") || q.includes("blur") || q.includes("dark")) root.currentPage = 4
                                    else if (q.includes("app") || q.includes("flatpak") || q.includes("install")) root.currentPage = 5
                                    else if (q.includes("time") || q.includes("clock") || q.includes("key") || q.includes("lang")) root.currentPage = 6
                                    else if (q.includes("sec") || q.includes("shield") || q.includes("term") || q.includes("support") || q.includes("mod")) root.currentPage = 7
                                    else if (q.includes("sound") || q.includes("vol") || q.includes("disp") || q.includes("res") || q.includes("pow") || q.includes("bat")) root.currentPage = 1
                                    else root.currentPage = 0
                                }
                            }
                        }
                    }

                    // 3. Navigation Categories (Windows 11 Structure)
                    Repeater {
                        model: [
                            { title: "Home", iconName: "go-home", pageIdx: 0 },
                            { title: "System", iconName: "computer", pageIdx: 1 },
                            { title: "Bluetooth & devices", iconName: "preferences-system-bluetooth", pageIdx: 2 },
                            { title: "Network & internet", iconName: "network-wireless", pageIdx: 3 },
                            { title: "Personalization", iconName: "preferences-desktop-wallpaper", pageIdx: 4 },
                            { title: "Apps", iconName: "applications-other", pageIdx: 5 },
                            { title: "Time & language", iconName: "preferences-system-time", pageIdx: 6 },
                            { title: "Privacy & security", iconName: "security-high", pageIdx: 7 }
                        ]

                        delegate: Rectangle {
                            id: navItem
                            required property var modelData
                            readonly property bool isSelected: root.currentPage === modelData.pageIdx

                            Layout.fillWidth: true
                            height: 40
                            radius: 8
                            color: isSelected ? Qt.rgba(0.38, 0.33, 0.95, 0.22) : (navMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")

                            // Windows 11 Left Accent Bar
                            Rectangle {
                                visible: navItem.isSelected
                                width: 4
                                height: 18
                                radius: 2
                                anchors.left: parent.left
                                anchors.leftMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.brandHighlight
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 12
                                spacing: 12

                                Kirigami.Icon {
                                    source: navItem.modelData.iconName
                                    width: 20
                                    height: 20
                                    color: navItem.isSelected ? root.brandHighlight : root.textMuted
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: navItem.modelData.title
                                    color: navItem.isSelected ? "#FFFFFF" : root.textMain
                                    font.pixelSize: 14
                                    font.bold: navItem.isSelected
                                }

                                // Red Warning Badge on Privacy & Security if system is Modified
                                Rectangle {
                                    visible: navItem.modelData.pageIdx === 7 && backend && !backend.overallSecurityOk
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: root.statusRed
                                }
                            }

                            MouseArea {
                                id: navMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.currentPage = navItem.modelData.pageIdx
                                    if (navItem.modelData.pageIdx === 3) backend.refreshNetwork()
                                    else if (navItem.modelData.pageIdx === 2) backend.refreshBluetooth()
                                    else if (navItem.modelData.pageIdx === 5) backend.refreshApps()
                                    else if (navItem.modelData.pageIdx === 7) backend.refreshSecurity()
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Footer Status Pill (Turns RED if Modified/Negative, GREEN if Intact)
                    Rectangle {
                        readonly property bool secOk: backend ? backend.overallSecurityOk : true
                        Layout.fillWidth: true
                        height: 38
                        radius: 8
                        color: secOk ? Qt.rgba(0.16, 0.76, 0.63, 0.12) : Qt.rgba(0.95, 0.33, 0.43, 0.16)
                        border.color: secOk ? Qt.rgba(0.16, 0.76, 0.63, 0.35) : Qt.rgba(0.95, 0.33, 0.43, 0.45)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: (backend && !backend.overallSecurityOk) ? root.statusRed : root.statusGreen
                            }

                            Label {
                                Layout.fillWidth: true
                                text: {
                                    if (backend && backend.statusMessage !== "") return backend.statusMessage
                                    if (backend && !backend.overallSecurityOk) return "Status: " + backend.systemIntegrity
                                    return "Sourceless Lockdown Active"
                                }
                                color: (backend && !backend.overallSecurityOk) ? root.statusRed : root.textMain
                                font.pixelSize: 12
                                font.bold: backend ? !backend.overallSecurityOk : false
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentPage = 7
                        }
                    }
                }
            }

            // =================================================================
            // RIGHT CONTENT AREA (Scrollable Windows 11 Pages)
            // =================================================================
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.currentPage

                // -------------------------------------------------------------
                // PAGE 0: HOME (Windows 11 Hero Overview + Quick Settings)
                // -------------------------------------------------------------
                ScrollView {
                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.width - 64
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 18

                        Item { height: 12 }

                        Label {
                            text: "Home"
                            color: root.textMain
                            font.pixelSize: 28
                            font.bold: true
                        }

                        // Hero Device Banner (Windows 11 Top Overview)
                        SettingCard {
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 20

                                Rectangle {
                                    width: 64
                                    height: 64
                                    radius: 14
                                    color: Qt.rgba(0.38, 0.33, 0.95, 0.2)
                                    border.color: root.brandHighlight
                                    border.width: 1

                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        source: "computer"
                                        width: 36
                                        height: 36
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Label {
                                        text: backend ? backend.hostname : "sourceless-node"
                                        color: root.textMain
                                        font.pixelSize: 20
                                        font.bold: true
                                    }

                                    Label {
                                        text: backend ? (backend.osName + "  •  " + backend.cpuModel) : "Sourceless OS"
                                        color: root.textMuted
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    RowLayout {
                                        spacing: 18
                                        Label {
                                            text: backend && backend.networkConnected ? ("● " + backend.connectionType + ": " + backend.activeNetworkName) : "● Network: Offline"
                                            color: backend && backend.networkConnected ? root.statusGreen : root.statusRed
                                            font.pixelSize: 13
                                            font.bold: true
                                        }
                                        Label {
                                            text: (backend && !backend.overallSecurityOk) ? ("● System: " + backend.systemIntegrity) : "● Shield: Protected"
                                            color: (backend && !backend.overallSecurityOk) ? root.statusRed : root.statusGreen
                                            font.pixelSize: 13
                                            font.bold: true
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                ActionButton {
                                    labelText: "Device specs"
                                    onTriggered: root.currentPage = 1
                                }
                            }
                        }

                        // Quick Settings Grid
                        Label {
                            text: "Quick settings"
                            color: root.textMain
                            font.pixelSize: 16
                            font.bold: true
                        }

                        SettingCard {
                            // Volume Quick Slider
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14

                                Kirigami.Icon {
                                    source: backend && backend.muted ? "audio-volume-muted" : "audio-volume-high"
                                    width: 22; height: 22
                                }
                                Label {
                                    text: "Sound Volume"
                                    color: root.textMain
                                    font.pixelSize: 14
                                    Layout.preferredWidth: 140
                                }
                                WinSlider {
                                    Layout.fillWidth: true
                                    from: 0; to: 100
                                    value: backend ? backend.volume : 70
                                    onMoved: backend.setVolume(Math.round(value))
                                }
                                Label {
                                    text: (backend ? backend.volume : 70) + "%"
                                    color: root.textMuted
                                    font.pixelSize: 13
                                    Layout.preferredWidth: 42
                                    horizontalAlignment: Text.AlignRight
                                }
                                ActionButton {
                                    labelText: backend && backend.muted ? "Unmute" : "Mute"
                                    onTriggered: backend.toggleMute()
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            // Quick Toggles Row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 24

                                RowLayout {
                                    spacing: 10
                                    Label { text: "Wi-Fi"; color: root.textMain; font.pixelSize: 14 }
                                    WinSwitch {
                                        checkedState: backend ? backend.wifiEnabled : true
                                        onToggled: function(val) { backend.setWifiEnabled(val) }
                                    }
                                }

                                RowLayout {
                                    spacing: 10
                                    Label { text: "Bluetooth"; color: root.textMain; font.pixelSize: 14 }
                                    WinSwitch {
                                        checkedState: backend ? backend.bluetoothEnabled : false
                                        onToggled: function(val) { backend.setBluetoothEnabled(val) }
                                    }
                                }

                                RowLayout {
                                    spacing: 10
                                    Label { text: "Night Light"; color: root.textMain; font.pixelSize: 14 }
                                    WinSwitch {
                                        checkedState: backend ? backend.nightLightEnabled : false
                                        onToggled: function(val) { backend.setNightLight(val, backend.nightLightTemp) }
                                    }
                                }

                                RowLayout {
                                    spacing: 10
                                    Label { text: "Glass Blur"; color: root.textMain; font.pixelSize: 14 }
                                    WinSwitch {
                                        checkedState: backend ? backend.blurEnabled : true
                                        onToggled: function(val) { backend.setBlurEnabled(val) }
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }
                        }

                        // Recommended Shortcuts (Buttons Aligned Flush Right!)
                        Label {
                            text: "Recommended settings"
                            color: root.textMain
                            font.pixelSize: 16
                            font.bold: true
                        }

                        SettingCard {
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                Kirigami.Icon { source: "video-display"; width: 22; height: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Display resolution & scaling"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: backend ? (backend.displayName + " • " + backend.currentResolution + " (" + backend.displayScale + "%)") : ""; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton { labelText: "Configure"; onTriggered: root.currentPage = 1 }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                Kirigami.Icon { source: "network-wireless"; width: 22; height: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Wi-Fi & Network connections"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: backend ? ("IP: " + backend.ipAddress + " • " + backend.dnsStatus) : ""; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton { labelText: "Manage"; onTriggered: { root.currentPage = 3; backend.scanWifi() } }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                Kirigami.Icon { source: "preferences-desktop-wallpaper"; width: 22; height: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Personalize Sourceless Glass"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Switch curated dark wallpapers and window translucency"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton { labelText: "Personalize"; onTriggered: root.currentPage = 4 }
                            }
                        }

                        // System Resources Overview Card
                        SettingCard {
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 24

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: "System Storage"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                        Item { Layout.fillWidth: true }
                                        Label { text: backend ? (backend.diskUsedText + " / " + backend.diskTotalText + " (" + backend.diskFreeText + " free)") : ""; color: root.textMuted; font.pixelSize: 12 }
                                    }
                                    WinProgressBar {
                                        percentValue: backend ? backend.diskPercent : 20
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: "Memory (RAM)"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                        Item { Layout.fillWidth: true }
                                        Label { text: backend ? (backend.ramUsedText + " / " + backend.ramTotalText + " (" + backend.ramPercent + "%)") : ""; color: root.textMuted; font.pixelSize: 12 }
                                    }
                                    WinProgressBar {
                                        percentValue: backend ? backend.ramPercent : 30
                                    }
                                }
                            }
                        }

                        Item { height: 24 }
                    }
                }

                // -------------------------------------------------------------
                // PAGE 1: SYSTEM (Display Dropdowns, Sound, Power, Storage, About)
                // -------------------------------------------------------------
                ScrollView {
                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.width - 64
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 18

                        Item { height: 12 }

                        Label {
                            text: "System"
                            color: root.textMain
                            font.pixelSize: 28
                            font.bold: true
                        }

                        // DISPLAY SECTION (Now with Windows 11 Dropdown Lists!)
                        Label { text: "Display & Graphics"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            // Row 1: Display Resolution Dropdown
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                Kirigami.Icon { source: "video-display"; width: 22; height: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Display resolution"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: backend ? ("Active monitor: " + backend.displayName + " (" + backend.currentResolution + ")") : ""; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinComboBox {
                                    id: resCombo
                                    model: backend ? backend.availableResolutions : []
                                    currentIndex: {
                                        if (!backend || !backend.availableResolutions) return 0
                                        const idx = backend.availableResolutions.indexOf(backend.currentResolution)
                                        return idx >= 0 ? idx : 0
                                    }
                                    onActivated: function(index) {
                                        if (backend && backend.availableResolutions[index]) {
                                            backend.setResolution(backend.availableResolutions[index])
                                        }
                                    }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            // Row 2: Scale & Layout Dropdown
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                Kirigami.Icon { source: "preferences-desktop-display-randr"; width: 22; height: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Scale & Layout"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Change the size of text, apps, and other items"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinComboBox {
                                    id: scaleCombo
                                    readonly property var scaleValues: [100, 125, 150, 175, 200]
                                    model: ["100% (Recommended)", "125%", "150%", "175%", "200%"]
                                    currentIndex: {
                                        if (!backend) return 0
                                        const idx = scaleValues.indexOf(backend.displayScale)
                                        return idx >= 0 ? idx : 0
                                    }
                                    onActivated: function(index) {
                                        if (backend && scaleValues[index] !== undefined) {
                                            backend.setDisplayScale(scaleValues[index])
                                        }
                                    }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            // Row 3: Night Light
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                Kirigami.Icon { source: "redshift-status-on"; width: 22; height: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Night Light (Eye Comfort)"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Use warmer colors to help block blue light (" + (backend ? backend.nightLightTemp : 4500) + "K)"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinSlider {
                                    from: 2800; to: 6000; stepSize: 100
                                    value: backend ? backend.nightLightTemp : 4500
                                    Layout.preferredWidth: 180
                                    onMoved: backend.setNightLight(backend.nightLightEnabled, Math.round(value))
                                }
                                WinSwitch {
                                    checkedState: backend ? backend.nightLightEnabled : false
                                    onToggled: function(val) { backend.setNightLight(val, backend.nightLightTemp) }
                                }
                            }
                        }

                        // SOUND SECTION
                        Label { text: "Sound"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                Kirigami.Icon { source: "audio-speakers"; width: 22; height: 22 }
                                ColumnLayout {
                                    Layout.preferredWidth: 240
                                    spacing: 2
                                    Label { text: "Output Volume"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: backend ? backend.audioOutputName : "System Audio"; color: root.textMuted; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                                WinSlider {
                                    Layout.fillWidth: true
                                    from: 0; to: 100
                                    value: backend ? backend.volume : 70
                                    onMoved: backend.setVolume(Math.round(value))
                                }
                                Label { text: (backend ? backend.volume : 70) + "%"; color: root.textMain; Layout.preferredWidth: 42; horizontalAlignment: Text.AlignRight }
                                ActionButton { labelText: backend && backend.muted ? "Unmute" : "Mute"; onTriggered: backend.toggleMute() }
                                ActionButton { labelText: "Test"; primary: true; onTriggered: backend.testSound() }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                Kirigami.Icon { source: "audio-input-microphone"; width: 22; height: 22 }
                                ColumnLayout {
                                    Layout.preferredWidth: 240
                                    spacing: 2
                                    Label { text: "Microphone Sensitivity"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: backend && backend.micMuted ? "Microphone Muted" : "Input Active"; color: backend && backend.micMuted ? root.statusRed : root.textMuted; font.pixelSize: 12 }
                                }
                                WinSlider {
                                    Layout.fillWidth: true
                                    from: 0; to: 100
                                    value: backend ? backend.micVolume : 80
                                    onMoved: backend.setMicVolume(Math.round(value))
                                }
                                Label { text: (backend ? backend.micVolume : 80) + "%"; color: root.textMain; Layout.preferredWidth: 42; horizontalAlignment: Text.AlignRight }
                                ActionButton { labelText: backend && backend.micMuted ? "Unmute Mic" : "Mute Mic"; onTriggered: backend.toggleMicMute() }
                            }
                        }

                        // POWER & STORAGE SECTION
                        Label { text: "Power & Storage"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                Kirigami.Icon { source: "battery-full"; width: 22; height: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Power Mode & Energy"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: backend ? (backend.batteryState + " (" + backend.batteryPercent + "%)") : ""; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton {
                                    labelText: "Power Saver"
                                    primary: backend && backend.powerProfile === "power-saver"
                                    onTriggered: backend.setPowerProfile("power-saver")
                                }
                                ActionButton {
                                    labelText: "Balanced"
                                    primary: backend && backend.powerProfile === "balanced"
                                    onTriggered: backend.setPowerProfile("balanced")
                                }
                                ActionButton {
                                    labelText: "Performance"
                                    primary: backend && backend.powerProfile === "performance"
                                    onTriggered: backend.setPowerProfile("performance")
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                Kirigami.Icon { source: "drive-harddisk"; width: 22; height: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Storage Sense (" + (backend ? backend.diskUsedText : "") + " used of " + (backend ? backend.diskTotalText : "") + ")"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Free space available: " + (backend ? backend.diskFreeText : ""); color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton {
                                    labelText: "Clean Temp Cache"
                                    onTriggered: backend.clearUserCache()
                                }
                            }
                        }

                        // ABOUT DEVICE SPECIFICATIONS (Windows 11 About Card)
                        Label { text: "About this PC"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 24
                                rowSpacing: 10

                                Label { text: "Device Name (Hostname)"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? backend.hostname : ""; color: root.textMain; font.pixelSize: 13; font.bold: true }

                                Label { text: "Active User Account"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? (backend.userFullName + " (" + backend.userName + ")") : ""; color: root.textMain; font.pixelSize: 13; font.bold: true }

                                Label { text: "Processor (CPU)"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? (backend.cpuModel + " (" + backend.cpuCores + " threads)") : ""; color: root.textMain; font.pixelSize: 13 }

                                Label { text: "Graphics (GPU)"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? backend.gpuModel : ""; color: root.textMain; font.pixelSize: 13 }

                                Label { text: "Installed RAM"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? (backend.ramTotalText + " (" + backend.ramUsedText + " active)") : ""; color: root.textMain; font.pixelSize: 13 }

                                Label { text: "Operating System"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? (backend.osName + " (Immutable OSTree)") : ""; color: root.textMain; font.pixelSize: 13; font.bold: true }

                                Label { text: "Linux Kernel Version"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? backend.kernelVersion : ""; color: root.textMain; font.pixelSize: 13 }

                                Label { text: "System Uptime"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? backend.uptimeText : ""; color: root.textMain; font.pixelSize: 13 }

                                Label { text: "Enrolled Node HWID"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? backend.hwid : ""; color: root.brandHighlight; font.pixelSize: 13; font.bold: true }
                            }
                        }

                        Item { height: 24 }
                    }
                }

                // -------------------------------------------------------------
                // PAGE 2: BLUETOOTH & DEVICES (Bluetooth + Mouse & Touchpad)
                // -------------------------------------------------------------
                ScrollView {
                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.width - 64
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 18

                        Item { height: 12 }

                        Label {
                            text: "Bluetooth & devices"
                            color: root.textMain
                            font.pixelSize: 28
                            font.bold: true
                        }

                        SettingCard {
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                Kirigami.Icon { source: "preferences-system-bluetooth"; width: 24; height: 24 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Bluetooth"; color: root.textMain; font.pixelSize: 15; font.bold: true }
                                    Label { text: backend && backend.bluetoothEnabled ? "Discoverable as " + backend.hostname : "Bluetooth is turned off"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton {
                                    labelText: "Scan Devices"
                                    primary: true
                                    enabledBtn: backend ? backend.bluetoothEnabled : false
                                    onTriggered: backend.scanBluetooth()
                                }
                                WinSwitch {
                                    checkedState: backend ? backend.bluetoothEnabled : false
                                    onToggled: function(val) { backend.setBluetoothEnabled(val) }
                                }
                            }

                            Repeater {
                                model: backend ? backend.bluetoothDevices : []
                                delegate: ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: modelData.name; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                        Label { text: "(" + modelData.mac + ")"; color: root.textMuted; font.pixelSize: 12 }
                                        Item { Layout.fillWidth: true }
                                        Label {
                                            text: modelData.connected ? "Connected" : "Paired"
                                            color: modelData.connected ? root.statusGreen : root.textMuted
                                            font.pixelSize: 12
                                        }
                                        ActionButton {
                                            labelText: modelData.connected ? "Disconnect" : "Connect"
                                            primary: !modelData.connected
                                            onTriggered: backend.toggleBluetoothDevice(modelData.mac, !modelData.connected)
                                        }
                                    }
                                }
                            }
                        }

                        // MOUSE & TOUCHPAD SECTION
                        Label { text: "Mouse & Touchpad"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                Kirigami.Icon { source: "input-mouse"; width: 22; height: 22 }
                                ColumnLayout {
                                    Layout.preferredWidth: 220
                                    spacing: 2
                                    Label { text: "Cursor Speed"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Adjust pointer sensitivity"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                WinSlider {
                                    Layout.fillWidth: true
                                    from: 1; to: 10; stepSize: 1
                                    value: backend ? backend.mouseSpeed : 5
                                    onMoved: backend.setMouseSettings(Math.round(value), backend.naturalScroll, backend.tapToClick, backend.leftHandedMouse)
                                }
                                Label { text: (backend ? backend.mouseSpeed : 5) + " / 10"; color: root.textMain; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignRight }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Natural Scrolling"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Content tracks finger movement on touchpad"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinSwitch {
                                    checkedState: backend ? backend.naturalScroll : false
                                    onToggled: function(val) { backend.setMouseSettings(backend.mouseSpeed, val, backend.tapToClick, backend.leftHandedMouse) }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Tap to Click (Touchpad)"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Single-finger tap registers as left click"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinSwitch {
                                    checkedState: backend ? backend.tapToClick : true
                                    onToggled: function(val) { backend.setMouseSettings(backend.mouseSpeed, backend.naturalScroll, val, backend.leftHandedMouse) }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Left-Handed Mouse Mode"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Swap primary left and right mouse buttons"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinSwitch {
                                    checkedState: backend ? backend.leftHandedMouse : false
                                    onToggled: function(val) { backend.setMouseSettings(backend.mouseSpeed, backend.naturalScroll, backend.tapToClick, val) }
                                }
                            }
                        }

                        Item { height: 24 }
                    }
                }

                // -------------------------------------------------------------
                // PAGE 3: NETWORK & INTERNET
                // -------------------------------------------------------------
                ScrollView {
                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.width - 64
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 18

                        Item { height: 12 }

                        Label {
                            text: "Network & internet"
                            color: root.textMain
                            font.pixelSize: 28
                            font.bold: true
                        }

                        // Network Status Banner (Windows 11 Top Card)
                        SettingCard {
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 20

                                Kirigami.Icon {
                                    source: backend && backend.networkConnected ? "network-wireless-connected-100" : "network-offline"
                                    width: 36; height: 36
                                }

                                ColumnLayout {
                                    spacing: 4
                                    Label {
                                        text: backend && backend.networkConnected ? ("Connected to " + backend.activeNetworkName + " (" + backend.connectionType + ")") : "Not Connected"
                                        color: backend && backend.networkConnected ? root.statusGreen : root.statusRed
                                        font.pixelSize: 16
                                        font.bold: true
                                    }
                                    Label {
                                        text: backend ? ("IPv4 Address: " + backend.ipAddress + "   •   DNS: " + backend.dnsStatus) : ""
                                        color: root.textMuted
                                        font.pixelSize: 13
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                ActionButton {
                                    visible: backend ? backend.networkConnected : false
                                    labelText: "Disconnect"
                                    danger: true
                                    onTriggered: backend.disconnectNetwork()
                                }
                            }
                        }

                        // Wi-Fi Management Card
                        SettingCard {
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                Kirigami.Icon { source: "network-wireless"; width: 22; height: 22 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Wi-Fi"; color: root.textMain; font.pixelSize: 15; font.bold: true }
                                    Label { text: "Connect to available wireless networks"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton {
                                    labelText: "Scan Networks"
                                    primary: true
                                    enabledBtn: backend ? backend.wifiEnabled : false
                                    onTriggered: backend.scanWifi()
                                }
                                WinSwitch {
                                    checkedState: backend ? backend.wifiEnabled : true
                                    onToggled: function(val) { backend.setWifiEnabled(val) }
                                }
                            }

                            Repeater {
                                model: backend ? backend.wifiNetworks : []
                                delegate: ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 12

                                        Kirigami.Icon {
                                            source: "network-wireless"
                                            width: 18; height: 18
                                        }

                                        ColumnLayout {
                                            spacing: 1
                                            Label {
                                                text: modelData.ssid
                                                color: root.textMain
                                                font.pixelSize: 14
                                                font.bold: modelData.inUse
                                            }
                                            Label {
                                                text: "Signal: " + modelData.signal + "%  •  Security: " + modelData.security
                                                color: root.textMuted
                                                font.pixelSize: 12
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        Label {
                                            visible: modelData.inUse
                                            text: "Connected"
                                            color: root.statusGreen
                                            font.pixelSize: 13
                                            font.bold: true
                                        }

                                        ActionButton {
                                            visible: !modelData.inUse
                                            labelText: root.selectedWifiSsid === modelData.ssid ? "Cancel" : "Connect"
                                            primary: root.selectedWifiSsid !== modelData.ssid
                                            onTriggered: {
                                                if (modelData.security === "Open") {
                                                    backend.connectWifi(modelData.ssid, "")
                                                } else {
                                                    root.selectedWifiSsid = (root.selectedWifiSsid === modelData.ssid) ? "" : modelData.ssid
                                                }
                                            }
                                        }
                                    }

                                    // Inline Password Input Box when network is selected
                                    RowLayout {
                                        visible: root.selectedWifiSsid === modelData.ssid
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 34
                                            radius: 6
                                            color: root.bgInput
                                            border.color: root.brandHighlight
                                            border.width: 1

                                            TextField {
                                                id: wifiPassInput
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                placeholderText: "Enter Wi-Fi security key for " + modelData.ssid
                                                placeholderTextColor: root.textMuted
                                                echoMode: TextInput.Password
                                                color: root.textMain
                                                font.pixelSize: 13
                                                background: Item {}
                                            }
                                        }

                                        ActionButton {
                                            labelText: "Join Network"
                                            primary: true
                                            onTriggered: {
                                                backend.connectWifi(modelData.ssid, wifiPassInput.text)
                                                root.selectedWifiSsid = ""
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Item { height: 24 }
                    }
                }

                // -------------------------------------------------------------
                // PAGE 4: PERSONALIZATION (Wallpapers & Glass Effects)
                // -------------------------------------------------------------
                ScrollView {
                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.width - 64
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 18

                        Item { height: 12 }

                        Label {
                            text: "Personalization"
                            color: root.textMain
                            font.pixelSize: 28
                            font.bold: true
                        }

                        Label {
                            text: "Official Sourceless Wallpapers"
                            color: root.textMain
                            font.pixelSize: 16
                            font.bold: true
                        }

                        SettingCard {
                            Label {
                                text: "Choose an approved system background (custom third-party themes are disabled for security)"
                                color: root.textMuted
                                font.pixelSize: 13
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 14

                                Repeater {
                                    model: backend ? backend.wallpapers : []
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: 210
                                        height: 145
                                        radius: 10
                                        color: root.bgInput
                                        border.color: wpMouse.containsMouse ? root.brandHighlight : root.borderSubtle
                                        border.width: wpMouse.containsMouse ? 2 : 1
                                        clip: true

                                        ColumnLayout {
                                            anchors.fill: parent
                                            spacing: 0

                                            Image {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                source: modelData.previewUrl
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                sourceSize.width: 320
                                                sourceSize.height: 180
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 32
                                                color: Qt.rgba(0.06, 0.07, 0.11, 0.92)

                                                Label {
                                                    anchors.centerIn: parent
                                                    text: modelData.name
                                                    color: root.textMain
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: wpMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: backend.applyWallpaper(modelData.path)
                                        }
                                    }
                                }
                            }
                        }

                        Label { text: "Sourceless Glass Visual Effects"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Translucent Window Blur (Acrylic / Glass)"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Apply real-time KWin GPU frosted glass blur behind translucent surfaces"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinSwitch {
                                    checkedState: backend ? backend.blurEnabled : true
                                    onToggled: function(val) { backend.setBlurEnabled(val) }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Smooth Desktop Animations"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Enable window transitions and workspace animations"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinSwitch {
                                    checkedState: backend ? backend.animationsEnabled : true
                                    onToggled: function(val) { backend.setAnimationsEnabled(val) }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Reset Taskbar & Desktop Layout"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Restore the default Sourceless floating dock and start menu configuration"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton {
                                    labelText: "Restore Layout"
                                    onTriggered: backend.resetDesktopLayout()
                                }
                            }
                        }

                        Item { height: 24 }
                    }
                }

                // -------------------------------------------------------------
                // PAGE 5: APPS (Sandboxed Flatpak Applications)
                // -------------------------------------------------------------
                ScrollView {
                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.width - 64
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 18

                        Item { height: 12 }

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: "Apps"
                                color: root.textMain
                                font.pixelSize: 28
                                font.bold: true
                            }
                            Item { Layout.fillWidth: true }
                            ActionButton {
                                labelText: "Refresh List"
                                onTriggered: backend.refreshApps()
                            }
                            ActionButton {
                                labelText: "Check for Updates"
                                primary: true
                                onTriggered: backend.updateAllApps()
                            }
                        }

                        SettingCard {
                            Label {
                                text: "Installed Sandboxed Applications (" + (backend ? backend.installedApps.length : 0) + ")"
                                color: root.textMain
                                font.pixelSize: 15
                                font.bold: true
                            }
                            Label {
                                text: "All applications run inside isolated Flatpak containers. Core system apps are protected against removal."
                                color: root.textMuted
                                font.pixelSize: 12
                            }

                            Repeater {
                                model: backend ? backend.installedApps : []
                                delegate: ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 12

                                        Kirigami.Icon {
                                            source: "applications-other"
                                            width: 22; height: 22
                                        }

                                        ColumnLayout {
                                            spacing: 1
                                            Label {
                                                text: modelData.name
                                                color: root.textMain
                                                font.pixelSize: 14
                                                font.bold: true
                                            }
                                            Label {
                                                text: modelData.appId + "  •  v" + modelData.version + " (" + modelData.scope + ")"
                                                color: root.textMuted
                                                font.pixelSize: 12
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        ActionButton {
                                            labelText: "Open"
                                            onTriggered: backend.launchApp(modelData.appId)
                                        }

                                        ActionButton {
                                            labelText: modelData.protectedApp ? "System Core" : "Uninstall"
                                            danger: !modelData.protectedApp
                                            enabledBtn: !modelData.protectedApp
                                            onTriggered: backend.uninstallApp(modelData.appId)
                                        }
                                    }
                                }
                            }
                        }

                        Item { height: 24 }
                    }
                }

                // -------------------------------------------------------------
                // PAGE 6: TIME & LANGUAGE
                // -------------------------------------------------------------
                ScrollView {
                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.width - 64
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 18

                        Item { height: 12 }

                        Label {
                            text: "Time & language"
                            color: root.textMain
                            font.pixelSize: 28
                            font.bold: true
                        }

                        SettingCard {
                            RowLayout {
                                Layout.fillWidth: true
                                Kirigami.Icon { source: "preferences-system-time"; width: 28; height: 28 }
                                ColumnLayout {
                                    spacing: 2
                                    Label {
                                        text: backend ? backend.currentDateTime : ""
                                        color: root.textMain
                                        font.pixelSize: 18
                                        font.bold: true
                                    }
                                    Label {
                                        text: backend ? ("Time zone: " + backend.timezone + "  •  NTP Synchronization: " + (backend.ntpEnabled ? "Active" : "Manual")) : ""
                                        color: root.textMuted
                                        font.pixelSize: 13
                                    }
                                }
                                Item { Layout.fillWidth: true }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "24-hour clock format"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Display time using 24-hour military notation"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinSwitch {
                                    checkedState: backend ? backend.use24Hour : true
                                    onToggled: function(val) { backend.setUse24Hour(val) }
                                }
                            }
                        }

                        Label { text: "Keyboard Layout"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            Label {
                                text: "Active keyboard layout: " + (backend ? backend.keyboardLayout.toUpperCase() : "US")
                                color: root.textMain
                                font.pixelSize: 14
                                font.bold: true
                            }
                            Label {
                                text: "Select your preferred keyboard input layout (when dual layout is selected, switch with Alt+Shift)"
                                color: root.textMuted
                                font.pixelSize: 12
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 10

                                Repeater {
                                    model: [
                                        { code: "us", label: "English (US)" },
                                        { code: "ro", label: "Română (Standard)" },
                                        { code: "us,ro", label: "US + Română (Dual)" },
                                        { code: "gb", label: "English (UK)" },
                                        { code: "de", label: "Deutsch (DE)" },
                                        { code: "fr", label: "Français (FR)" },
                                        { code: "es", label: "Español (ES)" },
                                        { code: "it", label: "Italiano (IT)" }
                                    ]
                                    delegate: ActionButton {
                                        required property var modelData
                                        labelText: modelData.label
                                        primary: backend && backend.keyboardLayout === modelData.code
                                        onTriggered: backend.setKeyboardLayout(modelData.code)
                                    }
                                }
                            }
                        }

                        Item { height: 24 }
                    }
                }

                // -------------------------------------------------------------
                // PAGE 7: PRIVACY & SECURITY (Color-Coded Posture + Live Tools)
                // -------------------------------------------------------------
                ScrollView {
                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.width - 64
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 18

                        Item { height: 12 }

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: "Privacy & security"
                                color: root.textMain
                                font.pixelSize: 28
                                font.bold: true
                            }
                            Item { Layout.fillWidth: true }
                            ActionButton {
                                labelText: "Refresh Status"
                                onTriggered: backend.refreshSecurity()
                            }
                        }

                        // Top Security Posture Card (Turns RED when Modified / Negative!)
                        SettingCard {
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 16

                                Rectangle {
                                    readonly property bool secOk: backend ? backend.overallSecurityOk : true
                                    width: 56
                                    height: 56
                                    radius: 14
                                    color: secOk ? Qt.rgba(0.16, 0.76, 0.63, 0.18) : Qt.rgba(0.95, 0.33, 0.43, 0.20)
                                    border.color: secOk ? root.statusGreen : root.statusRed
                                    border.width: 1

                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        source: (backend && !backend.overallSecurityOk) ? "security-low" : "security-high"
                                        width: 30; height: 30
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Label {
                                        text: (backend && !backend.overallSecurityOk)
                                              ? ("Security Warning: System State Modified (" + backend.securityScore + "%)")
                                              : ("Sourceless Security Policy is Enforced (" + (backend ? backend.securityScore : 100) + "%)")
                                        color: (backend && !backend.overallSecurityOk) ? root.statusRed : root.statusGreen
                                        font.pixelSize: 17
                                        font.bold: true
                                    }
                                    Label {
                                        text: (backend && !backend.overallSecurityOk)
                                              ? "One or more security seals are unsealed (Sudo / Wheel privilege or Support Terminal active). Review red indicators below."
                                              : "All mandatory lockdown controls, read-only OSTree verification, and YARA malware shields are intact."
                                        color: root.textMuted
                                        font.pixelSize: 13
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            WinProgressBar {
                                percentValue: backend ? backend.securityScore : 100
                                barColor: (backend && !backend.overallSecurityOk) ? root.statusRed : root.statusGreen
                            }
                        }

                        // Active Protection Layers (Every Negative State is RED!)
                        Label { text: "Active Protection Layers (Real-Time Telemetry)"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 24
                                rowSpacing: 12

                                Label { text: "System Image & Tamper Seal"; color: root.textMuted; font.pixelSize: 13 }
                                Label {
                                    text: backend ? backend.systemIntegrity : ""
                                    color: (backend && backend.isTampered) ? root.statusRed : root.statusGreen
                                    font.pixelSize: 13; font.bold: true
                                }

                                Label { text: "Interactive Terminal Gate"; color: root.textMuted; font.pixelSize: 13 }
                                Label {
                                    text: (backend && backend.supportSessionActive) ? "UNSEALED (Support Shell Permitted)" : "Locked (Kiosk Policy Enforced)"
                                    color: (backend && backend.supportSessionActive) ? root.statusRed : root.statusGreen
                                    font.pixelSize: 13; font.bold: true
                                }

                                Label { text: "SELinux Access Control"; color: root.textMuted; font.pixelSize: 13 }
                                Label {
                                    text: backend ? backend.selinuxStatus : ""
                                    color: (backend && !backend.selinuxOk) ? root.statusRed : root.statusGreen
                                    font.pixelSize: 13; font.bold: true
                                }

                                Label { text: "Kernel Lockdown Mode"; color: root.textMuted; font.pixelSize: 13 }
                                Label {
                                    text: backend ? backend.lockdownMode : ""
                                    color: (backend && !backend.lockdownOk) ? root.statusRed : root.statusGreen
                                    font.pixelSize: 13; font.bold: true
                                }

                                Label { text: "Sourceless Real-Time YARA Shield"; color: root.textMuted; font.pixelSize: 13 }
                                Label {
                                    text: backend && backend.shieldActive ? "Active (Monitoring ~/Downloads & Autostart)" : "STOPPED (Unprotected)"
                                    color: backend && backend.shieldActive ? root.statusGreen : root.statusRed
                                    font.pixelSize: 13; font.bold: true
                                }

                                Label { text: "Telemetry & Remote Support Agent"; color: root.textMuted; font.pixelSize: 13 }
                                Label {
                                    text: backend && backend.clientActive ? "Connected (Enrolled HWID)" : "Offline / Disconnected"
                                    color: backend && backend.clientActive ? root.statusGreen : root.statusRed
                                    font.pixelSize: 13; font.bold: true
                                }

                                Label { text: "DNS-over-TLS & Malware Filtering"; color: root.textMuted; font.pixelSize: 13 }
                                Label {
                                    text: backend ? backend.dnsStatus : ""
                                    color: root.statusGreen
                                    font.pixelSize: 13; font.bold: true
                                }
                            }
                        }

                        // On-Demand YARA Threat Scanner Card
                        Label { text: "Endpoint Malware & Infostealer Scanner (YARA)"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                Kirigami.Icon { source: "security-medium"; width: 24; height: 24 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "On-Demand Downloads & Home Threat Scan"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label {
                                        text: backend ? backend.lastScanResult : ""
                                        color: (backend && backend.lastScanResult.startsWith("ALERT:")) ? root.statusRed : root.statusGreen
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton {
                                    labelText: "Scan Now"
                                    primary: true
                                    onTriggered: backend.runQuickSecurityScan()
                                }
                            }
                        }

                        // Active Security Events / Findings
                        Label { text: "Security Audit Findings"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            Repeater {
                                model: backend ? backend.securityEvents : []
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Rectangle {
                                        width: 8; height: 8; radius: 4
                                        color: modelData.severity === "critical" ? root.statusRed : (modelData.severity === "warning" ? root.statusAmber : root.statusGreen)
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: modelData.title
                                        color: modelData.severity === "critical" ? root.statusRed : root.textMain
                                        font.pixelSize: 13
                                        font.bold: modelData.severity === "critical"
                                    }
                                }
                            }
                        }

                        // Authorized Technical Support
                        Label { text: "Authorized Technical Support"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                Kirigami.Icon { source: "utilities-terminal"; width: 24; height: 24 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Emergency Technician Terminal"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Requires today's cryptographic support authorization key. Unsealing triggers tamper telemetry."; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton {
                                    labelText: "Authorize Support Shell"
                                    onTriggered: backend.launchEmergencyTerminal()
                                }
                            }
                        }

                        Item { height: 24 }
                    }
                }
            }
        }

        // Continuous 4-Corner Rounded Border Overlay
        Rectangle {
            anchors.fill: parent
            radius: 18
            color: "transparent"
            border.color: root.borderSubtle
            border.width: 1
        }
    }
}
