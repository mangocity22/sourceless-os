/*
    SPDX-FileCopyrightText: 2026 Sourceless OS
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import Qt5Compat.GraphicalEffects

import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.components 1.0 as KirigamiComponents

Item {
    id: root

    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software
    readonly property color brandHighlight: "#6054F2"
    readonly property color brandHighlightHover: "#7368F7"
    readonly property color textMain: "#E8ECFF"
    readonly property color textMuted: "#9CA3C7"

    width: 1600
    height: 900

    property bool uiVisible: true
    property bool manualUserMode: (userModel.count === 0)
    property int currentUserIndex: (userModel.lastIndex >= 0 && userModel.lastIndex < userModel.count) ? userModel.lastIndex : 0
    property int currentSessionIndex: (sessionModel.lastIndex >= 0) ? sessionModel.lastIndex : 0
    property string errorText: ""
    property bool capsLockOn: false
    property bool showPassword: false
    property bool loggingIn: false

    LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    P5Support.DataSource {
        id: keystateSource
        engine: "keystate"
        connectedSources: ["Caps Lock"]
        onDataChanged: {
            if (data["Caps Lock"]) {
                root.capsLockOn = !!data["Caps Lock"]["Locked"];
            }
        }
        Component.onCompleted: {
            if (data["Caps Lock"]) {
                root.capsLockOn = !!data["Caps Lock"]["Locked"];
            }
        }
    }

    P5Support.DataSource {
        id: timeSource
        engine: "time"
        connectedSources: ["Local"]
        interval: 1000
    }

    function currentUserName() {
        if (root.manualUserMode) {
            return usernameField.text.trim();
        }
        if (userListView.currentItem) {
            return userListView.currentItem.userLogin;
        }
        return userModel.lastUser || "";
    }

    function currentUserDisplay() {
        if (userListView.currentItem) {
            return userListView.currentItem.userDisplay;
        }
        return userModel.lastUser || "User";
    }

    function currentUserIcon() {
        if (userListView.currentItem) {
            return userListView.currentItem.userAvatar;
        }
        return "";
    }

    function startLogin() {
        const user = root.currentUserName();
        if (!user || root.loggingIn) {
            return;
        }
        root.errorText = "";
        root.loggingIn = true;
        sddm.login(user, passwordField.text, root.currentSessionIndex);
    }

    function wakeUi() {
        root.uiVisible = true;
        idleTimer.restart();
    }

    Component.onCompleted: {
        Qt.callLater(() => {
            if (root.manualUserMode) {
                usernameField.forceActiveFocus();
            } else {
                passwordField.forceActiveFocus();
            }
        });
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.loggingIn = false;
            root.errorText = i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Login Failed");
            passwordField.selectAll();
            passwordField.forceActiveFocus();
            rejectShake.restart();
        }
        function onLoginSucceeded() {
            glassCardWrapper.opacity = 0;
            footerBar.opacity = 0;
        }
    }

    Timer {
        id: idleTimer
        interval: 60000
        running: root.uiVisible && passwordField.text.length === 0
        repeat: false
        onTriggered: {
            if (passwordField.text.length === 0) {
                root.showPassword = false;
                root.uiVisible = false;
            }
        }
    }

    // Background Wallpaper Layer
    Item {
        id: wallpaperLayer
        anchors.fill: parent

        Repeater {
            model: screenModel
            Item {
                x: geometry.x
                y: geometry.y
                width: geometry.width
                height: geometry.height

                Rectangle {
                    anchors.fill: parent
                    color: config.color || "#0B0D15"
                }

                Image {
                    anchors.fill: parent
                    visible: config.type === "image" && config.background !== ""
                    source: config.background || ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                }
            }
        }
    }

    // Liquid Glass Blur Layer
    FastBlur {
        id: wallpaperBlur
        anchors.fill: parent
        source: wallpaperLayer
        radius: root.uiVisible ? 44 : 0
        visible: !root.softwareRendering
        Behavior on radius { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
    }

    // Translucent Dark Glass Tint
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.uiVisible ? Qt.rgba(0.04, 0.05, 0.09, 0.56) : Qt.rgba(0.03, 0.04, 0.08, 0.22) }
            GradientStop { position: 1.0; color: root.uiVisible ? Qt.rgba(0.05, 0.06, 0.11, 0.70) : Qt.rgba(0.03, 0.04, 0.08, 0.34) }
        }
    }

    // Ambient Sourceless Glow
    Rectangle {
        width: 520
        height: 520
        radius: 260
        anchors.centerIn: glassCardWrapper
        opacity: root.uiVisible ? 0.22 : 0.0
        visible: !root.softwareRendering
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#6054F2" }
            GradientStop { position: 1.0; color: "transparent" }
        }
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPressed: root.wakeUi()
        onPositionChanged: root.wakeUi()
    }

    Keys.onPressed: event => {
        root.wakeUi();
        event.accepted = false;
    }

    // Minimalist Top Clock
    ColumnLayout {
        id: clockBlock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.max(48, parent.height * 0.10)
        spacing: 4

        readonly property var nowDate: (timeSource.data["Local"] && timeSource.data["Local"]["DateTime"])
            ? timeSource.data["Local"]["DateTime"]
            : new Date()

        QQC2.Label {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatTime(clockBlock.nowDate, "HH:mm")
            color: "#FFFFFF"
            font.pixelSize: 76
            font.weight: Font.Light
            font.letterSpacing: 2
        }

        QQC2.Label {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDate(clockBlock.nowDate, Qt.DefaultLocaleLongDate)
            color: Qt.rgba(0.91, 0.93, 1.0, 0.78)
            font.pixelSize: 16
            font.weight: Font.Normal
            font.letterSpacing: 0.5
        }
    }

    // Central Liquid Glass Login Card
    Item {
        id: glassCardWrapper
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 28
        width: Math.min(390, parent.width - 48)
        height: glassCard.implicitHeight
        opacity: root.uiVisible ? 1.0 : 0.0
        scale: root.uiVisible ? 1.0 : 0.96

        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        SequentialAnimation {
            id: rejectShake
            NumberAnimation { target: glassCardWrapper; property: "anchors.horizontalCenterOffset"; to: -12; duration: 55; easing.type: Easing.OutQuad }
            NumberAnimation { target: glassCardWrapper; property: "anchors.horizontalCenterOffset"; to: 12; duration: 70; easing.type: Easing.InOutQuad }
            NumberAnimation { target: glassCardWrapper; property: "anchors.horizontalCenterOffset"; to: -8; duration: 60; easing.type: Easing.InOutQuad }
            NumberAnimation { target: glassCardWrapper; property: "anchors.horizontalCenterOffset"; to: 6; duration: 55; easing.type: Easing.InOutQuad }
            NumberAnimation { target: glassCardWrapper; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50; easing.type: Easing.OutQuad }
        }

        DropShadow {
            anchors.fill: glassCard
            source: glassCard
            visible: !root.softwareRendering
            horizontalOffset: 0
            verticalOffset: 16
            radius: 36
            samples: 24
            color: Qt.rgba(0, 0, 0, 0.55)
        }

        Rectangle {
            id: glassCard
            width: parent.width
            implicitHeight: cardCol.implicitHeight + 56
            radius: 28
            color: Qt.rgba(0.08, 0.10, 0.16, 0.62)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.20)

            // Specular Liquid Glass top highlight
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 1
                height: parent.height * 0.45
                radius: 27
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Hidden ListView to track SDDM userModel cleanly
            ListView {
                id: userListView
                visible: false
                width: 1
                height: 1
                model: userModel
                currentIndex: root.currentUserIndex
                delegate: Item {
                    readonly property string userLogin: model.name || ""
                    readonly property string userDisplay: (model.realName && model.realName !== "") ? model.realName : (model.name || "")
                    readonly property string userAvatar: model.icon || ""
                }
            }

            ColumnLayout {
                id: cardCol
                anchors.fill: parent
                anchors.margins: 28
                spacing: 16

                // User Avatar + Switch Arrows (if multiple users)
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 14

                    QQC2.ToolButton {
                        visible: !root.manualUserMode && userModel.count > 1
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: {
                            root.currentUserIndex = (root.currentUserIndex - 1 + userModel.count) % userModel.count;
                            passwordField.forceActiveFocus();
                        }
                        contentItem: QQC2.Label {
                            text: "‹"
                            color: root.textMain
                            font.pixelSize: 20
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 16
                            color: parent.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                        }
                    }

                    Item {
                        width: 92
                        height: 92

                        Rectangle {
                            anchors.fill: parent
                            radius: 46
                            color: Qt.rgba(1, 1, 1, 0.06)
                            border.width: 1.5
                            border.color: Qt.rgba(1, 1, 1, 0.28)
                        }

                        KirigamiComponents.Avatar {
                            anchors.centerIn: parent
                            width: 82
                            height: 82
                            source: root.manualUserMode ? "" : root.currentUserIcon()
                            name: root.manualUserMode ? (usernameField.text || "User") : root.currentUserDisplay()
                        }
                    }

                    QQC2.ToolButton {
                        visible: !root.manualUserMode && userModel.count > 1
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: {
                            root.currentUserIndex = (root.currentUserIndex + 1) % userModel.count;
                            passwordField.forceActiveFocus();
                        }
                        contentItem: QQC2.Label {
                            text: "›"
                            color: root.textMain
                            font.pixelSize: 20
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 16
                            color: parent.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                        }
                    }
                }

                // Username Title & Subtitle
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    QQC2.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.manualUserMode ? "Sign In" : root.currentUserDisplay()
                        color: root.textMain
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "Sourceless OS"
                        color: root.textMuted
                        font.pixelSize: 12
                        font.letterSpacing: 0.6
                    }
                }

                // Manual Username Pill (only in Other User mode)
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.manualUserMode
                    height: 46
                    radius: 23
                    color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1.2
                    border.color: usernameField.activeFocus ? root.brandHighlight : Qt.rgba(1, 1, 1, 0.18)

                    QQC2.TextField {
                        id: usernameField
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        placeholderText: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Username")
                        placeholderTextColor: Qt.rgba(0.91, 0.93, 1.0, 0.45)
                        color: "#FFFFFF"
                        font.pixelSize: 14
                        verticalAlignment: TextInput.AlignVCenter
                        background: Item {}
                        onAccepted: passwordField.forceActiveFocus()
                    }
                }

                // Liquid Glass Pill Password Field
                Rectangle {
                    id: inputPill
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    height: 46
                    radius: 23
                    color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1.2
                    border.color: passwordField.activeFocus
                        ? root.brandHighlight
                        : Qt.rgba(1, 1, 1, 0.18)

                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 6
                        spacing: 6

                        QQC2.TextField {
                            id: passwordField
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            placeholderText: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Password")
                            placeholderTextColor: Qt.rgba(0.91, 0.93, 1.0, 0.45)
                            color: "#FFFFFF"
                            font.pixelSize: 14
                            echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                            passwordCharacter: "•"
                            verticalAlignment: TextInput.AlignVCenter
                            background: Item {}
                            enabled: !root.loggingIn

                            onTextChanged: {
                                idleTimer.restart();
                                if (root.errorText !== "" && text.length > 0) {
                                    root.errorText = "";
                                }
                            }
                            onAccepted: root.startLogin()
                        }

                        QQC2.ToolButton {
                            visible: passwordField.text.length > 0
                            implicitWidth: 32
                            implicitHeight: 32
                            opacity: 0.75
                            onClicked: {
                                root.showPassword = !root.showPassword;
                                passwordField.forceActiveFocus();
                            }
                            contentItem: Kirigami.Icon {
                                source: root.showPassword ? "view-hidden" : "view-visible"
                                isMask: true
                                color: root.textMain
                            }
                            background: Rectangle {
                                radius: 16
                                color: parent.hovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                            }
                        }

                        Rectangle {
                            width: 34
                            height: 34
                            radius: 17
                            visible: passwordField.text.length > 0 || root.loggingIn
                            color: loginMouse.containsMouse ? root.brandHighlightHover : root.brandHighlight

                            Behavior on color { ColorAnimation { duration: 120 } }

                            QQC2.Label {
                                anchors.centerIn: parent
                                text: root.loggingIn ? "…" : "→"
                                color: "#FFFFFF"
                                font.pixelSize: 16
                                font.bold: true
                            }

                            MouseArea {
                                id: loginMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !root.loggingIn
                                onClicked: root.startLogin()
                            }
                        }
                    }
                }

                // Error / Caps Lock Pill
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.errorText !== "" || root.capsLockOn
                    implicitWidth: statusLbl.implicitWidth + 24
                    implicitHeight: 28
                    radius: 14
                    color: root.errorText !== ""
                        ? Qt.rgba(0.95, 0.33, 0.43, 0.18)
                        : Qt.rgba(0.96, 0.65, 0.14, 0.18)
                    border.width: 1
                    border.color: root.errorText !== ""
                        ? Qt.rgba(0.95, 0.33, 0.43, 0.45)
                        : Qt.rgba(0.96, 0.65, 0.14, 0.45)

                    QQC2.Label {
                        id: statusLbl
                        anchors.centerIn: parent
                        text: root.errorText !== ""
                            ? root.errorText
                            : i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Caps Lock is on")
                        color: root.errorText !== "" ? "#FF8FA3" : "#FFD175"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }

    // Minimalist Bottom Floating Glass Action Bar
    Rectangle {
        id: footerBar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
        implicitWidth: footerRow.implicitWidth + 24
        implicitHeight: 44
        radius: 22
        color: Qt.rgba(0.08, 0.10, 0.16, 0.55)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        opacity: root.uiVisible ? 1.0 : 0.0
        visible: opacity > 0.01

        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        RowLayout {
            id: footerRow
            anchors.centerIn: parent
            spacing: 8

            component GlassFooterBtn : QQC2.ToolButton {
                property string btnIcon: ""
                property string btnText: ""
                implicitWidth: btnLbl.implicitWidth + 34
                implicitHeight: 32

                contentItem: RowLayout {
                    spacing: 6
                    Kirigami.Icon {
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                        source: btnIcon
                        isMask: true
                        color: root.textMain
                    }
                    QQC2.Label {
                        id: btnLbl
                        text: btnText
                        color: root.textMain
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }

                background: Rectangle {
                    radius: 16
                    color: parent.hovered ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
            }

            GlassFooterBtn {
                btnIcon: "system-suspend"
                btnText: i18ndc("plasma_lookandfeel_org.kde.lookandfeel", "Suspend to RAM", "Sleep")
                visible: sddm.canSuspend
                onClicked: sddm.suspend()
            }

            GlassFooterBtn {
                btnIcon: "system-reboot"
                btnText: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Restart")
                visible: sddm.canReboot
                onClicked: sddm.reboot()
            }

            GlassFooterBtn {
                btnIcon: "system-shutdown"
                btnText: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Shut Down")
                visible: sddm.canPowerOff
                onClicked: sddm.powerOff()
            }

            GlassFooterBtn {
                btnIcon: "system-switch-user"
                btnText: root.manualUserMode
                    ? i18nd("plasma_lookandfeel_org.kde.lookandfeel", "List Users")
                    : i18ndc("plasma_lookandfeel_org.kde.lookandfeel", "For switching to a username and password prompt", "Other…")
                visible: userModel.count > 0
                onClicked: {
                    root.manualUserMode = !root.manualUserMode;
                    root.errorText = "";
                    Qt.callLater(() => {
                        if (root.manualUserMode) usernameField.forceActiveFocus();
                        else passwordField.forceActiveFocus();
                    });
                }
            }

            GlassFooterBtn {
                btnIcon: "input-keyboard"
                btnText: (keyboard.layouts && keyboard.layouts.length > 0 && keyboard.currentLayout >= 0)
                    ? keyboard.layouts[keyboard.currentLayout].shortName.toUpperCase()
                    : "KB"
                visible: keyboard.layouts && keyboard.layouts.length > 1
                onClicked: {
                    keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length;
                    passwordField.forceActiveFocus();
                }
            }

            GlassFooterBtn {
                id: sessionBtn
                btnIcon: "preferences-desktop-plasma"
                btnText: {
                    if (sessionList.currentItem) {
                        return sessionList.currentItem.sName;
                    }
                    return "Plasma";
                }
                visible: sessionModel.rowCount() > 1
                onClicked: {
                    root.currentSessionIndex = (root.currentSessionIndex + 1) % sessionModel.rowCount();
                    passwordField.forceActiveFocus();
                }

                ListView {
                    id: sessionList
                    visible: false
                    width: 1
                    height: 1
                    model: sessionModel
                    currentIndex: root.currentSessionIndex
                    delegate: Item {
                        readonly property string sName: model.name || "Plasma"
                    }
                }
            }
        }
    }
}
