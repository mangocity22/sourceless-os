import QtQuick
import QtQuick.Layouts

Item {
    id: root
    // Se mulează automat pe rezoluția ecranului
    anchors.fill: parent

    // Configurare pentru cele 125 de cadre
    property int totalFrames: 125
    property int currentFrame: 0

    // Funcție pentru formatare pe 3 cifre (ex: frame_000.png -> frame_124.png)
    function getFrameName(index) {
        if (index < 10) return "00" + index;
        if (index < 100) return "0" + index;
        return "" + index;
    }

    // Fundal negru absolut
    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    // Logo Principal Static
    Image {
        id: mainLogo
        anchors.centerIn: parent
        width: 160
        height: 160
        sourceSize.width: 160
        sourceSize.height: 160
        source: "images/logo.png"
        smooth: true
        fillMode: Image.PreserveAspectFit
    }

    // Timer pentru animație (~30 FPS: 33ms per cadru)
    Timer {
        interval: 33
        running: true
        repeat: true
        onTriggered: {
            root.currentFrame = (root.currentFrame + 1) % root.totalFrames
        }
    }

    // Secvența de încărcare (cele 125 de cadre)
    Image {
        id: loaderSequence
        anchors.top: mainLogo.bottom
        anchors.topMargin: 40
        anchors.horizontalCenter: mainLogo.horizontalCenter
        width: 64
        height: 64
        sourceSize.width: 64
        sourceSize.height: 64
        smooth: true
        fillMode: Image.PreserveAspectFit

        source: "images/frame_" + root.getFrameName(root.currentFrame) + ".png"
    }
}