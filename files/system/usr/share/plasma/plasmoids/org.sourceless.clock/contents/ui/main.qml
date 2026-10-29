import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.calendar as PlasmaCalendar

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: "NoBackground"

    function stripPanelBackground() {
        if (Plasmoid.containment) {
            Plasmoid.containment.backgroundHints = "NoBackground";
        }
    }

    Component.onCompleted: stripPanelBackground()

    Connections {
        target: Plasmoid
        function onContainmentChanged() {
            stripPanelBackground();
        }
    }

    // Compact Representation: Corner Glass Widget
    compactRepresentation: Item {
        id: compactRoot
        Layout.preferredWidth: 135
        Layout.preferredHeight: 135
        implicitWidth: 135
        implicitHeight: 135

        Image {
            id: bg
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.height
            source: "/usr/share/sourceless/theme/Left.svg"
            fillMode: Image.Stretch
            smooth: true
        }

        Timer {
            interval: 1000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                var d = new Date();
                timeLabel.text = Qt.formatTime(d, "hh:mm");
                dateLabel.text = Qt.formatDate(d, "dd.MM.yyyy");
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 12
            anchors.verticalCenterOffset: 12
            spacing: 2

            Text {
                id: timeLabel
                text: Qt.formatTime(new Date(), "hh:mm")
                color: "#ffffff"
                font.pixelSize: 15
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                id: dateLabel
                text: Qt.formatDate(new Date(), "dd.MM.yyyy")
                color: Qt.rgba(1, 1, 1, 0.75)
                font.pixelSize: 11
                Layout.alignment: Qt.AlignHCenter
            }
        }

        MouseArea {
            id: clickArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: {
                root.expanded = !root.expanded;
            }
        }
    }

    // Full Representation: Native Plasma Calendar Popup
    fullRepresentation: Item {
        Layout.preferredWidth: 340
        Layout.preferredHeight: 360
        implicitWidth: 340
        implicitHeight: 360

        PlasmaCalendar.MonthView {
            anchors.fill: parent
            anchors.margins: 8
        }
    }
}