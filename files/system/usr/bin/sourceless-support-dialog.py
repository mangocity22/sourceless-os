#!/usr/bin/env python3
import sys
from PyQt6.QtWidgets import QApplication, QDialog, QVBoxLayout, QHBoxLayout, QLabel, QPushButton
from PyQt6.QtGui import QPixmap, QFont
from PyQt6.QtCore import Qt

class SupportDialog(QDialog):
    def __init__(self):
        super().__init__()

        # Bara de titlu KWin clasica (fara text ca sa lase loc logo-ului)
        self.setWindowTitle(" ")
        self.setFixedSize(550, 240)

        # Magia CSS: Izolam fundalul DOAR pentru fereastra (QDialog)
        # Si fortam fundal transparent pentru text (QLabel) ca sa scapam de patratele negre
        self.setStyleSheet("""
            QDialog {
                background-color: #1a1b26;
            }
            QLabel {
                background: transparent;
                color: #a9b1d6;
            }
            QPushButton {
                font-family: 'Inter', sans-serif;
                font-size: 13px;
                font-weight: bold;
                border-radius: 6px;
                padding: 8px 24px;
                border: none;
                outline: none;
            }
            QPushButton#btnYes {
                background-color: #7aa2f7;
                color: #1a1b26;
            }
            QPushButton#btnYes:hover {
                background-color: #8db0f8;
            }
            QPushButton#btnNo {
                background-color: #414868;
                color: #c0caf5;
            }
            QPushButton#btnNo:hover {
                background-color: #565f89;
            }
        """)

        main_layout = QVBoxLayout()
        main_layout.setContentsMargins(30, 20, 30, 30)
        main_layout.setSpacing(20)

        # --- 1. LOGO LUNG SOURCELESS SUPPORT TEAM (Sus) ---
        # Spune-le celor de la design sa faca un logo orizontal (ex: 400x50px), cu fundal transparent (PNG)
        logo_label = QLabel()
        logo_pixmap = QPixmap("/usr/share/sourceless/Resources/sourceless-team.png") # Pune calea corecta aici
        if not logo_pixmap.isNull():
            logo_label.setPixmap(logo_pixmap.scaledToHeight(35, Qt.TransformationMode.SmoothTransformation))
        logo_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        main_layout.addWidget(logo_label)

        # --- 2. ICONITA CHEIE SI TEXTUL (Mijloc) ---
        content_layout = QHBoxLayout()
        content_layout.setSpacing(25)

        icon_label = QLabel()
        icon_pixmap = QPixmap("/usr/share/sourceless/Resources/support-key.svg") # Pune calea corecta aici
        if not icon_pixmap.isNull():
            icon_label.setPixmap(icon_pixmap.scaled(72, 72, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation))
        icon_label.setFixedSize(72, 72)
        content_layout.addWidget(icon_label)

        text_layout = QVBoxLayout()
        text_layout.setSpacing(5)

        font_normal = QFont("Inter", 12)
        font_bold = QFont("Inter", 12, QFont.Weight.Bold)

        lbl_msg1 = QLabel("An administrator would like to initiate a remote support session.")
        lbl_msg1.setFont(font_normal)
        lbl_msg1.setWordWrap(True)

        lbl_msg2 = QLabel("Do you approve the RustDesk connection?")
        lbl_msg2.setFont(font_bold)
        lbl_msg2.setWordWrap(True)

        text_layout.addWidget(lbl_msg1)
        text_layout.addWidget(lbl_msg2)
        text_layout.addStretch()

        content_layout.addLayout(text_layout)
        main_layout.addLayout(content_layout)

        # --- 3. BUTOANELE (Jos) ---
        btn_layout = QHBoxLayout()
        btn_layout.addStretch()

        btn_yes = QPushButton("Yes")
        btn_yes.setObjectName("btnYes")
        btn_yes.setFixedSize(110, 38)
        btn_yes.setCursor(Qt.CursorShape.PointingHandCursor)
        btn_yes.clicked.connect(self.accept)

        btn_no = QPushButton("No")
        btn_no.setObjectName("btnNo")
        btn_no.setFixedSize(110, 38)
        btn_no.setCursor(Qt.CursorShape.PointingHandCursor)
        btn_no.clicked.connect(self.reject)

        btn_layout.addWidget(btn_yes)
        btn_layout.addWidget(btn_no)

        main_layout.addLayout(btn_layout)
        self.setLayout(main_layout)

if __name__ == '__main__':
    app = QApplication(sys.argv)
    dialog = SupportDialog()
    
    # Returneaza 0 pentru Yes, 1 pentru No
    sys.exit(0 if dialog.exec() else 1)