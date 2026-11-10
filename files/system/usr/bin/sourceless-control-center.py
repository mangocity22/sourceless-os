#!/usr/bin/env python3
import sys
import os
import pwd
import subprocess
from PyQt6.QtWidgets import (QApplication, QWidget, QVBoxLayout, QHBoxLayout, 
                             QPushButton, QLabel, QFrame, QScrollArea, QStackedWidget)
from PyQt6.QtGui import QIcon
from PyQt6.QtCore import Qt, QSize

class ControlCenter(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Sourceless Control Center")
        self.resize(1100, 750)

        # Styling de bază pentru "Liquid Glass"
        self.setStyleSheet("""
            QWidget {
                background-color: #1c1d25;
                color: #e0e5ff;
                font-family: 'Inter', sans-serif;
            }
            QFrame#sidebar {
                background-color: rgba(25, 27, 38, 0.7);
                border-right: 1px solid rgba(255, 255, 255, 0.05);
            }
            QPushButton.sidebar_btn {
                background: transparent;
                border: none;
                border-radius: 6px;
                padding: 10px 15px;
                text-align: left;
                font-size: 14px;
            }
            QPushButton.sidebar_btn:hover {
                background-color: rgba(255, 255, 255, 0.08);
            }
            QPushButton.sidebar_btn:checked {
                background-color: rgba(122, 162, 247, 0.2);
                color: #7aa2f7;
                font-weight: bold;
            }
            QFrame.card {
                background-color: rgba(30, 32, 48, 0.6);
                border-radius: 12px;
                border: 1px solid rgba(255, 255, 255, 0.05);
                margin-bottom: 10px;
            }
            QLabel.section_title {
                font-size: 18px;
                font-weight: bold;
                padding-bottom: 5px;
            }
            QPushButton.card_action_btn {
                background-color: rgba(255, 255, 255, 0.05);
                border-radius: 6px;
                padding: 12px;
                text-align: left;
                border: none;
                font-size: 14px;
                margin: 5px;
            }
            QPushButton.card_action_btn:hover {
                background-color: rgba(255, 255, 255, 0.1);
            }
        """)

        main_layout = QHBoxLayout(self)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)

        # -----------------------------------------------------
        # SIDEBAR (Stânga)
        # -----------------------------------------------------
        sidebar = QFrame()
        sidebar.setObjectName("sidebar")
        sidebar.setFixedWidth(260)
        sidebar_layout = QVBoxLayout(sidebar)
        sidebar_layout.setContentsMargins(15, 20, 15, 20)
        sidebar_layout.setSpacing(5)

        # Preluare dinamică a userului din Sourceless OS
        username = os.environ.get('USER', 'sourceless')
        try:
            full_name = pwd.getpwnam(username).pw_gecos.split(',')[0]
            if not full_name: 
                full_name = username.capitalize()
        except KeyError:
            full_name = "Sourceless Admin"
            
        lbl_profile = QLabel(f"{full_name}\n@{username}")
        lbl_profile.setStyleSheet("padding-bottom: 20px; font-weight: bold; font-size: 15px;")
        sidebar_layout.addWidget(lbl_profile)

        self.nav_buttons_group = []
        
        # -----------------------------------------------------
        # ZONA PRINCIPALĂ (Dreapta) - QStackedWidget
        # -----------------------------------------------------
        self.stacked_widget = QStackedWidget()
        
        # Definirea paginilor și a modulelor aferente
        self.pages_data = [
            ("Home", "home", self.create_home_page()),
            ("System", "computer", self.create_system_page()),
            ("Network & Internet", "network-wireless", self.create_network_page()),
            ("Bluetooth & Devices", "bluetooth", self.create_devices_page()),
            ("Personalization", "preferences-desktop-wallpaper", self.create_personalization_page())
        ]

        for index, (text, icon_name, widget) in enumerate(self.pages_data):
            btn = QPushButton(text)
            btn.setProperty("class", "sidebar_btn")
            btn.setIcon(QIcon.fromTheme(icon_name))
            btn.setIconSize(QSize(20, 20))
            btn.setCursor(Qt.CursorShape.PointingHandCursor)
            btn.setCheckable(True)
            btn.clicked.connect(lambda checked, idx=index: self.switch_page(idx))
            sidebar_layout.addWidget(btn)
            self.nav_buttons_group.append(btn)
            self.stacked_widget.addWidget(widget)

        sidebar_layout.addStretch()
        main_layout.addWidget(sidebar)
        main_layout.addWidget(self.stacked_widget)
        
        if self.nav_buttons_group:
            self.nav_buttons_group[0].setChecked(True)
            self.stacked_widget.setCurrentIndex(0)

    def switch_page(self, index):
        for i, btn in enumerate(self.nav_buttons_group):
            btn.setChecked(i == index)
        self.stacked_widget.setCurrentIndex(index)

    def create_scrollable_page(self, title, cards_data):
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setStyleSheet("background: transparent;")
        
        content_widget = QWidget()
        layout = QVBoxLayout(content_widget)
        layout.setContentsMargins(40, 30, 40, 30)
        layout.setSpacing(15)

        lbl_page_title = QLabel(title)
        lbl_page_title.setStyleSheet("font-size: 28px; font-weight: bold; margin-bottom: 10px;")
        layout.addWidget(lbl_page_title)
        
        for section_title, actions in cards_data:
            lbl_sec = QLabel(section_title)
            lbl_sec.setProperty("class", "section_title")
            layout.addWidget(lbl_sec)
            
            card = QFrame()
            card.setProperty("class", "card")
            card_layout = QVBoxLayout(card)
            card_layout.setContentsMargins(10, 10, 10, 10)
            card_layout.setSpacing(5)
            
            for btn_text, icon_name, kcm_mod in actions:
                btn = QPushButton(btn_text)
                btn.setProperty("class", "card_action_btn")
                btn.setIcon(QIcon.fromTheme(icon_name))
                btn.setIconSize(QSize(24, 24))
                btn.setCursor(Qt.CursorShape.PointingHandCursor)
                # kcmshell6 deschide strict fereastra acelui modul
                btn.clicked.connect(lambda checked, m=kcm_mod: self.open_kcm(m))
                card_layout.addWidget(btn)
                
            layout.addWidget(card)
            
        layout.addStretch()
        scroll.setWidget(content_widget)
        return scroll

    def create_home_page(self):
        return self.create_scrollable_page("Home", [
            ("Recommended Settings", [
                ("Display Configuration", "preferences-desktop-display-randr", "kcm_kscreen"),
                ("Wi-Fi & Networks", "network-wireless", "kcm_networkmanagement"),
                ("Sound Output & Input", "preferences-desktop-sound", "kcm_pulseaudio")
            ])
        ])

    def create_system_page(self):
        return self.create_scrollable_page("System", [
            ("Hardware", [
                ("Display Configuration", "preferences-desktop-display-randr", "kcm_kscreen"),
                ("Power Management", "preferences-system-power-management", "kcm_powerdevilprofilesconfig")
            ]),
            ("Administration", [
                ("About This System", "help-about", "kcm_about-distro"),
                ("User Accounts", "preferences-system-login", "kcm_users")
            ])
        ])

    def create_network_page(self):
        return self.create_scrollable_page("Network & Internet", [
            ("Connectivity", [
                ("Wi-Fi & Ethernet", "network-wireless", "kcm_networkmanagement"),
                ("Firewall Configuration", "security-high", "kcm_firewall")
            ])
        ])
        
    def create_devices_page(self):
        return self.create_scrollable_page("Bluetooth & Devices", [
            ("Peripherals", [
                ("Bluetooth Devices", "preferences-system-bluetooth", "kcm_bluetooth"),
                ("Printers", "printer", "kcm_printers"),
                ("Mouse & Touchpad", "input-mouse", "kcm_mouse")
            ])
        ])
        
    def create_personalization_page(self):
        return self.create_scrollable_page("Personalization", [
            ("Appearance", [
                ("Global Theme", "preferences-desktop-theme-global", "kcm_lookandfeel"),
                ("System Colors", "preferences-desktop-color", "kcm_colors"),
                ("Icons", "preferences-desktop-icons", "kcm_icons"),
                ("Wallpapers", "preferences-desktop-wallpaper", "kcm_wallpaper")
            ])
        ])

    def open_kcm(self, kcm_module):
        # Apelează strict kcmshell6 pentru a randa doar panoul specific, 
        # fără să deschidă tot meniul de systemsettings.
        subprocess.Popen(["kcmshell6", kcm_module])

if __name__ == '__main__':
    app = QApplication(sys.argv)
    window = ControlCenter()
    window.show()
    sys.exit(app.exec())