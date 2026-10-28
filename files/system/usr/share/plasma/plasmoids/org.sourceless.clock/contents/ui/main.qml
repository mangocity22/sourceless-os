import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation
    Layout.fillWidth: true
    Layout.fillHeight: true

    fullRepresentation: Item {
        anchors.fill: parent

        // 1. Fundalul SVG trimis de colegă
        Image {
            anchors.fill: parent
            source: "/usr/share/sourceless/theme/right.svg"
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        // 2. Timer care actualizează ora la fiecare secundă
        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: {
                var d = new Date();
                timeText.text = Qt.formatTime(d, "hh:mm");
                dateText.text = Qt.formatDate(d, "dd.MM.yyyy");
            }
        }

        // 3. Afișarea textului decalat în interiorul sfertului de cerc
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