import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root
    Layout.preferredWidth: 90
    Layout.preferredHeight: 90
    implicitWidth: 90
    implicitHeight: 90

    // Remove default panel frame container behind custom glass shape
    Plasmoid.backgroundHints: 0

    // Runner for desktop environment shell actions
    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
        }
        function exec(cmd) {
            connectSource(cmd)
        }
    }

    // Corner background SVG (right.svg provides bottom-left geometry)
    Image {
        id: bg
        anchors.fill: parent
        source: "/usr/share/sourceless/theme/right.svg"
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    // Centered branding icon
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

    // Click handler triggering the global Plasma application launcher
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            executable.exec("qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu")
        }
    }
}