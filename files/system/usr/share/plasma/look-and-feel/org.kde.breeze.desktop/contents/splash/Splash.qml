import QtQuick
import QtQuick.Layouts

Item {
    id: root
    width: 1920
    height: 1080

    // Numarul total de cadre din secventa (ajusteaza daca sunt 60)
    property int totalFrames: 30
    property int currentFrame: 0

    // Fundal negru complet Sourceless
    Rectangle {
        anchors.fill: parent
        color: "#0b0e14"
    }

    // Logo Sourceless Central (Static)
    Image {
        id: mainLogo
        anchors.centerIn: parent
        source: "images/logo.png"
        sourceSize.width: 160
        sourceSize.height: 160
        smooth: true
        fillMode: Image.PreserveAspectFit
    }

    // Cronometru pentru derularea cadrelor la ~30 FPS (33ms per cadru)
    Timer {
        interval: 33
        running: true
        repeat: true
        onTriggered: {
            root.currentFrame = (root.currentFrame + 1) % root.totalFrames
        }
    }

    // Animația de încărcare (Secvența PNG sub logo)
    Image {
        id: loaderSequence
        anchors.top: mainLogo.bottom
        anchors.topMargin: 40
        anchors.horizontalCenter: mainLogo.horizontalCenter
        sourceSize.width: 64
        sourceSize.height: 64
        smooth: true
        fillMode: Image.PreserveAspectFit

        // Formateaza numarul cadrului pe 2 cifre: frame_00.png, frame_01.png etc.
        source: "images/frame_" + (root.currentFrame < 10 ? "0" + root.currentFrame : root.currentFrame) + ".png"
    }

    // Elementul din dreapta jos (Plasma made by KDE) este complet omis/ascuns
    Item {
        visible: false
    }
}