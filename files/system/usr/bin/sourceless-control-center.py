#!/usr/bin/env python3
import sys
import subprocess
from PyQt6.QtWidgets import (QApplication, QWidget, QVBoxLayout, QHBoxLayout, 
                             QPushButton, QLabel, QFrame, QScrollArea, QGridLayout)
from PyQt6.QtGui import QFont, QIcon, QPixmap
from PyQt6.QtCore import Qt, QSize

class ControlCenter(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Sourceless Settings")
        self.resize(1100, 750)

        # Styling de bază pentru "Liquid Glass" și aspect Windows 11
        self.setStyleSheet("""
            QWidget {
                background-color: #1c1d25; /* Fundal întunecat */
                color: #e0e5ff;
                font-family: 'Inter', sans-serif;
            }
            /* Sidebar stânga */
            QFrame#sidebar {
                background-color: rgba(25, 27, 38, 0.7);
                border-right: 1px solid rgba(255, 255, 255, 0.05);
            }
            /* Butoane din sidebar */
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
            }
            /* Carduri în zona principală */
            QFrame.card {
                background-color: rgba(30, 32, 48, 0.6);
                border-radius: 12px;
                border: 1px solid rgba(255, 255, 255, 0.05);
            }
            QLabel.section_title {
                font-size: 18px;
                font-weight: bold;
                padding-bottom: 5px;
            }
            /* Butoane în interiorul cardurilor */
            QPushButton.card_action_btn {
                background-color: rgba(255, 255, 255, 0.05);
                border-radius: 6px;
                padding: 12px;
                text-align: left;
                border: none;
                font-size: 14px;
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

        # (Aici se pot adăuga elementele de profil utilizator, ca în mockup)
        lbl_profile = QLabel("Adrian Calin\nadrian.c@sourceless.com")
        lbl_profile.setStyleSheet("padding-bottom: 20px; font-weight: bold;")
        sidebar_layout.addWidget(lbl_profile)

        # Butoane Navigație (mockup)
        nav_buttons = [
            ("Home", "home"),
            ("System", "computer"),
            ("Bluetooth & devices", "bluetooth"),
            ("Network & internet", "network-wireless"),
            ("Personalization", "preferences-desktop-wallpaper")
        ]

        for text, icon_name in nav_buttons:
            btn = QPushButton(text)
            btn.setProperty("class", "sidebar_btn")
            btn.setIcon(QIcon.fromTheme(icon_name)) # Preia iconițele din tema sistemului
            btn.setIconSize(QSize(20, 20))
            btn.setCursor(Qt.CursorShape.PointingHandCursor)
            sidebar_layout.addWidget(btn)

        sidebar_layout.addStretch()
        main_layout.addWidget(sidebar)

        # -----------------------------------------------------
        # ZONA PRINCIPALĂ (Dreapta)
        # -----------------------------------------------------
        content_area = QScrollArea()
        content_area.setWidgetResizable(True)
        content_area.setFrameShape(QFrame.Shape.NoFrame)
        content_area.setStyleSheet("background: transparent;")
        
        content_widget = QWidget()
        content_layout = QVBoxLayout(content_widget)
        content_layout.setContentsMargins(40, 30, 40, 30)
        content_layout.setSpacing(20)

        # Titlu Pagină
        lbl_page_title = QLabel("Home")
        lbl_page_title.setStyleSheet("font-size: 28px; font-weight: bold;")
        content_layout.addWidget(lbl_page_title)

        # --- CARD: Recommended Settings ---
        lbl_rec = QLabel("Recommended settings")
        lbl_rec.setProperty("class", "section_title")
        content_layout.addWidget(lbl_rec)

        card_rec = QFrame()
        card_rec.setProperty("class", "card")
        card_rec_layout = QVBoxLayout(card_rec)

        btn_display = QPushButton("Display Configuration")
        btn_display.setProperty("class", "card_action_btn")
        btn_display.setIcon(QIcon.fromTheme("preferences-desktop-display-randr"))
        btn_display.clicked.connect(lambda: self.open_kcm("kcm_kscreen"))
        card_rec_layout.addWidget(btn_display)

        btn_wifi = QPushButton("Wi-Fi & Networks")
        btn_wifi.setProperty("class", "card_action_btn")
        btn_wifi.setIcon(QIcon.fromTheme("network-wireless"))
        btn_wifi.clicked.connect(lambda: self.open_kcm("kcm_networkmanagement"))
        card_rec_layout.addWidget(btn_wifi)
        
        content_layout.addWidget(card_rec)

        content_layout.addStretch()
        content_area.setWidget(content_widget)
        main_layout.addWidget(content_area)

    def open_kcm(self, kcm_module):
        # Rulează modulul KDE izolat, în fundal
        subprocess.Popen(["kcmshell6", kcm_module])

if __name__ == '__main__':
    app = QApplication(sys.argv)
    window = ControlCenter()
    window.show()
    sys.exit(app.exec())