import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ApplicationWindow {
    id: root
    width: 1100
    height: 750
    visible: true
    title: "Sourceless Control Center"
    
    // Fereastra principală este transparentă pentru Liquid Glass nativ
    color: "transparent"

    // Setăm culoarea cerută de echipă pentru accent
    readonly property color brandHighlight: "#6054F2"
    readonly property color textMain: "#e0e5ff"
    readonly property color textMuted: "#8e95b3"

    // Background-ul vizibil cu efect de sticlă
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.08, 0.09, 0.13, 0.75) // #141820 la 75% opacitate
        radius: 12
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // SIDEBAR
        Rectangle {
            Layout.preferredWidth: 260
            Layout.fillHeight: true
            color: Qt.rgba(0.05, 0.06, 0.09, 0.45)
            
            // Fără bordură în dreapta pentru a curge fin, sau o linie subtilă
            Rectangle {
                width: 1
                height: parent.height
                anchors.right: parent.right
                color: Qt.rgba(1, 1, 1, 0.05)
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 10

                Label {
                    text: "Dumitru\n@sourceless"
                    color: root.textMain
                    font.pixelSize: 15
                    font.bold: true
                    Layout.bottomMargin: 20
                }

                // Buton Meniu - Home
                Rectangle {
                    Layout.fillWidth: true
                    height: 40
                    color: root.brandHighlight // Aplicăm albastrul echipei de design!
                    radius: 6
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 15
                        spacing: 10
                        
                        Kirigami.Icon {
                            source: "home"
                            width: 20; height: 20
                            color: "white"
                        }
                        Label {
                            text: "Home"
                            color: "white"
                            font.pixelSize: 14
                            font.bold: true
                        }
                    }
                }
                
                // Buton Meniu - System (Inactiv)
                Rectangle {
                    Layout.fillWidth: true
                    height: 40
                    color: "transparent"
                    radius: 6
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 15
                        spacing: 10
                        
                        Kirigami.Icon {
                            source: "computer"
                            width: 20; height: 20
                            color: root.textMuted
                        }
                        Label {
                            text: "System"
                            color: root.textMuted
                            font.pixelSize: 14
                        }
                    }
                }

                Item { Layout.fillHeight: true } // Împinge meniul în sus
            }
        }

        // ZONA PRINCIPALĂ (Paginile)
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: 0

            // Pagina Home
            Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 40
                    spacing: 20

                    Label {
                        text: "Home"
                        font.pixelSize: 28
                        font.bold: true
                        color: root.textMain
                    }

                    Label {
                        text: "Recommended Settings"
                        font.pixelSize: 18
                        font.bold: true
                        color: root.textMain
                    }

                    // Card de setări
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 180
                        color: Qt.rgba(0.14, 0.15, 0.21, 0.6)
                        radius: 12
                        border.color: Qt.rgba(1, 1, 1, 0.05)

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 5
                            
                            // Aici vom injecta modulele KCM nativ în următorul pas
                            Button {
                                text: "Display Configuration"
                                Layout.fillWidth: true
                                icon.name: "preferences-desktop-display-randr"
                                // Styling simplu QML Button pentru mock-up
                            }
                            Button {
                                text: "Wi-Fi & Networks"
                                Layout.fillWidth: true
                                icon.name: "network-wireless"
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}