#!/usr/bin/env python3
"""PyQt6 confirmation prompt displayed to the desktop user before starting a RustDesk support session."""

import sys
from PyQt6.QtWidgets import QApplication, QDialog, QVBoxLayout, QHBoxLayout, QLabel, QPushButton
from PyQt6.QtGui import QPixmap, QFont
from PyQt6.QtCore import Qt


class SupportDialog(QDialog):
    """Modal authorization dialog asking the user to approve or reject a remote support request."""

    def __init__(self):
        super().__init__()

        # Keep native KWin titlebar clean (blank title reserves space visually for header branding)
        self.setWindowTitle(" ")
        self.setFixedSize(550, 240)

        # Scope background color to QDialog and keep QLabel backgrounds transparent to avoid black label boxes
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

        # 1. Top Sourceless Support Team horizontal banner logo
        logo_label = QLabel()
        logo_pixmap = QPixmap("/usr/share/sourceless/Resources/sourceless-team.png")
        if not logo_pixmap.isNull():
            logo_label.setPixmap(logo_pixmap.scaledToHeight(35, Qt.TransformationMode.SmoothTransformation))
        logo_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        main_layout.addWidget(logo_label)

        # 2. Support key icon and confirmation prompt text
        content_layout = QHBoxLayout()
        content_layout.setSpacing(25)

        icon_label = QLabel()
        icon_pixmap = QPixmap("/usr/share/sourceless/Resources/support-key.svg")
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

        # 3. Bottom Yes/No action buttons
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

    # Exit 0 when approved (Yes), 1 when rejected or closed (No)
    sys.exit(0 if dialog.exec() else 1)
