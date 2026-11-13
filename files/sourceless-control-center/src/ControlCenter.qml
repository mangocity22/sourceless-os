import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.coreaddons 1.0 as KCoreAddons
import org.kde.kirigamiaddons.components 1.0 as KirigamiComponents

ApplicationWindow {
    id: root
    width: 1160
    height: 780
    minimumWidth: 940
    minimumHeight: 640
    visible: true
    title: "Sourceless Control Center"
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"
    background: Item {}

    readonly property int windowRadius: (root.visibility === Window.Maximized || root.visibility === Window.FullScreen) ? 0 : 18

    KCoreAddons.KUser {
        id: kuser
    }

    // Sourceless Glass Design Tokens (Windows 11 Mica/Acrylic Dark Inspired)
    readonly property color brandHighlight: "#6054F2"
    readonly property color brandHighlightHover: "#7368F7"
    readonly property color bgWindow: "#11131E"
    readonly property color bgSidebar: "#0B0D15"
    readonly property color bgCard: Qt.rgba(0.14, 0.16, 0.23, 0.78)
    readonly property color bgCardHover: Qt.rgba(0.18, 0.20, 0.29, 0.88)
    readonly property color bgInput: Qt.rgba(0.09, 0.10, 0.15, 0.95)
    readonly property color borderSubtle: Qt.rgba(1, 1, 1, 0.10)
    readonly property color textMain: "#E8ECFF"
    readonly property color textMuted: "#949BC0"
    readonly property color statusGreen: "#2AC3A2"
    readonly property color statusAmber: "#F5A623"
    readonly property color statusRed: "#F2546D"

    property int currentPage: 0
    property string selectedWifiSsid: ""
    property string searchQuery: ""
    property var searchResults: []
    property int searchSelectedIndex: 0
    property string highlightedSection: ""
    property bool searchPopupOpen: false
    property bool searchPopupHovered: false

    readonly property var searchCatalog: [
        // Personalization (Page 4)
        { title: "Background & Wallpapers", subtitle: "Personalization • Wallpaper", pageIdx: 4, sectionKey: "wallpaper", iconName: "personalization",
          keywords: "background wallpaper desktop picture image photo backdrop personalize theme dark sourceless glass fundal imagine poza tapet tema" },
        { title: "Translucent Window Blur (Acrylic / Glass)", subtitle: "Personalization • Visual Effects", pageIdx: 4, sectionKey: "effects", iconName: "personalization",
          keywords: "blur glass acrylic mica translucency transparency frosted window effect kwin transparenta efecte sticla" },
        { title: "Smooth Desktop Animations", subtitle: "Personalization • Visual Effects", pageIdx: 4, sectionKey: "effects", iconName: "personalization",
          keywords: "animations transitions motion smooth workspace effects animatii tranzitii" },
        { title: "Reset Taskbar & Desktop Layout", subtitle: "Personalization • Visual Effects", pageIdx: 4, sectionKey: "effects", iconName: "personalization",
          keywords: "taskbar dock start menu panel layout reset restore default bara meniu" },

        // System (Page 1)
        { title: "Display Resolution", subtitle: "System • Display & Graphics", pageIdx: 1, sectionKey: "display", iconName: "display",
          keywords: "display resolution monitor screen graphics video pixels hz refresh ecran rezolutie monitor" },
        { title: "Scale & Layout (DPI)", subtitle: "System • Display & Graphics", pageIdx: 1, sectionKey: "display", iconName: "scale",
          keywords: "scale scaling layout dpi zoom size text ui interface font marime scalare" },
        { title: "Night Light (Eye Comfort)", subtitle: "System • Display & Graphics", pageIdx: 1, sectionKey: "display", iconName: "night-light",
          keywords: "night light eye comfort blue light warm color temperature kelvin sleep lumina nocturna ochi" },
        { title: "Sound & Output Volume", subtitle: "System • Sound", pageIdx: 1, sectionKey: "sound", iconName: "audio-speakers",
          keywords: "sound audio volume speaker headphones output mute unmute test sunet volum difuzor casti" },
        { title: "Microphone & Input Sensitivity", subtitle: "System • Sound", pageIdx: 1, sectionKey: "sound", iconName: "mic",
          keywords: "microphone mic input voice recording sensitivity mute microfon voce" },
        { title: "Power Mode & Battery", subtitle: "System • Power & Storage", pageIdx: 1, sectionKey: "power", iconName: "power",
          keywords: "power battery energy saver balanced performance charge ac adapter consum baterie energie performanta" },
        { title: "Storage Sense & Disk Cache", subtitle: "System • Power & Storage", pageIdx: 1, sectionKey: "power", iconName: "storage",
          keywords: "storage disk drive space free used ssd clean temp cache clear stocare spatiu disc memorie cache" },
        { title: "About this PC (Device Specs)", subtitle: "System • About", pageIdx: 1, sectionKey: "about", iconName: "system",
          keywords: "about pc device specs specifications hardware cpu processor gpu graphics ram memory os kernel uptime hostname hwid user account specificatii sistem procesor" },

        // Bluetooth & devices (Page 2)
        { title: "Bluetooth & Wireless Devices", subtitle: "Bluetooth & devices", pageIdx: 2, sectionKey: "bluetooth", iconName: "bluetooth",
          keywords: "bluetooth wireless pair connect disconnect devices headphones speaker mouse keyboard dispozitive" },
        { title: "Mouse & Cursor Speed", subtitle: "Bluetooth & devices • Mouse & Touchpad", pageIdx: 2, sectionKey: "mouse", iconName: "mouse",
          keywords: "mouse cursor pointer speed sensitivity left handed buttons swap viteza cursor" },
        { title: "Touchpad, Tap to Click & Natural Scrolling", subtitle: "Bluetooth & devices • Mouse & Touchpad", pageIdx: 2, sectionKey: "mouse", iconName: "mouse",
          keywords: "touchpad trackpad natural scrolling scroll tap click gesture" },

        // Network & internet (Page 3)
        { title: "Wi-Fi & Wireless Networks", subtitle: "Network & internet • Wi-Fi", pageIdx: 3, sectionKey: "wifi", iconName: "network",
          keywords: "wifi wi-fi wireless wlan network ssid password connect scan internet retea parola" },
        { title: "Network Status, Ethernet, IP & DNS", subtitle: "Network & internet • Connection", pageIdx: 3, sectionKey: "net-status", iconName: "network-connected",
          keywords: "network internet ethernet lan cable ipv4 ip address dns quad9 cloudflare dot connection status offline online" },

        // Apps (Page 5)
        { title: "Installed Apps & Updates (Flatpak)", subtitle: "Apps", pageIdx: 5, sectionKey: "apps", iconName: "apps",
          keywords: "apps applications programs software flatpak sandbox install uninstall remove update launch open aplicatii programe dezinstalare actualizari" },

        // Time & language (Page 6)
        { title: "Date, Time, Timezone & 24-Hour Clock", subtitle: "Time & language", pageIdx: 6, sectionKey: "datetime", iconName: "time",
          keywords: "time date clock 24 hour military timezone ntp sync calendar ceas ora data fus orar" },
        { title: "Keyboard Layout & Input Language", subtitle: "Time & language • Keyboard", pageIdx: 6, sectionKey: "keyboard", iconName: "time",
          keywords: "keyboard layout language input typing english romana romanian us uk de fr es it alt shift tastatura limba" },

        // Privacy & security (Page 7)
        { title: "Security Posture & Lockdown Status", subtitle: "Privacy & security", pageIdx: 7, sectionKey: "posture", iconName: "security-high",
          keywords: "security privacy policy posture score lockdown status seal intact modified warning securitate" },
        { title: "Active Protection Layers (OSTree, SELinux, Kernel)", subtitle: "Privacy & security • Telemetry", pageIdx: 7, sectionKey: "telemetry", iconName: "security-high",
          keywords: "protection layers telemetry ostree cosign immutable selinux enforcing kernel lockdown tamper seal" },
        { title: "YARA Malware & Infostealer Scanner", subtitle: "Privacy & security • Scanner", pageIdx: 7, sectionKey: "scanner", iconName: "security-scan",
          keywords: "yara malware virus threat scanner scan downloads autostart infostealer antivirus protectie scanare" },
        { title: "Security Audit Findings", subtitle: "Privacy & security • Audit", pageIdx: 7, sectionKey: "audit", iconName: "security-high",
          keywords: "audit findings events alerts logs warnings security" },
        { title: "Emergency Technician Support Terminal", subtitle: "Privacy & security • Support", pageIdx: 7, sectionKey: "support", iconName: "terminal",
          keywords: "support session technician emergency terminal shell console unlock key konsole suport tehnic" }
    ]

    Timer {
        id: highlightResetTimer
        interval: 2200
        onTriggered: root.highlightedSection = ""
    }

    function refreshPageData(pageIdx) {
        if (!backend) return
        if (pageIdx === 2) backend.refreshBluetooth()
        else if (pageIdx === 3) backend.refreshNetwork()
        else if (pageIdx === 5) backend.refreshApps()
        else if (pageIdx === 7) backend.refreshSecurity()
    }

    function scrollToSection(pageIdx, sectionKey) {
        if (!sectionKey) return
        const scrollViews = [homeScroll, systemScroll, btScroll, netScroll, personalizationScroll, appsScroll, timeScroll, securityScroll]
        const cardMap = {
            "display": cardDisplay,
            "sound": cardSound,
            "power": cardPower,
            "about": cardAbout,
            "bluetooth": cardBluetooth,
            "mouse": cardMouse,
            "net-status": cardNetStatus,
            "wifi": cardWifi,
            "wallpaper": cardWallpaper,
            "effects": cardEffects,
            "apps": cardApps,
            "datetime": cardDateTime,
            "keyboard": cardKeyboard,
            "posture": cardPosture,
            "telemetry": cardTelemetry,
            "scanner": cardScanner,
            "audit": cardAudit,
            "support": cardSupport
        }
        const sv = scrollViews[pageIdx]
        const card = cardMap[sectionKey]
        if (!sv || !card) return
        Qt.callLater(function() {
            if (!sv.contentItem) return
            const maxScroll = Math.max(0, sv.contentItem.contentHeight - sv.height)
            sv.contentItem.contentY = Math.max(0, Math.min(card.y - 24, maxScroll))
        })
    }

    function navigateToSearchResult(item, closeDropdown) {
        if (!item) return
        if (root.currentPage !== item.pageIdx) {
            root.currentPage = item.pageIdx
            root.refreshPageData(item.pageIdx)
        }
        root.highlightedSection = item.sectionKey || ""
        highlightResetTimer.restart()
        root.scrollToSection(item.pageIdx, item.sectionKey)
        if (closeDropdown) {
            root.searchPopupOpen = false
            searchField.focus = false
        }
    }

    function updateSearch(queryText) {
        const q = queryText.toLowerCase().trim()
        root.searchQuery = q
        if (q === "") {
            root.searchResults = []
            root.searchSelectedIndex = 0
            root.searchPopupOpen = false
            return
        }

        const tokens = q.split(/\s+/).filter(function(t) { return t.length > 0 })
        const matches = []

        for (let i = 0; i < root.searchCatalog.length; i++) {
            const item = root.searchCatalog[i]
            const titleLower = item.title.toLowerCase()
            const subLower = item.subtitle.toLowerCase()
            const haystack = titleLower + " " + subLower + " " + item.keywords

            let allMatch = true
            for (let t = 0; t < tokens.length; t++) {
                if (!haystack.includes(tokens[t])) {
                    allMatch = false
                    break
                }
            }
            if (!allMatch) continue

            let score = 1
            if (titleLower.startsWith(q)) score = 4
            else if (titleLower.includes(q)) score = 3
            else if (subLower.includes(q)) score = 2
            matches.push({ item: item, score: score, idx: i })
        }

        matches.sort(function(a, b) {
            if (b.score !== a.score) return b.score - a.score
            return a.idx - b.idx
        })

        root.searchResults = matches.slice(0, 6).map(function(m) { return m.item })
        root.searchSelectedIndex = 0
        root.searchPopupOpen = true

        if (root.searchResults.length > 0) {
            root.navigateToSearchResult(root.searchResults[0], false)
        }
    }

    Component.onCompleted: {
        const pageMap = {
            "home": 0,
            "system": 1,
            "bluetooth": 2,
            "network": 3,
            "personalization": 4,
            "apps": 5,
            "time": 6,
            "security": 7
        }
        if (backend && pageMap[backend.initialPage] !== undefined) {
            root.currentPage = pageMap[backend.initialPage]
        }
    }

    // 0. Sourceless NCH Cyber High-Tech SVG Icon Component
    component CyberIcon : Item {
        property string iconName: ""
        width: 22
        height: 22
        Layout.preferredWidth: width
        Layout.preferredHeight: height

        Image {
            anchors.fill: parent
            source: parent.iconName !== "" ? ("qrc:/icons/" + parent.iconName + ".svg") : ""
            sourceSize: Qt.size(64, 64)
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
    }

    // 1. Reusable Windows 11 Setting Card Component
    component SettingCard : Rectangle {
        default property alias cardContent: innerCol.data
        property string sectionKey: ""
        readonly property bool isHighlighted: sectionKey !== "" && root.highlightedSection === sectionKey
        Layout.fillWidth: true
        implicitHeight: innerCol.implicitHeight + 32
        color: isHighlighted ? root.bgCardHover : root.bgCard
        radius: 10
        border.color: isHighlighted ? root.brandHighlight : root.borderSubtle
        border.width: isHighlighted ? 2 : 1
        Behavior on border.color { ColorAnimation { duration: 180 } }

        ColumnLayout {
            id: innerCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12
        }
    }

    // 2. Reusable Action Button
    component ActionButton : Rectangle {
        id: btnRoot
        property string labelText: ""
        property bool primary: false
        property bool danger: false
        property bool enabledBtn: true
        signal triggered()

        implicitWidth: Math.max(110, btnLbl.implicitWidth + 28)
        implicitHeight: 34
        radius: 6
        opacity: enabledBtn ? 1.0 : 0.45
        color: {
            if (!enabledBtn) return Qt.rgba(0.2, 0.22, 0.3, 0.5)
            if (danger) return btnMouse.containsMouse ? "#FF647C" : root.statusRed
            if (primary) return btnMouse.containsMouse ? root.brandHighlightHover : root.brandHighlight
            return btnMouse.containsMouse ? Qt.rgba(0.24, 0.27, 0.38, 0.9) : Qt.rgba(0.19, 0.21, 0.30, 0.85)
        }
        border.color: (primary || danger) ? "transparent" : root.borderSubtle
        border.width: 1

        Label {
            id: btnLbl
            anchors.centerIn: parent
            text: btnRoot.labelText
            color: "#FFFFFF"
            font.pixelSize: 13
            font.bold: btnRoot.primary || btnRoot.danger
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btnRoot.enabledBtn ? Qt.PointingHandCursor : Qt.ForbiddenCursor
            onClicked: {
                if (btnRoot.enabledBtn) btnRoot.triggered()
            }
        }
    }

    // 3. Reusable Toggle Pill (Windows 11 Switch)
    component WinSwitch : Rectangle {
        id: switchRoot
        property bool checkedState: false
        signal toggled(bool newValue)

        width: 46
        height: 24
        radius: 12
        color: checkedState ? root.brandHighlight : Qt.rgba(0.25, 0.28, 0.38, 0.9)
        border.color: checkedState ? root.brandHighlightHover : Qt.rgba(1, 1, 1, 0.2)
        border.width: 1

        Rectangle {
            width: 16
            height: 16
            radius: 8
            anchors.verticalCenter: parent.verticalCenter
            x: switchRoot.checkedState ? switchRoot.width - width - 4 : 4
            color: "#FFFFFF"
            Behavior on x { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: switchRoot.toggled(!switchRoot.checkedState)
        }
    }

    // 4. Reusable Windows 11 Slider (Styled with #6054F2 Brand Highlight)
    component WinSlider : Slider {
        id: sliderControl
        implicitWidth: 200
        implicitHeight: 26

        background: Rectangle {
            x: sliderControl.leftPadding
            y: sliderControl.topPadding + sliderControl.availableHeight / 2 - height / 2
            implicitWidth: 200
            implicitHeight: 6
            width: sliderControl.availableWidth
            height: implicitHeight
            radius: 3
            color: Qt.rgba(0.22, 0.25, 0.35, 0.95)

            Rectangle {
                width: sliderControl.visualPosition * parent.width
                height: parent.height
                color: root.brandHighlight
                radius: 3
            }
        }

        handle: Rectangle {
            x: sliderControl.leftPadding + sliderControl.visualPosition * (sliderControl.availableWidth - width)
            y: sliderControl.topPadding + sliderControl.availableHeight / 2 - height / 2
            implicitWidth: 18
            implicitHeight: 18
            radius: 9
            color: sliderControl.pressed ? root.brandHighlightHover : root.brandHighlight
            border.color: "#FFFFFF"
            border.width: 3
        }
    }

    // 5. Reusable Windows 11 ProgressBar (Styled with #6054F2 or Custom Color)
    component WinProgressBar : Item {
        id: progRoot
        property real percentValue: 0
        property color barColor: root.brandHighlight
        Layout.fillWidth: true
        implicitHeight: 8

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: Qt.rgba(0.22, 0.25, 0.35, 0.95)

            Rectangle {
                width: Math.max(6, Math.min(1.0, progRoot.percentValue / 100.0) * parent.width)
                height: parent.height
                radius: 4
                color: progRoot.barColor
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }
        }
    }

    // 6. Reusable Windows 11 Dropdown List (ComboBox)
    component WinComboBox : ComboBox {
        id: comboControl
        implicitWidth: 210
        implicitHeight: 36

        delegate: ItemDelegate {
            id: itemDlgt
            required property var model
            required property int index
            width: comboControl.width
            height: 34
            highlighted: comboControl.highlightedIndex === index

            contentItem: Label {
                text: itemDlgt.model[comboControl.textRole] !== undefined ? itemDlgt.model[comboControl.textRole] : itemDlgt.modelData
                color: "#FFFFFF"
                font.pixelSize: 13
                font.bold: comboControl.currentIndex === itemDlgt.index
                verticalAlignment: Text.AlignVCenter
                leftPadding: 10
            }

            background: Rectangle {
                radius: 6
                color: itemDlgt.highlighted ? root.brandHighlight : (comboControl.currentIndex === itemDlgt.index ? Qt.rgba(0.38, 0.33, 0.95, 0.30) : "transparent")
            }
        }

        indicator: Canvas {
            id: canvas
            x: comboControl.width - width - 12
            y: comboControl.topPadding + (comboControl.availableHeight - height) / 2
            width: 10
            height: 6
            contextType: "2d"

            onPaint: {
                context.reset();
                context.moveTo(0, 0);
                context.lineTo(width, 0);
                context.lineTo(width / 2, height);
                context.closePath();
                context.fillStyle = "#E8ECFF";
                context.fill();
            }
        }

        contentItem: Label {
            leftPadding: 12
            rightPadding: comboControl.indicator.width + 18
            text: comboControl.displayText
            font.pixelSize: 13
            font.bold: true
            color: root.textMain
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            implicitWidth: 210
            implicitHeight: 36
            color: comboControl.down || comboControl.popup.visible ? Qt.rgba(0.18, 0.20, 0.29, 0.98) : root.bgInput
            border.color: comboControl.popup.visible || comboControl. hovered ? root.brandHighlight : root.borderSubtle
            border.width: 1
            radius: 6
        }

        popup: Popup {
            y: comboControl.height + 4
            width: comboControl.width
            implicitHeight: Math.min(280, contentItem.implicitHeight + 12)
            padding: 6

            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: comboControl.popup.visible ? comboControl.delegateModel : null
                currentIndex: comboControl.highlightedIndex
                ScrollIndicator.vertical: ScrollIndicator { }
            }

            background: Rectangle {
                color: Qt.rgba(0.09, 0.10, 0.15, 0.98)
                border.color: root.brandHighlight
                border.width: 1
                radius: 8
            }
        }
    }

    // Main Translucent Window Container
    Rectangle {
        anchors.fill: parent
        color: root.bgWindow
        radius: root.windowRadius
        clip: true

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // =================================================================
            // LEFT SIDEBAR (Windows 11 Navigation Pane)
            // =================================================================
            Item {
                id: sidebarItem
                Layout.preferredWidth: 280
                Layout.fillHeight: true
                clip: true

                // Rounded left corners (top-left & bottom-left = 18px) while keeping the right separator straight
                Rectangle {
                    x: 0
                    y: 0
                    width: parent.width + root.windowRadius
                    height: parent.height
                    radius: root.windowRadius
                    color: root.bgSidebar
                }

                Rectangle {
                    width: 1
                    height: parent.height
                    anchors.right: parent.right
                    color: root.borderSubtle
                }

                ColumnLayout {
                    id: sidebarCol
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    anchors.topMargin: 12
                    anchors.bottomMargin: 18
                    spacing: 10

                    // Integrated Window Title Row (Draggable)
                    Item {
                        Layout.fillWidth: true
                        height: 24

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            spacing: 8

                            CyberIcon {
                                iconName: "sourceless-control-center"
                                width: 18
                                height: 18
                            }

                            Label {
                                Layout.fillWidth: true
                                text: "Sourceless Control Center"
                                color: root.textMuted
                                font.pixelSize: 12
                                font.bold: true
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onPressed: root.startSystemMove()
                            onDoubleClicked: {
                                if (root.visibility === Window.Maximized) root.showNormal()
                                else root.showMaximized()
                            }
                        }
                    }

                    // 1. Dynamic User Profile Card with Real Profile Photo
                    Rectangle {
                        Layout.fillWidth: true
                        height: 68
                        radius: 10
                        color: profileMouse.containsMouse ? root.bgCardHover : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 12

                            // Real User Avatar (Matches Start Menu Dog Picture!)
                            Item {
                                width: 48
                                height: 48

                                KirigamiComponents.Avatar {
                                    id: sidebarAvatar
                                    anchors.fill: parent
                                    source: (backend && backend.userAvatar !== "") ? backend.userAvatar : kuser.faceIconUrl
                                    name: backend ? backend.userFullName : kuser.fullName
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    Layout.fillWidth: true
                                    text: (kuser.fullName && kuser.fullName !== "") ? kuser.fullName : (backend ? backend.userFullName : "User")
                                    color: root.textMain
                                    font.pixelSize: 15
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: backend ? (backend.userName + "@" + backend.hostname) : "@sourceless"
                                    color: root.textMuted
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: profileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentPage = 1 // Jump to System/About
                        }
                    }

                    // 2. Windows 11 Search Box
                    Rectangle {
                        id: searchBox
                        Layout.fillWidth: true
                        height: 36
                        radius: 8
                        color: root.bgInput
                        border.color: searchField.activeFocus ? root.brandHighlight : root.borderSubtle
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            spacing: 8

                            CyberIcon {
                                iconName: "search"
                                width: 16
                                height: 16
                            }

                            TextField {
                                id: searchField
                                Layout.fillWidth: true
                                placeholderText: "Find a setting..."
                                placeholderTextColor: root.textMuted
                                color: root.textMain
                                font.pixelSize: 13
                                background: Item {}
                                onTextChanged: root.updateSearch(text)
                                onActiveFocusChanged: {
                                    if (activeFocus && text.trim().length > 0) {
                                        root.searchPopupOpen = true
                                    } else if (!activeFocus && !root.searchPopupHovered) {
                                        root.searchPopupOpen = false
                                    }
                                }
                                Keys.onDownPressed: {
                                    if (root.searchResults.length > 0) {
                                        root.searchPopupOpen = true
                                        root.searchSelectedIndex = (root.searchSelectedIndex + 1) % root.searchResults.length
                                        root.navigateToSearchResult(root.searchResults[root.searchSelectedIndex], false)
                                    }
                                }
                                Keys.onUpPressed: {
                                    if (root.searchResults.length > 0) {
                                        root.searchPopupOpen = true
                                        root.searchSelectedIndex = (root.searchSelectedIndex - 1 + root.searchResults.length) % root.searchResults.length
                                        root.navigateToSearchResult(root.searchResults[root.searchSelectedIndex], false)
                                    }
                                }
                                Keys.onEscapePressed: {
                                    root.searchPopupOpen = false
                                    focus = false
                                }
                                onAccepted: {
                                    if (root.searchResults.length > 0) {
                                        const idx = Math.min(root.searchSelectedIndex, root.searchResults.length - 1)
                                        root.navigateToSearchResult(root.searchResults[idx], true)
                                    }
                                }
                            }

                            Rectangle {
                                visible: searchField.text.length > 0
                                width: 22
                                height: 22
                                radius: 11
                                color: clearSearchMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"

                                Label {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: root.textMuted
                                    font.pixelSize: 11
                                }

                                MouseArea {
                                    id: clearSearchMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        searchField.text = ""
                                        root.searchPopupOpen = false
                                        root.highlightedSection = ""
                                    }
                                }
                            }
                        }
                    }

                    // 3. Navigation Categories (Windows 11 Structure)
                    Repeater {
                        model: [
                            { title: "Home", iconName: "home", pageIdx: 0 },
                            { title: "System", iconName: "system", pageIdx: 1 },
                            { title: "Bluetooth & devices", iconName: "bluetooth", pageIdx: 2 },
                            { title: "Network & internet", iconName: "network", pageIdx: 3 },
                            { title: "Personalization", iconName: "personalization", pageIdx: 4 },
                            { title: "Apps", iconName: "apps", pageIdx: 5 },
                            { title: "Time & language", iconName: "time", pageIdx: 6 },
                            { title: "Privacy & security", iconName: "security-high", pageIdx: 7 }
                        ]

                        delegate: Rectangle {
                            id: navItem
                            required property var modelData
                            readonly property bool isSelected: root.currentPage === modelData.pageIdx

                            Layout.fillWidth: true
                            height: 40
                            radius: 8
                            color: isSelected ? Qt.rgba(0.38, 0.33, 0.95, 0.22) : (navMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")

                            // Windows 11 Left Accent Bar
                            Rectangle {
                                visible: navItem.isSelected
                                width: 4
                                height: 18
                                radius: 2
                                anchors.left: parent.left
                                anchors.leftMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.brandHighlight
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 12
                                spacing: 12

                                CyberIcon {
                                    iconName: navItem.modelData.iconName
                                    width: 22
                                    height: 22
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: navItem.modelData.title
                                    color: navItem.isSelected ? "#FFFFFF" : root.textMain
                                    font.pixelSize: 14
                                    font.bold: navItem.isSelected
                                }

                                // Red Warning Badge on Privacy & Security if system is Modified
                                Rectangle {
                                    visible: navItem.modelData.pageIdx === 7 && backend && !backend.overallSecurityOk
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: root.statusRed
                                }
                            }

                            MouseArea {
                                id: navMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.currentPage = navItem.modelData.pageIdx
                                    root.refreshPageData(navItem.modelData.pageIdx)
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Footer Status Pill (Turns RED if Modified/Negative, GREEN if Intact)
                    Rectangle {
                        readonly property bool secOk: backend ? backend.overallSecurityOk : true
                        Layout.fillWidth: true
                        height: 38
                        radius: 8
                        color: secOk ? Qt.rgba(0.16, 0.76, 0.63, 0.12) : Qt.rgba(0.95, 0.33, 0.43, 0.16)
                        border.color: secOk ? Qt.rgba(0.16, 0.76, 0.63, 0.35) : Qt.rgba(0.95, 0.33, 0.43, 0.45)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: (backend && !backend.overallSecurityOk) ? root.statusRed : root.statusGreen
                            }

                            Label {
                                Layout.fillWidth: true
                                text: {
                                    if (backend && backend.statusMessage !== "") return backend.statusMessage
                                    if (backend && !backend.overallSecurityOk) return "Status: " + backend.systemIntegrity
                                    return "Sourceless Lockdown Active"
                                }
                                color: (backend && !backend.overallSecurityOk) ? root.statusRed : root.textMain
                                font.pixelSize: 12
                                font.bold: backend ? !backend.overallSecurityOk : false
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentPage = 7
                        }
                    }
                }

                // Floating Search Results Dropdown Overlay
                Rectangle {
                    id: searchDropdown
                    visible: root.searchPopupOpen && root.searchQuery.length > 0
                    z: 100
                    x: sidebarCol.anchors.leftMargin
                    y: sidebarCol.y + searchBox.y + searchBox.height + 6
                    width: searchBox.width
                    height: dropdownCol.implicitHeight + 12
                    radius: 10
                    color: Qt.rgba(0.08, 0.09, 0.14, 0.98)
                    border.color: root.brandHighlight
                    border.width: 1

                    HoverHandler {
                        id: dropdownHover
                        onHoveredChanged: root.searchPopupHovered = hovered
                    }

                    ColumnLayout {
                        id: dropdownCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 6
                        spacing: 3

                        Label {
                            visible: root.searchResults.length === 0
                            Layout.fillWidth: true
                            padding: 8
                            text: "No matching settings found"
                            color: root.textMuted
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Repeater {
                            model: root.searchResults
                            delegate: Rectangle {
                                id: resRow
                                required property var modelData
                                required property int index
                                readonly property bool isRowActive: root.searchSelectedIndex === index || resMouse.containsMouse

                                Layout.fillWidth: true
                                height: 46
                                radius: 7
                                color: isRowActive ? Qt.rgba(0.38, 0.33, 0.95, 0.28) : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    CyberIcon {
                                        iconName: resRow.modelData.iconName
                                        width: 18
                                        height: 18
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        Label {
                                            Layout.fillWidth: true
                                            text: resRow.modelData.title
                                            color: "#FFFFFF"
                                            font.pixelSize: 12
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: resRow.modelData.subtitle
                                            color: root.textMuted
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    id: resMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.searchSelectedIndex = resRow.index
                                    onClicked: {
                                        root.searchSelectedIndex = resRow.index
                                        root.searchPopupHovered = false
                                        root.navigateToSearchResult(resRow.modelData, true)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // =================================================================
            // RIGHT CONTENT AREA (Integrated Titlebar + Scrollable Pages)
            // =================================================================
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Seamless Integrated Top Bar (Drag Area + Window Controls)
                Item {
                    Layout.fillWidth: true
                    height: 38

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onPressed: root.startSystemMove()
                        onDoubleClicked: {
                            if (root.visibility === Window.Maximized) root.showNormal()
                            else root.showMaximized()
                        }
                    }

                    RowLayout {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: 10
                        anchors.topMargin: 8
                        spacing: 6

                        // Minimize Button
                        Rectangle {
                            width: 34
                            height: 26
                            radius: 7
                            color: minMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent"

                            Label {
                                anchors.centerIn: parent
                                text: "─"
                                color: root.textMain
                                font.pixelSize: 12
                                font.bold: true
                            }

                            MouseArea {
                                id: minMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showMinimized()
                            }
                        }

                        // Maximize / Restore Button
                        Rectangle {
                            width: 34
                            height: 26
                            radius: 7
                            color: maxMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent"

                            Rectangle {
                                anchors.centerIn: parent
                                width: 10
                                height: 10
                                radius: 2
                                color: "transparent"
                                border.color: root.textMain
                                border.width: 1
                            }

                            MouseArea {
                                id: maxMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.visibility === Window.Maximized) root.showNormal()
                                    else root.showMaximized()
                                }
                            }
                        }

                        // Close Button (Red Hover like Windows 11)
                        Rectangle {
                            width: 34
                            height: 26
                            radius: 7
                            color: closeMouse.containsMouse ? root.statusRed : "transparent"

                            Label {
                                anchors.centerIn: parent
                                text: "✕"
                                color: closeMouse.containsMouse ? "#FFFFFF" : root.textMain
                                font.pixelSize: 13
                            }

                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.close()
                            }
                        }
                    }
                }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: root.currentPage

                    // -------------------------------------------------------------
                    // PAGE 0: HOME (Windows 11 Hero Overview + Quick Settings)
                    // -------------------------------------------------------------
                    ScrollView {
                        id: homeScroll
                        clip: true
                        contentWidth: availableWidth

                        ColumnLayout {
                            width: parent.width - 64
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 18

                            Item { height: 2 }

                        Label {
                            text: "Home"
                            color: root.textMain
                            font.pixelSize: 28
                            font.bold: true
                        }

                        // Hero Device Banner (Windows 11 Top Overview)
                        SettingCard {
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 20

                                Rectangle {
                                    width: 64
                                    height: 64
                                    radius: 14
                                    color: Qt.rgba(0.38, 0.33, 0.95, 0.2)
                                    border.color: root.brandHighlight
                                    border.width: 1

                                    CyberIcon {
                                        anchors.centerIn: parent
                                        iconName: "system"
                                        width: 38
                                        height: 38
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Label {
                                        text: backend ? backend.hostname : "sourceless-node"
                                        color: root.textMain
                                        font.pixelSize: 20
                                        font.bold: true
                                    }

                                    Label {
                                        text: backend ? (backend.osName + "  •  " + backend.cpuModel) : "Sourceless OS"
                                        color: root.textMuted
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 16
                                        Label {
                                            text: backend && backend.networkConnected ? ("● " + backend.connectionType + ": " + backend.activeNetworkName) : "● Network: Offline"
                                            color: backend && backend.networkConnected ? root.statusGreen : root.statusRed
                                            font.pixelSize: 13
                                            font.bold: true
                                        }
                                        Label {
                                            width: Math.min(implicitWidth, parent.width)
                                            text: (backend && !backend.overallSecurityOk) ? ("● System: " + backend.systemIntegrity) : "● Shield: Protected"
                                            color: (backend && !backend.overallSecurityOk) ? root.statusRed : root.statusGreen
                                            font.pixelSize: 13
                                            font.bold: true
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }

                                ActionButton {
                                    labelText: "Device specs"
                                    onTriggered: root.currentPage = 1
                                }
                            }
                        }

                        // Quick Settings Grid
                        Label {
                            text: "Quick settings"
                            color: root.textMain
                            font.pixelSize: 16
                            font.bold: true
                        }

                        SettingCard {
                            // Volume Quick Slider
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14

                                CyberIcon {
                                    iconName: backend && backend.muted ? "audio-muted" : "audio-high"
                                    width: 22; height: 22
                                }
                                Label {
                                    text: "Sound Volume"
                                    color: root.textMain
                                    font.pixelSize: 14
                                    Layout.preferredWidth: 140
                                }
                                WinSlider {
                                    Layout.fillWidth: true
                                    from: 0; to: 100
                                    value: backend ? backend.volume : 70
                                    onMoved: backend.setVolume(Math.round(value))
                                }
                                Label {
                                    text: (backend ? backend.volume : 70) + "%"
                                    color: root.textMuted
                                    font.pixelSize: 13
                                    Layout.preferredWidth: 42
                                    horizontalAlignment: Text.AlignRight
                                }
                                ActionButton {
                                    labelText: backend && backend.muted ? "Unmute" : "Mute"
                                    onTriggered: backend.toggleMute()
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            // Quick Toggles Row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 24

                                RowLayout {
                                    spacing: 10
                                    Label { text: "Wi-Fi"; color: root.textMain; font.pixelSize: 14 }
                                    WinSwitch {
                                        checkedState: backend ? backend.wifiEnabled : true
                                        onToggled: function(val) { backend.setWifiEnabled(val) }
                                    }
                                }

                                RowLayout {
                                    spacing: 10
                                    Label { text: "Bluetooth"; color: root.textMain; font.pixelSize: 14 }
                                    WinSwitch {
                                        checkedState: backend ? backend.bluetoothEnabled : false
                                        onToggled: function(val) { backend.setBluetoothEnabled(val) }
                                    }
                                }

                                RowLayout {
                                    spacing: 10
                                    Label { text: "Night Light"; color: root.textMain; font.pixelSize: 14 }
                                    WinSwitch {
                                        checkedState: backend ? backend.nightLightEnabled : false
                                        onToggled: function(val) { backend.setNightLight(val, backend.nightLightTemp) }
                                    }
                                }

                                RowLayout {
                                    spacing: 10
                                    Label { text: "Glass Blur"; color: root.textMain; font.pixelSize: 14 }
                                    WinSwitch {
                                        checkedState: backend ? backend.blurEnabled : true
                                        onToggled: function(val) { backend.setBlurEnabled(val) }
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }
                        }

                        // Recommended Shortcuts (Buttons Aligned Flush Right!)
                        Label {
                            text: "Recommended settings"
                            color: root.textMain
                            font.pixelSize: 16
                            font.bold: true
                        }

                        SettingCard {
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                CyberIcon { iconName: "display"; width: 24; height: 24 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Display resolution & scaling"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: backend ? (backend.displayName + " • " + backend.currentResolution + " (" + backend.displayScale + "%)") : ""; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton { labelText: "Configure"; onTriggered: root.currentPage = 1 }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                CyberIcon { iconName: "network"; width: 24; height: 24 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Wi-Fi & Network connections"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: backend ? ("IP: " + backend.ipAddress + " • " + backend.dnsStatus) : ""; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton { labelText: "Manage"; onTriggered: { root.currentPage = 3; backend.scanWifi() } }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                CyberIcon { iconName: "personalization"; width: 24; height: 24 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Personalize Sourceless Glass"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Switch curated dark wallpapers and window translucency"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton { labelText: "Personalize"; onTriggered: root.currentPage = 4 }
                            }
                        }

                        // System Resources Overview Card
                        SettingCard {
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 24

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: "System Storage"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                        Item { Layout.fillWidth: true }
                                        Label { text: backend ? (backend.diskUsedText + " / " + backend.diskTotalText + " (" + backend.diskFreeText + " free)") : ""; color: root.textMuted; font.pixelSize: 12 }
                                    }
                                    WinProgressBar {
                                        percentValue: backend ? backend.diskPercent : 20
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: "Memory (RAM)"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                        Item { Layout.fillWidth: true }
                                        Label { text: backend ? (backend.ramUsedText + " / " + backend.ramTotalText + " (" + backend.ramPercent + "%)") : ""; color: root.textMuted; font.pixelSize: 12 }
                                    }
                                    WinProgressBar {
                                        percentValue: backend ? backend.ramPercent : 30
                                    }
                                }
                            }
                        }

                        Item { height: 24 }
                    }
                }

                // -------------------------------------------------------------
                // PAGE 1: SYSTEM (Display Dropdowns, Sound, Power, Storage, About)
                // -------------------------------------------------------------
                ScrollView {
                    id: systemScroll
                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.width - 64
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 18

                        Item { height: 12 }

                        Label {
                            text: "System"
                            color: root.textMain
                            font.pixelSize: 28
                            font.bold: true
                        }

                        // DISPLAY SECTION (Now with Windows 11 Dropdown Lists!)
                        Label { text: "Display & Graphics"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            id: cardDisplay
                            sectionKey: "display"
                            // Row 1: Display Resolution Dropdown
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                CyberIcon { iconName: "display"; width: 24; height: 24 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Display resolution"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: backend ? ("Active monitor: " + backend.displayName + " (" + backend.currentResolution + ")") : ""; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinComboBox {
                                    id: resCombo
                                    model: backend ? backend.availableResolutions : []
                                    currentIndex: {
                                        if (!backend || !backend.availableResolutions) return 0
                                        const idx = backend.availableResolutions.indexOf(backend.currentResolution)
                                        return idx >= 0 ? idx : 0
                                    }
                                    onActivated: function(index) {
                                        if (backend && backend.availableResolutions[index]) {
                                            backend.setResolution(backend.availableResolutions[index])
                                        }
                                    }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            // Row 2: Scale & Layout Dropdown
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                CyberIcon { iconName: "scale"; width: 24; height: 24 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Scale & Layout"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Change the size of text, apps, and other items"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinComboBox {
                                    id: scaleCombo
                                    readonly property var scaleValues: [100, 125, 150, 175, 200]
                                    model: ["100% (Recommended)", "125%", "150%", "175%", "200%"]
                                    currentIndex: {
                                        if (!backend) return 0
                                        const idx = scaleValues.indexOf(backend.displayScale)
                                        return idx >= 0 ? idx : 0
                                    }
                                    onActivated: function(index) {
                                        if (backend && scaleValues[index] !== undefined) {
                                            backend.setDisplayScale(scaleValues[index])
                                        }
                                    }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            // Row 3: Night Light
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                CyberIcon { iconName: "night-light"; width: 24; height: 24 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Night Light (Eye Comfort)"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Use warmer colors to help block blue light (" + (backend ? backend.nightLightTemp : 4500) + "K)"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinSlider {
                                    from: 2800; to: 6000; stepSize: 100
                                    value: backend ? backend.nightLightTemp : 4500
                                    Layout.preferredWidth: 180
                                    onMoved: backend.setNightLight(backend.nightLightEnabled, Math.round(value))
                                }
                                WinSwitch {
                                    checkedState: backend ? backend.nightLightEnabled : false
                                    onToggled: function(val) { backend.setNightLight(val, backend.nightLightTemp) }
                                }
                            }
                        }

                        // SOUND SECTION
                        Label { text: "Sound"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            id: cardSound
                            sectionKey: "sound"
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                CyberIcon { iconName: "audio-speakers"; width: 24; height: 24 }
                                ColumnLayout {
                                    Layout.preferredWidth: 240
                                    spacing: 2
                                    Label { text: "Output Volume"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: backend ? backend.audioOutputName : "System Audio"; color: root.textMuted; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                                WinSlider {
                                    Layout.fillWidth: true
                                    from: 0; to: 100
                                    value: backend ? backend.volume : 70
                                    onMoved: backend.setVolume(Math.round(value))
                                }
                                Label { text: (backend ? backend.volume : 70) + "%"; color: root.textMain; Layout.preferredWidth: 42; horizontalAlignment: Text.AlignRight }
                                ActionButton { labelText: backend && backend.muted ? "Unmute" : "Mute"; onTriggered: backend.toggleMute() }
                                ActionButton { labelText: "Test"; primary: true; onTriggered: backend.testSound() }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                CyberIcon { iconName: "mic"; width: 24; height: 24 }
                                ColumnLayout {
                                    Layout.preferredWidth: 240
                                    spacing: 2
                                    Label { text: "Microphone Sensitivity"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: backend && backend.micMuted ? "Microphone Muted" : "Input Active"; color: backend && backend.micMuted ? root.statusRed : root.textMuted; font.pixelSize: 12 }
                                }
                                WinSlider {
                                    Layout.fillWidth: true
                                    from: 0; to: 100
                                    value: backend ? backend.micVolume : 80
                                    onMoved: backend.setMicVolume(Math.round(value))
                                }
                                Label { text: (backend ? backend.micVolume : 80) + "%"; color: root.textMain; Layout.preferredWidth: 42; horizontalAlignment: Text.AlignRight }
                                ActionButton { labelText: backend && backend.micMuted ? "Unmute Mic" : "Mute Mic"; onTriggered: backend.toggleMicMute() }
                            }
                        }

                        // POWER & STORAGE SECTION
                        Label { text: "Power & Storage"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            id: cardPower
                            sectionKey: "power"
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                CyberIcon { iconName: "power"; width: 24; height: 24 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Power Mode & Energy"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: backend ? (backend.batteryState + " (" + backend.batteryPercent + "%)") : ""; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton {
                                    labelText: "Power Saver"
                                    primary: backend && backend.powerProfile === "power-saver"
                                    onTriggered: backend.setPowerProfile("power-saver")
                                }
                                ActionButton {
                                    labelText: "Balanced"
                                    primary: backend && backend.powerProfile === "balanced"
                                    onTriggered: backend.setPowerProfile("balanced")
                                }
                                ActionButton {
                                    labelText: "Performance"
                                    primary: backend && backend.powerProfile === "performance"
                                    onTriggered: backend.setPowerProfile("performance")
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                CyberIcon { iconName: "storage"; width: 24; height: 24 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Storage Sense (" + (backend ? backend.diskUsedText : "") + " used of " + (backend ? backend.diskTotalText : "") + ")"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Free space available: " + (backend ? backend.diskFreeText : ""); color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton {
                                    labelText: "Clean Temp Cache"
                                    onTriggered: backend.clearUserCache()
                                }
                            }
                        }

                        // ABOUT DEVICE SPECIFICATIONS (Windows 11 About Card)
                        Label { text: "About this PC"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            id: cardAbout
                            sectionKey: "about"
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 24
                                rowSpacing: 10

                                Label { text: "Device Name (Hostname)"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? backend.hostname : ""; color: root.textMain; font.pixelSize: 13; font.bold: true }

                                Label { text: "Active User Account"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? (backend.userFullName + " (" + backend.userName + ")") : ""; color: root.textMain; font.pixelSize: 13; font.bold: true }

                                Label { text: "Processor (CPU)"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? (backend.cpuModel + " (" + backend.cpuCores + " threads)") : ""; color: root.textMain; font.pixelSize: 13 }

                                Label { text: "Graphics (GPU)"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? backend.gpuModel : ""; color: root.textMain; font.pixelSize: 13 }

                                Label { text: "Installed RAM"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? (backend.ramTotalText + " (" + backend.ramUsedText + " active)") : ""; color: root.textMain; font.pixelSize: 13 }

                                Label { text: "Operating System"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? (backend.osName + " (Immutable OSTree)") : ""; color: root.textMain; font.pixelSize: 13; font.bold: true }

                                Label { text: "Linux Kernel Version"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? backend.kernelVersion : ""; color: root.textMain; font.pixelSize: 13 }

                                Label { text: "System Uptime"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? backend.uptimeText : ""; color: root.textMain; font.pixelSize: 13 }

                                Label { text: "Enrolled Node HWID"; color: root.textMuted; font.pixelSize: 13 }
                                Label { text: backend ? backend.hwid : ""; color: root.brandHighlight; font.pixelSize: 13; font.bold: true }
                            }
                        }

                        Item { height: 24 }
                    }
                }

                // -------------------------------------------------------------
                // PAGE 2: BLUETOOTH & DEVICES (Bluetooth + Mouse & Touchpad)
                // -------------------------------------------------------------
                ScrollView {
                    id: btScroll
                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.width - 64
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 18

                        Item { height: 12 }

                        Label {
                            text: "Bluetooth & devices"
                            color: root.textMain
                            font.pixelSize: 28
                            font.bold: true
                        }

                        SettingCard {
                            id: cardBluetooth
                            sectionKey: "bluetooth"
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                CyberIcon { iconName: "bluetooth"; width: 24; height: 24 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Bluetooth"; color: root.textMain; font.pixelSize: 15; font.bold: true }
                                    Label { text: backend && backend.bluetoothEnabled ? "Discoverable as " + backend.hostname : "Bluetooth is turned off"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton {
                                    labelText: "Scan Devices"
                                    primary: true
                                    enabledBtn: backend ? backend.bluetoothEnabled : false
                                    onTriggered: backend.scanBluetooth()
                                }
                                WinSwitch {
                                    checkedState: backend ? backend.bluetoothEnabled : false
                                    onToggled: function(val) { backend.setBluetoothEnabled(val) }
                                }
                            }

                            Repeater {
                                model: backend ? backend.bluetoothDevices : []
                                delegate: ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: modelData.name; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                        Label { text: "(" + modelData.mac + ")"; color: root.textMuted; font.pixelSize: 12 }
                                        Item { Layout.fillWidth: true }
                                        Label {
                                            text: modelData.connected ? "Connected" : "Paired"
                                            color: modelData.connected ? root.statusGreen : root.textMuted
                                            font.pixelSize: 12
                                        }
                                        ActionButton {
                                            labelText: modelData.connected ? "Disconnect" : "Connect"
                                            primary: !modelData.connected
                                            onTriggered: backend.toggleBluetoothDevice(modelData.mac, !modelData.connected)
                                        }
                                    }
                                }
                            }
                        }

                        // MOUSE & TOUCHPAD SECTION
                        Label { text: "Mouse & Touchpad"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            id: cardMouse
                            sectionKey: "mouse"
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                CyberIcon { iconName: "mouse"; width: 24; height: 24 }
                                ColumnLayout {
                                    Layout.preferredWidth: 220
                                    spacing: 2
                                    Label { text: "Cursor Speed"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Adjust pointer sensitivity"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                WinSlider {
                                    Layout.fillWidth: true
                                    from: 1; to: 10; stepSize: 1
                                    value: backend ? backend.mouseSpeed : 5
                                    onMoved: backend.setMouseSettings(Math.round(value), backend.naturalScroll, backend.tapToClick, backend.leftHandedMouse)
                                }
                                Label { text: (backend ? backend.mouseSpeed : 5) + " / 10"; color: root.textMain; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignRight }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Natural Scrolling"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Content tracks finger movement on touchpad"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinSwitch {
                                    checkedState: backend ? backend.naturalScroll : false
                                    onToggled: function(val) { backend.setMouseSettings(backend.mouseSpeed, val, backend.tapToClick, backend.leftHandedMouse) }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Tap to Click (Touchpad)"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Single-finger tap registers as left click"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinSwitch {
                                    checkedState: backend ? backend.tapToClick : true
                                    onToggled: function(val) { backend.setMouseSettings(backend.mouseSpeed, backend.naturalScroll, val, backend.leftHandedMouse) }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Left-Handed Mouse Mode"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Swap primary left and right mouse buttons"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinSwitch {
                                    checkedState: backend ? backend.leftHandedMouse : false
                                    onToggled: function(val) { backend.setMouseSettings(backend.mouseSpeed, backend.naturalScroll, backend.tapToClick, val) }
                                }
                            }
                        }

                        Item { height: 24 }
                    }
                }

                // -------------------------------------------------------------
                // PAGE 3: NETWORK & INTERNET
                // -------------------------------------------------------------
                ScrollView {
                    id: netScroll
                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.width - 64
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 18

                        Item { height: 12 }

                        Label {
                            text: "Network & internet"
                            color: root.textMain
                            font.pixelSize: 28
                            font.bold: true
                        }

                        // Network Status Banner (Windows 11 Top Card)
                        SettingCard {
                            id: cardNetStatus
                            sectionKey: "net-status"
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 20

                                CyberIcon {
                                    iconName: backend && backend.networkConnected ? "network-connected" : "network-offline"
                                    width: 36; height: 36
                                }

                                ColumnLayout {
                                    spacing: 4
                                    Label {
                                        text: backend && backend.networkConnected ? ("Connected to " + backend.activeNetworkName + " (" + backend.connectionType + ")") : "Not Connected"
                                        color: backend && backend.networkConnected ? root.statusGreen : root.statusRed
                                        font.pixelSize: 16
                                        font.bold: true
                                    }
                                    Label {
                                        text: backend ? ("IPv4 Address: " + backend.ipAddress + "   •   DNS: " + backend.dnsStatus) : ""
                                        color: root.textMuted
                                        font.pixelSize: 13
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                ActionButton {
                                    visible: backend ? backend.networkConnected : false
                                    labelText: "Disconnect"
                                    danger: true
                                    onTriggered: backend.disconnectNetwork()
                                }
                            }
                        }

                        // Wi-Fi Management Card
                        SettingCard {
                            id: cardWifi
                            sectionKey: "wifi"
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                CyberIcon { iconName: "network"; width: 24; height: 24 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Wi-Fi"; color: root.textMain; font.pixelSize: 15; font.bold: true }
                                    Label { text: "Connect to available wireless networks"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton {
                                    labelText: "Scan Networks"
                                    primary: true
                                    enabledBtn: backend ? backend.wifiEnabled : false
                                    onTriggered: backend.scanWifi()
                                }
                                WinSwitch {
                                    checkedState: backend ? backend.wifiEnabled : true
                                    onToggled: function(val) { backend.setWifiEnabled(val) }
                                }
                            }

                            Repeater {
                                model: backend ? backend.wifiNetworks : []
                                delegate: ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 12

                                        CyberIcon {
                                            iconName: "network"
                                            width: 20; height: 20
                                        }

                                        ColumnLayout {
                                            spacing: 1
                                            Label {
                                                text: modelData.ssid
                                                color: root.textMain
                                                font.pixelSize: 14
                                                font.bold: modelData.inUse
                                            }
                                            Label {
                                                text: "Signal: " + modelData.signal + "%  •  Security: " + modelData.security
                                                color: root.textMuted
                                                font.pixelSize: 12
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        Label {
                                            visible: modelData.inUse
                                            text: "Connected"
                                            color: root.statusGreen
                                            font.pixelSize: 13
                                            font.bold: true
                                        }

                                        ActionButton {
                                            visible: !modelData.inUse
                                            labelText: root.selectedWifiSsid === modelData.ssid ? "Cancel" : "Connect"
                                            primary: root.selectedWifiSsid !== modelData.ssid
                                            onTriggered: {
                                                if (modelData.security === "Open") {
                                                    backend.connectWifi(modelData.ssid, "")
                                                } else {
                                                    root.selectedWifiSsid = (root.selectedWifiSsid === modelData.ssid) ? "" : modelData.ssid
                                                }
                                            }
                                        }
                                    }

                                    // Inline Password Input Box when network is selected
                                    RowLayout {
                                        visible: root.selectedWifiSsid === modelData.ssid
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 34
                                            radius: 6
                                            color: root.bgInput
                                            border.color: root.brandHighlight
                                            border.width: 1

                                            TextField {
                                                id: wifiPassInput
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                placeholderText: "Enter Wi-Fi security key for " + modelData.ssid
                                                placeholderTextColor: root.textMuted
                                                echoMode: TextInput.Password
                                                color: root.textMain
                                                font.pixelSize: 13
                                                background: Item {}
                                            }
                                        }

                                        ActionButton {
                                            labelText: "Join Network"
                                            primary: true
                                            onTriggered: {
                                                backend.connectWifi(modelData.ssid, wifiPassInput.text)
                                                root.selectedWifiSsid = ""
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Item { height: 24 }
                    }
                }

                // -------------------------------------------------------------
                // PAGE 4: PERSONALIZATION (Wallpapers & Glass Effects)
                // -------------------------------------------------------------
                ScrollView {
                    id: personalizationScroll
                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.width - 64
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 18

                        Item { height: 12 }

                        Label {
                            text: "Personalization"
                            color: root.textMain
                            font.pixelSize: 28
                            font.bold: true
                        }

                        Label {
                            text: "Official Sourceless Wallpapers"
                            color: root.textMain
                            font.pixelSize: 16
                            font.bold: true
                        }

                        SettingCard {
                            id: cardWallpaper
                            sectionKey: "wallpaper"
                            Label {
                                text: "Choose an approved system background (custom third-party themes are disabled for security)"
                                color: root.textMuted
                                font.pixelSize: 13
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 14

                                Repeater {
                                    model: backend ? backend.wallpapers : []
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: 210
                                        height: 145
                                        radius: 10
                                        color: root.bgInput
                                        border.color: wpMouse.containsMouse ? root.brandHighlight : root.borderSubtle
                                        border.width: wpMouse.containsMouse ? 2 : 1
                                        clip: true

                                        ColumnLayout {
                                            anchors.fill: parent
                                            spacing: 0

                                            Image {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                source: modelData.previewUrl
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                sourceSize.width: 320
                                                sourceSize.height: 180
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 32
                                                color: Qt.rgba(0.06, 0.07, 0.11, 0.92)

                                                Label {
                                                    anchors.centerIn: parent
                                                    text: modelData.name
                                                    color: root.textMain
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: wpMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: backend.applyWallpaper(modelData.path)
                                        }
                                    }
                                }
                            }
                        }

                        Label { text: "Sourceless Glass Visual Effects"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            id: cardEffects
                            sectionKey: "effects"
                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Translucent Window Blur (Acrylic / Glass)"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Apply real-time KWin GPU frosted glass blur behind translucent surfaces"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinSwitch {
                                    checkedState: backend ? backend.blurEnabled : true
                                    onToggled: function(val) { backend.setBlurEnabled(val) }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Smooth Desktop Animations"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Enable window transitions and workspace animations"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinSwitch {
                                    checkedState: backend ? backend.animationsEnabled : true
                                    onToggled: function(val) { backend.setAnimationsEnabled(val) }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Reset Taskbar & Desktop Layout"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Restore the default Sourceless floating dock and start menu configuration"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton {
                                    labelText: "Restore Layout"
                                    onTriggered: backend.resetDesktopLayout()
                                }
                            }
                        }

                        Item { height: 24 }
                    }
                }

                // -------------------------------------------------------------
                // PAGE 5: APPS (Sandboxed Flatpak Applications)
                // -------------------------------------------------------------
                ScrollView {
                    id: appsScroll
                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.width - 64
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 18

                        Item { height: 12 }

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: "Apps"
                                color: root.textMain
                                font.pixelSize: 28
                                font.bold: true
                            }
                            Item { Layout.fillWidth: true }
                            ActionButton {
                                labelText: "Refresh List"
                                onTriggered: backend.refreshApps()
                            }
                            ActionButton {
                                labelText: "Check for Updates"
                                primary: true
                                onTriggered: backend.updateAllApps()
                            }
                        }

                        SettingCard {
                            id: cardApps
                            sectionKey: "apps"
                            Label {
                                text: "Installed Sandboxed Applications (" + (backend ? backend.installedApps.length : 0) + ")"
                                color: root.textMain
                                font.pixelSize: 15
                                font.bold: true
                            }
                            Label {
                                text: "All applications run inside isolated Flatpak containers. Core system apps are protected against removal."
                                color: root.textMuted
                                font.pixelSize: 12
                            }

                            Repeater {
                                model: backend ? backend.installedApps : []
                                delegate: ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 12

                                        CyberIcon {
                                            iconName: "apps"
                                            width: 24; height: 24
                                        }

                                        ColumnLayout {
                                            spacing: 1
                                            Label {
                                                text: modelData.name
                                                color: root.textMain
                                                font.pixelSize: 14
                                                font.bold: true
                                            }
                                            Label {
                                                text: modelData.appId + "  •  v" + modelData.version + " (" + modelData.scope + ")"
                                                color: root.textMuted
                                                font.pixelSize: 12
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        ActionButton {
                                            labelText: "Open"
                                            onTriggered: backend.launchApp(modelData.appId)
                                        }

                                        ActionButton {
                                            labelText: modelData.protectedApp ? "System Core" : "Uninstall"
                                            danger: !modelData.protectedApp
                                            enabledBtn: !modelData.protectedApp
                                            onTriggered: backend.uninstallApp(modelData.appId)
                                        }
                                    }
                                }
                            }
                        }

                        Item { height: 24 }
                    }
                }

                // -------------------------------------------------------------
                // PAGE 6: TIME & LANGUAGE
                // -------------------------------------------------------------
                ScrollView {
                    id: timeScroll
                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.width - 64
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 18

                        Item { height: 12 }

                        Label {
                            text: "Time & language"
                            color: root.textMain
                            font.pixelSize: 28
                            font.bold: true
                        }

                        SettingCard {
                            id: cardDateTime
                            sectionKey: "datetime"
                            RowLayout {
                                Layout.fillWidth: true
                                CyberIcon { iconName: "time"; width: 28; height: 28 }
                                ColumnLayout {
                                    spacing: 2
                                    Label {
                                        text: backend ? backend.currentDateTime : ""
                                        color: root.textMain
                                        font.pixelSize: 18
                                        font.bold: true
                                    }
                                    Label {
                                        text: backend ? ("Time zone: " + backend.timezone + "  •  NTP Synchronization: " + (backend.ntpEnabled ? "Active" : "Manual")) : ""
                                        color: root.textMuted
                                        font.pixelSize: 13
                                    }
                                }
                                Item { Layout.fillWidth: true }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.borderSubtle }

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "24-hour clock format"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Display time using 24-hour military notation"; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                WinSwitch {
                                    checkedState: backend ? backend.use24Hour : true
                                    onToggled: function(val) { backend.setUse24Hour(val) }
                                }
                            }
                        }

                        Label { text: "Keyboard Layout"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            id: cardKeyboard
                            sectionKey: "keyboard"
                            Label {
                                text: "Active keyboard layout: " + (backend ? backend.keyboardLayout.toUpperCase() : "US")
                                color: root.textMain
                                font.pixelSize: 14
                                font.bold: true
                            }
                            Label {
                                text: "Select your preferred keyboard input layout (when dual layout is selected, switch with Alt+Shift)"
                                color: root.textMuted
                                font.pixelSize: 12
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 10

                                Repeater {
                                    model: [
                                        { code: "us", label: "English (US)" },
                                        { code: "ro", label: "Română (Standard)" },
                                        { code: "us,ro", label: "US + Română (Dual)" },
                                        { code: "gb", label: "English (UK)" },
                                        { code: "de", label: "Deutsch (DE)" },
                                        { code: "fr", label: "Français (FR)" },
                                        { code: "es", label: "Español (ES)" },
                                        { code: "it", label: "Italiano (IT)" }
                                    ]
                                    delegate: ActionButton {
                                        required property var modelData
                                        labelText: modelData.label
                                        primary: backend && backend.keyboardLayout === modelData.code
                                        onTriggered: backend.setKeyboardLayout(modelData.code)
                                    }
                                }
                            }
                        }

                        Item { height: 24 }
                    }
                }

                // -------------------------------------------------------------
                // PAGE 7: PRIVACY & SECURITY (Color-Coded Posture + Live Tools)
                // -------------------------------------------------------------
                ScrollView {
                    id: securityScroll
                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.width - 64
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 18

                        Item { height: 12 }

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: "Privacy & security"
                                color: root.textMain
                                font.pixelSize: 28
                                font.bold: true
                            }
                            Item { Layout.fillWidth: true }
                            ActionButton {
                                labelText: "Refresh Status"
                                onTriggered: backend.refreshSecurity()
                            }
                        }

                        // Top Security Posture Card (Turns RED when Modified / Negative!)
                        SettingCard {
                            id: cardPosture
                            sectionKey: "posture"
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 16

                                Rectangle {
                                    readonly property bool secOk: backend ? backend.overallSecurityOk : true
                                    width: 56
                                    height: 56
                                    radius: 14
                                    color: secOk ? Qt.rgba(0.16, 0.76, 0.63, 0.18) : Qt.rgba(0.95, 0.33, 0.43, 0.20)
                                    border.color: secOk ? root.statusGreen : root.statusRed
                                    border.width: 1

                                    CyberIcon {
                                        anchors.centerIn: parent
                                        iconName: (backend && !backend.overallSecurityOk) ? "security-low" : "security-high"
                                        width: 32; height: 32
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Label {
                                        text: (backend && !backend.overallSecurityOk)
                                              ? ("Security Warning: System State Modified (" + backend.securityScore + "%)")
                                              : ("Sourceless Security Policy is Enforced (" + (backend ? backend.securityScore : 100) + "%)")
                                        color: (backend && !backend.overallSecurityOk) ? root.statusRed : root.statusGreen
                                        font.pixelSize: 17
                                        font.bold: true
                                    }
                                    Label {
                                        text: (backend && !backend.overallSecurityOk)
                                              ? "One or more security seals are unsealed (Sudo / Wheel privilege or Support Terminal active). Review red indicators below."
                                              : "All mandatory lockdown controls, read-only OSTree verification, and YARA malware shields are intact."
                                        color: root.textMuted
                                        font.pixelSize: 13
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            WinProgressBar {
                                percentValue: backend ? backend.securityScore : 100
                                barColor: (backend && !backend.overallSecurityOk) ? root.statusRed : root.statusGreen
                            }
                        }

                        // Active Protection Layers (Every Negative State is RED!)
                        Label { text: "Active Protection Layers (Real-Time Telemetry)"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            id: cardTelemetry
                            sectionKey: "telemetry"
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 24
                                rowSpacing: 12

                                Label { text: "System Image & Tamper Seal"; color: root.textMuted; font.pixelSize: 13 }
                                Label {
                                    text: backend ? backend.systemIntegrity : ""
                                    color: (backend && backend.isTampered) ? root.statusRed : root.statusGreen
                                    font.pixelSize: 13; font.bold: true
                                }

                                Label { text: "Interactive Terminal Gate"; color: root.textMuted; font.pixelSize: 13 }
                                Label {
                                    text: (backend && backend.supportSessionActive) ? "UNSEALED (Support Shell Permitted)" : "Locked (Kiosk Policy Enforced)"
                                    color: (backend && backend.supportSessionActive) ? root.statusRed : root.statusGreen
                                    font.pixelSize: 13; font.bold: true
                                }

                                Label { text: "SELinux Access Control"; color: root.textMuted; font.pixelSize: 13 }
                                Label {
                                    text: backend ? backend.selinuxStatus : ""
                                    color: (backend && !backend.selinuxOk) ? root.statusRed : root.statusGreen
                                    font.pixelSize: 13; font.bold: true
                                }

                                Label { text: "Kernel Lockdown Mode"; color: root.textMuted; font.pixelSize: 13 }
                                Label {
                                    text: backend ? backend.lockdownMode : ""
                                    color: (backend && !backend.lockdownOk) ? root.statusRed : root.statusGreen
                                    font.pixelSize: 13; font.bold: true
                                }

                                Label { text: "Sourceless Real-Time YARA Shield"; color: root.textMuted; font.pixelSize: 13 }
                                Label {
                                    text: backend && backend.shieldActive ? "Active (Monitoring ~/Downloads & Autostart)" : "STOPPED (Unprotected)"
                                    color: backend && backend.shieldActive ? root.statusGreen : root.statusRed
                                    font.pixelSize: 13; font.bold: true
                                }

                                Label { text: "Telemetry & Remote Support Agent"; color: root.textMuted; font.pixelSize: 13 }
                                Label {
                                    text: backend && backend.clientActive ? "Connected (Enrolled HWID)" : "Offline / Disconnected"
                                    color: backend && backend.clientActive ? root.statusGreen : root.statusRed
                                    font.pixelSize: 13; font.bold: true
                                }

                                Label { text: "DNS-over-TLS & Malware Filtering"; color: root.textMuted; font.pixelSize: 13 }
                                Label {
                                    text: backend ? backend.dnsStatus : ""
                                    color: root.statusGreen
                                    font.pixelSize: 13; font.bold: true
                                }
                            }
                        }

                        // On-Demand YARA Threat Scanner Card
                        Label { text: "Endpoint Malware & Infostealer Scanner (YARA)"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            id: cardScanner
                            sectionKey: "scanner"
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                CyberIcon { iconName: "security-scan"; width: 26; height: 26 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "On-Demand Downloads & Home Threat Scan"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label {
                                        text: backend ? backend.lastScanResult : ""
                                        color: (backend && backend.lastScanResult.startsWith("ALERT:")) ? root.statusRed : root.statusGreen
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton {
                                    labelText: "Scan Now"
                                    primary: true
                                    onTriggered: backend.runQuickSecurityScan()
                                }
                            }
                        }

                        // Active Security Events / Findings
                        Label { text: "Security Audit Findings"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            id: cardAudit
                            sectionKey: "audit"
                            Repeater {
                                model: backend ? backend.securityEvents : []
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Rectangle {
                                        width: 8; height: 8; radius: 4
                                        color: modelData.severity === "critical" ? root.statusRed : (modelData.severity === "warning" ? root.statusAmber : root.statusGreen)
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: modelData.title
                                        color: modelData.severity === "critical" ? root.statusRed : root.textMain
                                        font.pixelSize: 13
                                        font.bold: modelData.severity === "critical"
                                    }
                                }
                            }
                        }

                        // Authorized Technical Support
                        Label { text: "Authorized Technical Support"; color: root.textMain; font.pixelSize: 16; font.bold: true }

                        SettingCard {
                            id: cardSupport
                            sectionKey: "support"
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                CyberIcon { iconName: "terminal"; width: 26; height: 26 }
                                ColumnLayout {
                                    spacing: 2
                                    Label { text: "Emergency Technician Terminal"; color: root.textMain; font.pixelSize: 14; font.bold: true }
                                    Label { text: "Requires today's cryptographic support authorization key. Unsealing triggers tamper telemetry."; color: root.textMuted; font.pixelSize: 12 }
                                }
                                Item { Layout.fillWidth: true }
                                ActionButton {
                                    labelText: "Authorize Support Shell"
                                    onTriggered: backend.launchEmergencyTerminal()
                                }
                            }
                        }

                        Item { height: 24 }
                    }
                }
                }
            }
        }

        // Continuous 4-Corner Rounded Border Overlay
        Rectangle {
            anchors.fill: parent
            radius: root.windowRadius
            color: "transparent"
            border.color: root.borderSubtle
            border.width: root.windowRadius > 0 ? 1 : 0
        }

        // Edge & Corner System Resize Handles (Active when Windowed)
        MouseArea {
            visible: root.visibility !== Window.Maximized
            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
            anchors.topMargin: 12; anchors.bottomMargin: 12
            width: 5
            cursorShape: Qt.SizeHorCursor
            onPressed: root.startSystemResize(Qt.LeftEdge)
        }
        MouseArea {
            visible: root.visibility !== Window.Maximized
            anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
            anchors.topMargin: 12; anchors.bottomMargin: 12
            width: 5
            cursorShape: Qt.SizeHorCursor
            onPressed: root.startSystemResize(Qt.RightEdge)
        }
        MouseArea {
            visible: root.visibility !== Window.Maximized
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 12; anchors.rightMargin: 130
            height: 5
            cursorShape: Qt.SizeVerCursor
            onPressed: root.startSystemResize(Qt.TopEdge)
        }
        MouseArea {
            visible: root.visibility !== Window.Maximized
            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 12; anchors.rightMargin: 12
            height: 5
            cursorShape: Qt.SizeVerCursor
            onPressed: root.startSystemResize(Qt.BottomEdge)
        }
        MouseArea {
            visible: root.visibility !== Window.Maximized
            anchors.right: parent.right; anchors.bottom: parent.bottom
            width: 14; height: 14
            cursorShape: Qt.SizeFDiagCursor
            onPressed: root.startSystemResize(Qt.RightEdge | Qt.BottomEdge)
        }
        MouseArea {
            visible: root.visibility !== Window.Maximized
            anchors.left: parent.left; anchors.bottom: parent.bottom
            width: 14; height: 14
            cursorShape: Qt.SizeBDiagCursor
            onPressed: root.startSystemResize(Qt.LeftEdge | Qt.BottomEdge)
        }
    }
}
