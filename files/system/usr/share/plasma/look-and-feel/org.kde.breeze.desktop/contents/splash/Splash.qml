import QtQuick
import QtQuick.Layouts

Item {
    id: root
    anchors.fill: parent

    // Configurare pentru cele 125 de cadre (000 - 124)
    property int totalFrames: 125
    property int currentFrame: 0

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

    // Logo Principal Static - decalat cu 50px mai sus de centrul ecranului
    Image {
        id: mainLogo
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -50
        width: 160
        height: 160
        sourceSize.width: 160
        sourceSize.height: 160
        source: "images/logo.png"
        smooth: true
        fillMode: Image.PreserveAspectFit
    }

    // Timer animatie (~30 FPS: 33ms per cadru)
    Timer {
        interval: 33
        running: true
        repeat: true
        onTriggered: {
            root.currentFrame = (root.currentFrame + 1) % root.totalFrames
        }
    }

    // Rotița de încărcare redusă la 40x40 px
    Image {
        id: loaderSequence
        anchors.top: mainLogo.bottom
        anchors.topMargin: 40
        anchors.horizontalCenter: mainLogo.horizontalCenter
        width: 36
        height: 36
        sourceSize.width: 36
        sourceSize.height: 36
        smooth: true
        fillMode: Image.PreserveAspectFit

        source: "images/frame_" + root.getFrameName(root.currentFrame) + ".png"
    }
}