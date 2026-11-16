/*
    SPDX-FileCopyrightText: 2026 Sourceless OS
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.kirigamiaddons.components 1.0 as KirigamiComponents
import org.kde.coreaddons 1.0 as KCoreAddons
import org.kde.plasma.private.sessions 2.0 as Sessions

Item {
    id: root

    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software
    readonly property color cyberLime: "#A7FF52"
    readonly property color cyberViolet: "#6054F2"
    readonly property color cyberVioletHover: "#7368F7"
    readonly property color bgObsidian: "#090B12"
    readonly property color textMain: "#E8ECFF"
    readonly property color textMuted: "#949BC0"

    property string errorText: ""
    property string infoText: ""
    property bool capsLockOn: false
    property bool showPassword: false
    property bool authenticating: false

    readonly property string resolvedUserName: {
        if (typeof kscreenlocker_userName !== "undefined" && kscreenlocker_userName !== "") {
            return kscreenlocker_userName;
        }
        return (kuser.fullName && kuser.fullName !== "") ? kuser.fullName : kuser.loginName;
    }

    readonly property string resolvedUserAvatar: {
        if (typeof kscreenlocker_userImage !== "undefined" && kscreenlocker_userImage !== "") {
            return kscreenlocker_userImage;
        }
        return kuser.faceIconUrl;
    }

    KCoreAddons.KUser {
        id: kuser
    }

    Sessions.SessionManagement {
        id: sessionManagement
    }

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

    function submitPassword() {
        if (root.authenticating) {
            return;
        }
        root.errorText = "";
        root.authenticating = true;
        if (typeof authenticator !== "undefined" && authenticator) {
            if (typeof authenticator.startAuthenticating === "function") {
                authenticator.startAuthenticating();
            }
            authenticator.respond(passwordInput.text);
        }
    }

    Component.onCompleted: {
        if (typeof authenticator !== "undefined" && authenticator && typeof authenticator.startAuthenticating === "function") {
            authenticator.startAuthenticating();
        }
        Qt.callLater(() => passwordInput.forceActiveFocus());
    }

    Connections {
        target: (typeof authenticator !== "undefined") ? authenticator : null
        ignoreUnknownSignals: true

        function onSucceeded() {
            root.authenticating = false;
            root.errorText = "";
        }

        function onFailed() {
            root.authenticating = false;
            root.errorText = "Authentication Failed — Check Credentials";
            passwordInput.selectAll();
            passwordInput.forceActiveFocus();
            rejectShake.restart();
        }

        function onErrorMessageChanged() {
            if (authenticator && authenticator.errorMessage) {
                root.authenticating = false;
                root.errorText = authenticator.errorMessage;
                rejectShake.restart();
            }
        }

        function onInfoMessageChanged() {
            if (authenticator) {
                root.infoText = authenticator.infoMessage || "";
            }
        }
    }

    // 1. Dark Obsidian Cyber Tint over Wallpaper
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.03, 0.04, 0.07, 0.72) }
            GradientStop { position: 0.5; color: Qt.rgba(0.04, 0.05, 0.09, 0.68) }
            GradientStop { position: 1.0; color: Qt.rgba(0.02, 0.03, 0.06, 0.84) }
        }
    }

    // Subtle Cyber Grid Pattern
    Canvas {
        anchors.fill: parent
        opacity: 0.045
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.strokeStyle = "#A7FF52";
            ctx.lineWidth = 1;
            var step = 64;
            for (var x = 0; x < width; x += step) {
                ctx.beginPath();
                ctx.moveTo(x, 0);
                ctx.lineTo(x, height);
                ctx.stroke();
            }
            for (var y = 0; y < height; y += step) {
                ctx.beginPath();
                ctx.moveTo(0, y);
                ctx.lineTo(width, y);
                ctx.stroke();
            }
        }
    }

    // 2. Top Cyber HUD Bar
    Rectangle {
        id: topHud
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 56
        color: Qt.rgba(0.04, 0.05, 0.09, 0.72)

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 28
            anchors.rightMargin: 28
            spacing: 12

            Image {
                source: "/usr/share/pixmaps/sourceless-logo.svg"
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                sourceSize: Qt.size(44, 44)
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            Text {
                text: "SOURCELESS OS"
                color: root.textMain
                font.pixelSize: 13
                font.bold: true
                font.letterSpacing: 1.8
            }

            Rectangle {
                width: 1
                height: 16
                color: Qt.rgba(1, 1, 1, 0.14)
            }

            Rectangle {
                width: 8
                height: 8
                radius: 4
                color: root.cyberLime
            }

            Text {
                text: "SESSION LOCKED // ENCRYPTED"
                color: root.textMuted
                font.pixelSize: 11
                font.letterSpacing: 1.2
            }

            Item { Layout.fillWidth: true }

            readonly property var nowDate: (timeSource.data["Local"] && timeSource.data["Local"]["DateTime"])
                ? timeSource.data["Local"]["DateTime"]
                : new Date()

            Text {
                text: Qt.formatDate(parent.nowDate, "ddd, dd MMM yyyy")
                color: root.textMuted
                font.pixelSize: 12
                font.letterSpacing: 0.6
            }

            Rectangle {
                width: 1
                height: 14
                color: Qt.rgba(1, 1, 1, 0.14)
            }

            Text {
                text: Qt.formatTime(parent.nowDate, "HH:mm:ss")
                color: root.textMain
                font.pixelSize: 14
                font.bold: true
                font.letterSpacing: 1.2
            }
        }
    }

    // 3. Central Cyber High-Tech Auth Card
    Item {
        id: authContainer
        anchors.centerIn: parent
        width: Math.min(420, parent.width - 48)
        height: cyberCard.implicitHeight

        SequentialAnimation {
            id: rejectShake
            NumberAnimation { target: authContainer; property: "anchors.horizontalCenterOffset"; to: -12; duration: 50; easing.type: Easing.OutQuad }
            NumberAnimation { target: authContainer; property: "anchors.horizontalCenterOffset"; to: 12; duration: 65; easing.type: Easing.InOutQuad }
            NumberAnimation { target: authContainer; property: "anchors.horizontalCenterOffset"; to: -8; duration: 55; easing.type: Easing.InOutQuad }
            NumberAnimation { target: authContainer; property: "anchors.horizontalCenterOffset"; to: 6; duration: 50; easing.type: Easing.InOutQuad }
            NumberAnimation { target: authContainer; property: "anchors.horizontalCenterOffset"; to: 0; duration: 45; easing.type: Easing.OutQuad }
        }

        DropShadow {
            anchors.fill: cyberCard
            source: cyberCard
            visible: !root.softwareRendering
            horizontalOffset: 0
            verticalOffset: 18
            radius: 40
            samples: 24
            color: Qt.rgba(0, 0, 0, 0.72)
        }

        Rectangle {
            id: cyberCard
            width: parent.width
            implicitHeight: cardCol.implicitHeight + 56
            radius: 16
            border.width: 1
            border.color: Qt.rgba(0.38, 0.33, 0.95, 0.42)
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.11, 0.13, 0.21, 0.88) }
                GradientStop { position: 1.0; color: Qt.rgba(0.05, 0.07, 0.12, 0.94) }
            }

            // Top SourceLess NCH Cyber Gradient Accent Line (#A7FF52 -> #6054F2)
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                height: 2
                radius: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.cyberLime }
                    GradientStop { position: 0.55; color: root.cyberViolet }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            ColumnLayout {
                id: cardCol
                anchors.fill: parent
                anchors.margins: 28
                spacing: 18

                // User Avatar + Cyber Gradient Ring
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    width: 88
                    height: 88

                    Rectangle {
                        anchors.fill: parent
                        radius: 44
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: root.cyberLime }
                            GradientStop { position: 1.0; color: root.cyberViolet }
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 82
                        height: 82
                        radius: 41
                        color: root.bgObsidian
                    }

                    KirigamiComponents.Avatar {
                        anchors.centerIn: parent
                        width: 78
                        height: 78
                        source: root.resolvedUserAvatar
                        name: root.resolvedUserName
                    }
                }

                // Identity Header
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.resolvedUserName
                        color: root.textMain
                        font.pixelSize: 21
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "AUTHORIZATION REQUIRED"
                        color: root.cyberLime
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 1.8
                    }
                }

                // Password Input Box
                Rectangle {
                    Layout.fillWidth: true
                    height: 46
                    radius: 10
                    color: Qt.rgba(0.04, 0.05, 0.08, 0.90)
                    border.width: 1.5
                    border.color: passwordInput.activeFocus ? root.cyberViolet : Qt.rgba(1, 1, 1, 0.14)

                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 6
                        spacing: 6

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Enter password..."
                                color: Qt.rgba(0.58, 0.61, 0.75, 0.65)
                                font.pixelSize: 13
                                visible: passwordInput.text.length === 0
                            }

                            TextInput {
                                id: passwordInput
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                color: "#FFFFFF"
                                font.pixelSize: 13
                                echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                                passwordCharacter: "●"
                                clip: true
                                focus: true
                                enabled: !root.authenticating
                                selectionColor: root.cyberViolet

                                onTextChanged: {
                                    if (root.errorText !== "" && text.length > 0) {
                                        root.errorText = "";
                                    }
                                }
                                onAccepted: root.submitPassword()
                            }
                        }

                        // Eye Toggle
                        Rectangle {
                            visible: passwordInput.text.length > 0
                            width: 30
                            height: 30
                            radius: 7
                            color: eyeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"

                            Canvas {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                property bool activeState: root.showPassword
                                onActiveStateChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height);
                                    ctx.strokeStyle = root.showPassword ? "#A7FF52" : "#949BC0";
                                    ctx.lineWidth = 1.5;
                                    ctx.beginPath();
                                    ctx.moveTo(1, 8);
                                    ctx.quadraticCurveTo(8, 2, 15, 8);
                                    ctx.quadraticCurveTo(8, 14, 1, 8);
                                    ctx.stroke();
                                    ctx.beginPath();
                                    ctx.arc(8, 8, 2.3, 0, Math.PI * 2);
                                    ctx.stroke();
                                }
                            }

                            MouseArea {
                                id: eyeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.showPassword = !root.showPassword;
                                    passwordInput.forceActiveFocus();
                                }
                            }
                        }

                        // Cyber Unlock Button
                        Rectangle {
                            width: 76
                            height: 34
                            radius: 8
                            color: root.authenticating
                                ? Qt.rgba(0.38, 0.33, 0.95, 0.5)
                                : (loginMouse.containsMouse ? root.cyberVioletHover : root.cyberViolet)

                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: root.authenticating ? "..." : "UNLOCK"
                                color: "#FFFFFF"
                                font.pixelSize: 11
                                font.bold: true
                                font.letterSpacing: 0.9
                            }

                            MouseArea {
                                id: loginMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !root.authenticating
                                onClicked: root.submitPassword()
                            }
                        }
                    }
                }

                // Error / Caps Lock / Info Strip
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.errorText !== "" || root.capsLockOn || root.infoText !== ""
                    height: 32
                    radius: 8
                    color: root.errorText !== ""
                        ? Qt.rgba(0.95, 0.33, 0.43, 0.16)
                        : Qt.rgba(0.96, 0.65, 0.14, 0.16)
                    border.width: 1
                    border.color: root.errorText !== ""
                        ? Qt.rgba(0.95, 0.33, 0.43, 0.50)
                        : Qt.rgba(0.96, 0.65, 0.14, 0.50)

                    Text {
                        anchors.centerIn: parent
                        text: {
                            if (root.errorText !== "") return root.errorText;
                            if (root.capsLockOn) return "CAPS LOCK IS ACTIVE";
                            return root.infoText;
                        }
                        color: root.errorText !== "" ? "#FF8FA3" : "#FFD175"
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 0.6
                    }
                }
            }
        }
    }

    // 4. Bottom Cyber Action Dock
    Rectangle {
        id: bottomDock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        implicitWidth: dockRow.implicitWidth + 20
        height: 44
        radius: 12
        color: Qt.rgba(0.06, 0.08, 0.13, 0.84)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
        visible: dockRow.implicitWidth > 0

        component CyberDockBtn : Rectangle {
            id: btnRoot
            property string labelText: ""
            property string iconType: "power"
            signal triggered()

            implicitWidth: btnContent.implicitWidth + 22
            height: 32
            radius: 8
            color: btnMouse.containsMouse ? Qt.rgba(0.38, 0.33, 0.95, 0.28) : "transparent"
            border.width: btnMouse.containsMouse ? 1 : 0
            border.color: Qt.rgba(0.38, 0.33, 0.95, 0.65)

            RowLayout {
                id: btnContent
                anchors.centerIn: parent
                spacing: 7

                Canvas {
                    Layout.preferredWidth: 14
                    Layout.preferredHeight: 14
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.strokeStyle = "#A7FF52";
                        ctx.lineWidth = 1.6;
                        ctx.lineCap = "round";
                        if (btnRoot.iconType === "power") {
                            ctx.beginPath();
                            ctx.arc(7, 7.5, 4.5, -Math.PI * 0.25, Math.PI * 1.25, false);
                            ctx.stroke();
                            ctx.beginPath();
                            ctx.moveTo(7, 2);
                            ctx.lineTo(7, 6.5);
                            ctx.stroke();
                        } else if (btnRoot.iconType === "restart") {
                            ctx.beginPath();
                            ctx.arc(7, 7, 4.5, 0.3, Math.PI * 1.85, false);
                            ctx.stroke();
                            ctx.beginPath();
                            ctx.moveTo(10, 2.5);
                            ctx.lineTo(11.5, 5.2);
                            ctx.lineTo(8.5, 5.5);
                            ctx.stroke();
                        } else if (btnRoot.iconType === "sleep") {
                            ctx.beginPath();
                            ctx.arc(8, 7, 4.5, Math.PI * 0.35, Math.PI * 1.65, true);
                            ctx.stroke();
                        } else {
                            ctx.beginPath();
                            ctx.arc(7, 4.5, 2.3, 0, Math.PI * 2);
                            ctx.stroke();
                            ctx.beginPath();
                            ctx.arc(7, 12.5, 4.5, Math.PI * 1.15, Math.PI * 1.85, false);
                            ctx.stroke();
                        }
                    }
                }

                Text {
                    text: btnRoot.labelText
                    color: root.textMain
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
            }

            MouseArea {
                id: btnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: btnRoot.triggered()
            }
        }

        RowLayout {
            id: dockRow
            anchors.centerIn: parent
            spacing: 6

            CyberDockBtn {
                labelText: "Sleep"
                iconType: "sleep"
                visible: sessionManagement.canSuspend
                onTriggered: sessionManagement.suspend()
            }

            CyberDockBtn {
                labelText: "Restart"
                iconType: "restart"
                visible: sessionManagement.canReboot
                onTriggered: sessionManagement.reboot()
            }

            CyberDockBtn {
                labelText: "Shut Down"
                iconType: "power"
                visible: sessionManagement.canPowerOff
                onTriggered: sessionManagement.powerOff()
            }

            CyberDockBtn {
                labelText: "Switch User"
                iconType: "user"
                visible: sessionManagement.canSwitchUser
                onTriggered: sessionManagement.switchUser()
            }
        }
    }
}
