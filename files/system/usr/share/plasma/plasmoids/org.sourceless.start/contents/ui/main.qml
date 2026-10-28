import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    preferredRepresentation: PlasmoidItem.CompactRepresentation

    // Compact representation: Corner circle sector
    compactRepresentation: Item {
        id: compactRoot
        Layout.preferredWidth: 90
        Layout.preferredHeight: 90
        implicitWidth: 90
        implicitHeight: 90

        Image {
            id: bg
            anchors.fill: parent
            source: "/usr/share/sourceless/theme/Left.svg"
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        Kirigami.Icon {
            id: appIcon
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -8
            anchors.verticalCenterOffset: 8
            width: 32
            height: 32
            source: "sourceless-logo"

            scale: mouseArea.pressed ? 0.90 : (mouseArea.containsMouse ? 1.05 : 1.0)
            Behavior on scale { NumberAnimation { duration: 100 } }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.expanded = !root.expanded
            }
        }
    }

    // Temporary popup menu opened on click
    fullRepresentation: Item {
        Layout.preferredWidth: 380
        Layout.preferredHeight: 520
        implicitWidth: 380
        implicitHeight: 520

        Rectangle {
            anchors.fill: parent
            radius: 20
            color: Qt.rgba(0.04, 0.06, 0.10, 0.85)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.15)

            Text {
                anchors.centerIn: parent
                text: "Sourceless Application Menu"
                color: "#ffffff"
                font.pixelSize: 14
            }
        }
    }
}