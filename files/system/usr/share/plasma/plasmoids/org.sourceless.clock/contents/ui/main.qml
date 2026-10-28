import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root
    preferredRepresentation: PlasmoidItem.CompactRepresentation

    // Compact representation rendered directly on the panel
    compactRepresentation: Item {
        id: compactRoot
        Layout.preferredWidth: 110
        Layout.preferredHeight: 90
        implicitWidth: 110
        implicitHeight: 90

        // Background SVG asset
        Image {
            id: bg
            anchors.fill: parent
            source: "/usr/share/sourceless/theme/right.svg"
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        // Timer updating time and date every second
        Timer {
            interval: 1000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                var d = new Date();
                timeText.text = Qt.formatTime(d, "hh:mm");
                dateText.text = Qt.formatDate(d, "dd.MM.yyyy");
            }
        }

        // Offset text layout centered inside the glass sector
        ColumnLayout {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 6
            anchors.verticalCenterOffset: 6
            spacing: 2

            Text {
                id: timeText
                text: Qt.formatTime(new Date(), "hh:mm")
                color: "#ffffff"
                font.pixelSize: 13
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                id: dateText
                text: Qt.formatDate(new Date(), "dd.MM.yyyy")
                color: Qt.rgba(1, 1, 1, 0.65)
                font.pixelSize: 10
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}