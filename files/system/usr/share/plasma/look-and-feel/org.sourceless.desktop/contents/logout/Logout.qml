/*
    SPDX-FileCopyrightText: 2026 Sourceless OS
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.coreaddons as KCoreAddons
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.private.sessions as Sessions

Item {
    id: root
    anchors.fill: parent
    focus: true

    // Context properties provided by Plasma's ksmserver-logout-greeter / plasma-shutdown
    // sdtype: 0 = ShutdownTypeNone (Logout), 1 = ShutdownTypeReboot, 2 = ShutdownTypeHalt
    property real timeout: 30
    property real remainingTime: (typeof automaticallyDoSeconds === "number" && automaticallyDoSeconds > 0) ? automaticallyDoSeconds : root.timeout
    property bool isVisible: true

    signal logoutRequested()
    signal haltRequested()
    signal rebootRequested()
    signal suspendRequested(int spdMethod)
    signal cancelRequested()
    signal lockScreenRequested()

    // SourceLess NCH Cyber Palette (matched to SDDM Main.qml & LockScreenUi.qml)
    readonly property color bgCard: Qt.rgba(0.035, 0.043, 0.071, 0.88)
    readonly property color bgInput: Qt.rgba(0.025, 0.032, 0.055, 0.90)
    readonly property color cyberLime: "#A7FF52"
    readonly property color cyberViolet: "#6054F2"
    readonly property color cyberVioletHover: "#7469FF"
    readonly property color cyberDanger: "#F4546D"
    readonly property color textMain: "#F3F5FF"
    readonly property color textMuted: "#949BC0"

    readonly property int currentSdType: (typeof sdtype !== "undefined") ? Number(sdtype) : 0
    readonly property bool allowShutdown: (typeof maysd !== "undefined") ? Boolean(maysd) : true
    readonly property bool showAllChoices: (typeof choose !== "undefined") ? Boolean(choose) : false

    KCoreAddons.KUser { id: kuser }
    Sessions.SessionManagement { id: sessionManagement }

    P5Support.DataSource {
        id: timeSource
        engine: "time"
        connectedSources: ["Local"]
        interval: 1000
    }

    function normalizeAvatarUrl(val) {
        if (!val) return "";
        var s = String(val).trim();
        if (!s) return "";
        if (s.indexOf("file://") === 0 || s.indexOf("http://") === 0 || s.indexOf("https://") === 0 || s.indexOf("qrc:/") === 0) {
            return s;
        }
        if (s.indexOf("/") === 0) {
            return "file://" + s;
        }
        return s;
    }

    readonly property string resolvedUserName: {
        if (kuser.fullName && kuser.fullName.length > 0) return kuser.fullName;
        if (kuser.loginName && kuser.loginName.length > 0) return kuser.loginName;
        return "sourceless";
    }

    readonly property string resolvedUserAvatar: {
        var u = normalizeAvatarUrl(kuser.faceIconUrl);
        if (u.length > 0) return u;
        if (kuser.loginName && kuser.loginName.length > 0) {
            return "file:///var/home/" + kuser.loginName + "/.face.icon";
        }
        return "file:///var/home/sourceless/.face.icon";
    }

    readonly property string actionTitle: {
        if (root.showAllChoices) return "POWER & SESSION CONTROL";
        if (root.currentSdType === 1) return "SYSTEM REBOOT // CONFIRMATION";
        if (root.currentSdType === 2) return "SYSTEM SHUTDOWN // CONFIRMATION";
        return "SESSION LOGOUT // CONFIRMATION";
    }

    readonly property string primaryButtonLabel: {
        if (root.currentSdType === 1) return "RESTART NOW";
        if (root.currentSdType === 2) return "SHUT DOWN NOW";
        return "LOG OUT NOW";
    }

    readonly property string countdownLabel: {
        var secs = Math.max(0, Math.ceil(root.remainingTime));
        if (root.currentSdType === 1) return "Restarting automatically in " + secs + "s";
        if (root.currentSdType === 2) return "Shutting down automatically in " + secs + "s";
        return "Logging out automatically in " + secs + "s";
    }

    function triggerPrimaryAction() {
        countdownTimer.stop();
        if (root.currentSdType === 1) {
            root.rebootRequested();
        } else if (root.currentSdType === 2) {
            root.haltRequested();
        } else {
            root.logoutRequested();
        }
    }

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            if (root.remainingTime <= 1) {
                root.remainingTime = 0;
                stop();
                root.triggerPrimaryAction();
            } else {
                root.remainingTime -= 1;
            }
        }
    }

    Keys.onEscapePressed: {
        countdownTimer.stop();
        root.cancelRequested();
    }
    Keys.onReturnPressed: root.triggerPrimaryAction()
    Keys.onEnterPressed: root.triggerPrimaryAction()

    // 1. Dark Obsidian Cyber Backdrop
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.03, 0.04, 0.07, 0.78) }
            GradientStop { position: 0.5; color: Qt.rgba(0.04, 0.05, 0.09, 0.74) }
            GradientStop { position: 1.0; color: Qt.rgba(0.02, 0.03, 0.06, 0.88) }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                countdownTimer.stop();
                root.cancelRequested();
            }
        }
    }

    // 2. Top Cyber HUD Bar
    Rectangle {
        id: topHud
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 44
        color: Qt.rgba(0.025, 0.03, 0.055, 0.85)
        border.color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 22
            anchors.rightMargin: 22

            RowLayout {
                spacing: 10
                Image {
                    source: "/usr/share/icons/hicolor/scalable/apps/sourceless-logo.svg"
                    width: 20
                    height: 20
                    sourceSize.width: 20
                    sourceSize.height: 20
                    fillMode: Image.PreserveAspectFit
                    onStatusChanged: {
                        if (status === Image.Error) {
                            source = "/usr/share/pixmaps/sourceless-logo.svg";
                        }
                    }
                }
                Text {
                    text: "SOURCELESS OS"
                    color: root.textMain
                    font.pixelSize: 12
                    font.bold: true
                    font.letterSpacing: 1.8
                }
                Rectangle {
                    width: 1; height: 14
                    color: Qt.rgba(1, 1, 1, 0.14)
                }
                Rectangle {
                    width: 7; height: 7; radius: 4
                    color: root.cyberLime
                }
                Text {
                    text: root.actionTitle
                    color: root.textMuted
                    font.pixelSize: 10
                    font.letterSpacing: 1.2
                }
            }

            Item { Layout.fillWidth: true }

            RowLayout {
                spacing: 12
                Text {
                    text: {
                        var dt = timeSource.data["Local"] ? timeSource.data["Local"]["DateTime"] : new Date();
                        return Qt.formatDateTime(dt, "ddd, dd MMM yyyy");
                    }
                    color: root.textMuted
                    font.pixelSize: 11
                    font.letterSpacing: 0.5
                }
                Rectangle {
                    width: 1; height: 14
                    color: Qt.rgba(1, 1, 1, 0.14)
                }
                Text {
                    text: {
                        var dt = timeSource.data["Local"] ? timeSource.data["Local"]["DateTime"] : new Date();
                        return Qt.formatDateTime(dt, "HH:mm:ss");
                    }
                    color: root.textMain
                    font.pixelSize: 13
                    font.bold: true
                    font.letterSpacing: 1.0
                }
            }
        }
    }

    // 3. Center Cyber Session / Power Card
    Item {
        id: cardWrapper
        width: 420
        height: cardCol.implicitHeight + 76
        anchors.centerIn: parent

        // Consume clicks inside card so backdrop MouseArea doesn't cancel
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        // Card Base
        Rectangle {
            id: cyberCard
            anchors.fill: parent
            radius: 16
            color: root.bgCard
            border.width: 0

            // Full Gradient Outline (#A7FF52 -> #6E62FF -> #6054F2)
            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    var r = 16;
                    var w = width;
                    var h = height;
                    var grad = ctx.createLinearGradient(0, 0, w, h);
                    grad.addColorStop(0.0, "#A7FF52");
                    grad.addColorStop(0.5, "#6E62FF");
                    grad.addColorStop(1.0, "#6054F2");
                    ctx.strokeStyle = grad;
                    ctx.lineWidth = 1.5;
                    ctx.beginPath();
                    ctx.moveTo(r, 1);
                    ctx.lineTo(w - r, 1);
                    ctx.quadraticCurveTo(w - 1, 1, w - 1, r);
                    ctx.lineTo(w - 1, h - r);
                    ctx.quadraticCurveTo(w - 1, h - 1, w - r, h - 1);
                    ctx.lineTo(r, h - 1);
                    ctx.quadraticCurveTo(1, h - 1, 1, h - r);
                    ctx.lineTo(1, r);
                    ctx.quadraticCurveTo(1, 1, r, 1);
                    ctx.closePath();
                    ctx.stroke();
                }
            }

            // Floating User Avatar (104x104, centered on top border)
            Item {
                id: avatarRing
                width: 104
                height: 104
                anchors.horizontalCenter: parent.horizontalCenter
                y: -52
                z: 10

                Rectangle {
                    anchors.fill: parent
                    radius: 52
                    color: "#090B12"
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 52
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: root.cyberLime }
                        GradientStop { position: 1.0; color: root.cyberViolet }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 98
                    height: 98
                    radius: 49
                    color: "#0B0E17"

                    Image {
                        id: avatarImg
                        anchors.fill: parent
                        anchors.margins: 2
                        source: root.resolvedUserAvatar
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false
                        onStatusChanged: {
                            if (status === Image.Error && String(source).indexOf(".face.icon") !== -1) {
                                source = "file:///var/home/" + (kuser.loginName || "sourceless") + "/.face";
                            }
                        }
                    }

                    Rectangle {
                        id: avatarMask
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 47
                        visible: false
                    }

                    MultiEffect {
                        anchors.fill: avatarImg
                        source: avatarImg
                        maskEnabled: true
                        maskSource: avatarMask
                        visible: avatarImg.status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: avatarImg.status !== Image.Ready
                        text: root.resolvedUserName.charAt(0).toUpperCase()
                        color: root.cyberLime
                        font.pixelSize: 32
                        font.bold: true
                    }
                }
            }

            ColumnLayout {
                id: cardCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 64
                anchors.leftMargin: 30
                anchors.rightMargin: 30
                spacing: 14

                // User Title & Status Subtitle
                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 4

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.resolvedUserName
                        color: root.textMain
                        font.pixelSize: 20
                        font.bold: true
                        font.letterSpacing: 0.4
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.actionTitle
                        color: root.cyberLime
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 1.6
                    }
                }

                // Primary Action + Cancel Row
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 10

                    // Primary Confirm Button
                    Rectangle {
                        Layout.fillWidth: true
                        height: 44
                        radius: 10
                        color: primaryMouse.containsMouse
                            ? (root.currentSdType === 2 ? "#FF667D" : root.cyberVioletHover)
                            : (root.currentSdType === 2 ? root.cyberDanger : root.cyberViolet)

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: root.primaryButtonLabel
                            color: "#FFFFFF"
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 1.0
                        }

                        MouseArea {
                            id: primaryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.triggerPrimaryAction()
                        }
                    }

                    // Cancel Button
                    Rectangle {
                        width: 112
                        height: 44
                        radius: 10
                        color: cancelMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : root.bgInput
                        border.color: cancelMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.14)
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "CANCEL"
                            color: root.textMain
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1.0
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                countdownTimer.stop();
                                root.cancelRequested();
                            }
                        }
                    }
                }

                // Countdown Indicator Strip
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.remainingTime > 0
                    height: 32
                    radius: 8
                    color: Qt.rgba(0.38, 0.33, 0.95, 0.14)
                    border.color: Qt.rgba(0.38, 0.33, 0.95, 0.45)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: root.countdownLabel
                        color: root.textMuted
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 0.4
                    }
                }
            }
        }
    }

    // 4. Bottom Cyber Power & Session Dock
    component CyberDockBtn: Rectangle {
        id: dockBtn
        property string labelText: ""
        property string iconType: ""
        signal triggered()

        width: rowContent.implicitWidth + 24
        height: 36
        radius: 9
        color: dockMouse.containsMouse ? Qt.rgba(0.65, 1.0, 0.32, 0.12) : "transparent"
        border.color: dockMouse.containsMouse ? Qt.rgba(0.65, 1.0, 0.32, 0.40) : "transparent"
        border.width: 1

        Behavior on color { ColorAnimation { duration: 120 } }

        RowLayout {
            id: rowContent
            anchors.centerIn: parent
            spacing: 8

            Canvas {
                width: 14
                height: 14
                property bool hovered: dockMouse.containsMouse
                onHoveredChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.strokeStyle = hovered ? "#A7FF52" : "#949BC0";
                    ctx.lineWidth = 1.6;
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";
                    if (dockBtn.iconType === "sleep") {
                        ctx.beginPath();
                        ctx.arc(8, 7, 5, 0.6, Math.PI * 1.85);
                        ctx.stroke();
                    } else if (dockBtn.iconType === "restart") {
                        ctx.beginPath();
                        ctx.arc(7, 7, 4.5, 0.5, Math.PI * 1.9);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.moveTo(10, 2);
                        ctx.lineTo(12, 4.5);
                        ctx.lineTo(9, 5.5);
                        ctx.stroke();
                    } else if (dockBtn.iconType === "power") {
                        ctx.beginPath();
                        ctx.arc(7, 8, 4.5, -0.9, Math.PI + 0.9);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.moveTo(7, 2);
                        ctx.lineTo(7, 7);
                        ctx.stroke();
                    } else if (dockBtn.iconType === "logout") {
                        ctx.beginPath();
                        ctx.moveTo(6, 2.5);
                        ctx.lineTo(2.5, 2.5);
                        ctx.lineTo(2.5, 11.5);
                        ctx.lineTo(6, 11.5);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.moveTo(5.5, 7);
                        ctx.lineTo(12, 7);
                        ctx.moveTo(9.5, 4.5);
                        ctx.lineTo(12, 7);
                        ctx.lineTo(9.5, 9.5);
                        ctx.stroke();
                    }
                }
            }

            Text {
                text: dockBtn.labelText
                color: dockMouse.containsMouse ? "#F3F5FF" : "#949BC0"
                font.pixelSize: 11
                font.bold: dockMouse.containsMouse
            }
        }

        MouseArea {
            id: dockMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: dockBtn.triggered()
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
        anchors.horizontalCenter: parent.horizontalCenter
        width: dockRow.implicitWidth + 24
        height: 48
        radius: 13
        color: Qt.rgba(0.035, 0.043, 0.071, 0.85)
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1

        RowLayout {
            id: dockRow
            anchors.centerIn: parent
            spacing: 6

            CyberDockBtn {
                labelText: "Sleep"
                iconType: "sleep"
                visible: Boolean(sessionManagement.canSuspend)
                onTriggered: {
                    countdownTimer.stop();
                    root.suspendRequested(1);
                }
            }

            CyberDockBtn {
                labelText: "Restart"
                iconType: "restart"
                visible: root.allowShutdown && Boolean(sessionManagement.canReboot)
                onTriggered: {
                    countdownTimer.stop();
                    root.rebootRequested();
                }
            }

            CyberDockBtn {
                labelText: "Shut Down"
                iconType: "power"
                visible: root.allowShutdown && Boolean(sessionManagement.canPowerOff)
                onTriggered: {
                    countdownTimer.stop();
                    root.haltRequested();
                }
            }

            CyberDockBtn {
                labelText: "Log Out"
                iconType: "logout"
                onTriggered: {
                    countdownTimer.stop();
                    root.logoutRequested();
                }
            }
        }
    }
}
