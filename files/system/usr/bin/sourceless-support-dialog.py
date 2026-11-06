#!/usr/bin/env python3
import sys
from PyQt6.QtWidgets import QApplication, QDialog, QVBoxLayout, QLabel, QPushButton, QHBoxLayout
from PyQt6.QtGui import QIcon, QPixmap, QFont
from PyQt6.QtCore import Qt

class SupportDialog(QDialog):
    def __init__(self):
        super().__init__()

        # --- Setari Fereastra ---
        self.setWindowTitle("Sourceless Support Team")
        # Poti folosi o imagine lunga pentru titlu daca elimini bara de sus a sistemului
        # self.setWindowFlags(Qt.WindowType.FramelessWindowHint)
        self.setFixedSize(500, 200) # Dimensiune mai mare si aerisita

        # --- Fundal custom (optional) ---
        # self.setStyleSheet("background-image: url(/cale/catre/fundal-sourceless.png); color: white;")
        self.setStyleSheet("background-color: #1a1b26; color: #a9b1d6;")

        layout = QVBoxLayout()
        layout.setContentsMargins(30, 30, 30, 30) # Spatiere generoasa (aerisire)

        # --- Zona Iconita + Text ---
        top_layout = QHBoxLayout()

        # Iconita Cheie Fixa
        icon_label = QLabel()
        pixmap = QPixmap("/usr/share/sourceless/Resources/support-key.svg") # 
        # Daca pixmap-ul nu se incarca, poti folosi o iconita din sistem
        # icon = QIcon.fromTheme("preferences-system")
        # pixmap = icon.pixmap(64, 64)
        icon_label.setPixmap(pixmap.scaled(64, 64, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation))
        icon_label.setFixedSize(80, 80)
        top_layout.addWidget(icon_label)

        # Textul
        text_layout = QVBoxLayout()
        msg_font = QFont("Inter", 12) # Font custom

        lbl_msg1 = QLabel("An administrator would like to initiate a remote support session.")
        lbl_msg1.setFont(msg_font)
        lbl_msg1.setWordWrap(True)

        lbl_msg2 = QLabel("Do you approve the RustDesk connection?")
        lbl_msg2.setFont(msg_font)
        lbl_msg2.setWordWrap(True)
        lbl_msg2.setStyleSheet("margin-top: 10px; font-weight: bold;")

        text_layout.addWidget(lbl_msg1)
        text_layout.addWidget(lbl_msg2)
        text_layout.addStretch()

        top_layout.addLayout(text_layout)
        layout.addLayout(top_layout)

        # --- Zona Butoane ---
        btn_layout = QHBoxLayout()
        btn_layout.addStretch()

        btn_yes = QPushButton("Yes")
        btn_yes.setFixedSize(100, 35)
        # Stil custom pentru butoane
        btn_yes.setStyleSheet("background-color: #7aa2f7; color: #15161e; font-weight: bold; border-radius: 5px;")
        btn_yes.clicked.connect(self.accept)

        btn_no = QPushButton("No")
        btn_no.setFixedSize(100, 35)
        btn_no.setStyleSheet("background-color: #414868; color: #c0caf5; font-weight: bold; border-radius: 5px;")
        btn_no.clicked.connect(self.reject)

        btn_layout.addWidget(btn_yes)
        btn_layout.addWidget(btn_no)

        layout.addLayout(btn_layout)
        self.setLayout(layout)

if __name__ == '__main__':
    app = QApplication(sys.argv)
    
    # Fortam utilizarea unei teme specifice daca este necesar
    # app.setStyle("kvantum")
    
    dialog = SupportDialog()
    
    # Returnam 0 pentru Yes, 1 pentru No (comportament similar kdialog)
    if dialog.exec():
        sys.exit(0)
    else:
        sys.exit(1)