import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root
    Layout.preferredWidth: 110
    Layout.preferredHeight: 90
    implicitWidth: 110
    implicitHeight: 90

    // Remove default panel background behind the glass SVG
    Plasmoid.backgroundHints: 0

    // Corner background SVG (Left.svg provides bottom-right geometry)
    Image {
        id: bg
        anchors.fill: parent
        source: "/usr/share/sourceless/theme/Left.svg"
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    // Ticker updating system time and date
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

    // Clock typography aligned inside the glass corner curve
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
            color: Qt.rgba(1, 1, 1, 0.70)
            font.pixelSize: 10
            Layout.alignment: Qt.AlignHCenter
        }
    }
}