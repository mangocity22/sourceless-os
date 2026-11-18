import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.workspace.calendar as PlasmaCalendar

PlasmoidItem {
    id: root

    // Use native Plasma 6 NoBackground hint without mutating containment properties
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // Compact taskbar representation (time and date stacked vertically)
    compactRepresentation: Item {
        id: compactRoot
        Layout.minimumWidth: timeColumn.implicitWidth + 24
        Layout.preferredWidth: timeColumn.implicitWidth + 24
        Layout.fillHeight: true

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
            id: timeColumn
            anchors.centerIn: parent
            spacing: 1

            Text {
                id: timeLabel
                text: Qt.formatTime(new Date(), "hh:mm")
                color: "#ffffff"
                font.pixelSize: 14
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                id: dateLabel
                text: Qt.formatDate(new Date(), "dd.MM.yyyy")
                color: Qt.rgba(1, 1, 1, 0.78)
                font.pixelSize: 11
                Layout.alignment: Qt.AlignHCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
        }
    }

    // Popup calendar representation
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
