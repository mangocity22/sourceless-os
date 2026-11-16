/*
    SPDX-FileCopyrightText: 2026 Sourceless OS
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import Qt5Compat.GraphicalEffects

import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.components 1.0 as KirigamiComponents
import org.kde.coreaddons 1.0 as KCoreAddons
import org.kde.plasma.private.sessions 2.0 as Sessions

Item {
    id: root

    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software
    readonly property color brandHighlight: "#6054F2"
    readonly property color brandHighlightHover: "#7368F7"
    readonly property color textMain: "#E8ECFF"
    readonly property color textMuted: "#9CA3C7"
    readonly property color statusAmber: "#F5A623"
    readonly property color statusRed: "#F2546D"

    property bool uiVisible: true
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
            authenticator.respond(passwordField.text);
        }
    }

    function wakeUi() {
        root.uiVisible = true;
        idleTimer.restart();
        passwordField.forceActiveFocus();
    }

    Component.onCompleted: {
        if (typeof authenticator !== "undefined" && authenticator && typeof authenticator.startAuthenticating === "function") {
            authenticator.startAuthenticating();
        }
        Qt.callLater(() => passwordField.forceActiveFocus());
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
            root.errorText = i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Unlocking failed");
            passwordField.selectAll();
            passwordField.forceActiveFocus();
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

    Timer {
        id: idleTimer
        interval: 45000
        running: root.uiVisible && passwordField.text.length === 0
        repeat: false
        onTriggered: {
            if (passwordField.text.length === 0) {
                root.showPassword = false;
                root.uiVisible = false;
            }
        }
    }

    // Subtle Liquid Glass backdrop tint & fallback gradient
    Rectangle {
        id: backdropLayer
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.uiVisible ? Qt.rgba(0.04, 0.05, 0.09, 0.56) : Qt.rgba(0.03, 0.04, 0.08, 0.25) }
            GradientStop { position: 1.0; color: root.uiVisible ? Qt.rgba(0.05, 0.06, 0.11, 0.68) : Qt.rgba(0.03, 0.04, 0.08, 0.35) }
        }
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.InOutQuad } }
    }

    // Ambient Sourceless glow behind the glass card
    Rectangle {
        width: 520
        height: 520
        radius: 260
        anchors.centerIn: glassCard
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

    // Central Liquid Glass Card
    Item {
        id: glassCardWrapper
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 28
        width: Math.min(380, parent.width - 48)
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

            ColumnLayout {
                id: cardCol
                anchors.fill: parent
                anchors.margins: 28
                spacing: 16

                // User Avatar with Liquid Glass Ring
                Item {
                    Layout.alignment: Qt.AlignHCenter
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
                        source: root.resolvedUserAvatar
                        name: root.resolvedUserName
                    }
                }

                // Username & OS Subtitle
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    QQC2.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.resolvedUserName
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
                            enabled: !root.authenticating
                            focus: true

                            onTextChanged: {
                                idleTimer.restart();
                                if (root.errorText !== "" && text.length > 0) {
                                    root.errorText = "";
                                }
                            }
                            onAccepted: root.submitPassword()
                        }

                        // Reveal password toggle
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

                        // Integrated Unlock Pill Button
                        Rectangle {
                            id: unlockBtn
                            width: 34
                            height: 34
                            radius: 17
                            visible: passwordField.text.length > 0 || root.authenticating
                            color: unlockMouse.containsMouse ? root.brandHighlightHover : root.brandHighlight

                            Behavior on color { ColorAnimation { duration: 120 } }

                            QQC2.Label {
                                anchors.centerIn: parent
                                text: root.authenticating ? "…" : "→"
                                color: "#FFFFFF"
                                font.pixelSize: 16
                                font.bold: true
                            }

                            MouseArea {
                                id: unlockMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !root.authenticating
                                onClicked: root.submitPassword()
                            }
                        }
                    }
                }

                // Status / Caps Lock / Error Pill
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.errorText !== "" || root.capsLockOn || root.infoText !== ""
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
                        text: {
                            if (root.errorText !== "") return root.errorText;
                            if (root.capsLockOn) return i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Caps Lock is on");
                            return root.infoText;
                        }
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
                onClicked: idleTimer.restart()

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
                visible: sessionManagement.canSuspend
                onClicked: sessionManagement.suspend()
            }

            GlassFooterBtn {
                btnIcon: "system-reboot"
                btnText: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Restart")
                visible: sessionManagement.canReboot
                onClicked: sessionManagement.reboot()
            }

            GlassFooterBtn {
                btnIcon: "system-shutdown"
                btnText: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Shut Down")
                visible: sessionManagement.canPowerOff
                onClicked: sessionManagement.powerOff()
            }

            GlassFooterBtn {
                btnIcon: "system-switch-user"
                btnText: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Switch User")
                visible: sessionManagement.canSwitchUser
                onClicked: sessionManagement.switchUser()
            }
        }
    }
}
