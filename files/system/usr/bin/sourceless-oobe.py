#!/usr/bin/env python3
"""SourceLess OS First-Boot OOBE (Windows-style initial user setup).

Full-screen PyQt6 setup wizard matching LockScreenUi.qml aesthetics.
Runs on first boot when /etc/sourceless/.oobe_completed does not exist,
creates the user's standard account via /usr/bin/sourceless-oobe-apply,
and hands off cleanly to the SDDM login screen.
"""

import os
import re
import subprocess
import sys

from PyQt6.QtCore import Qt, QThread, QTimer, QDateTime, pyqtSignal
from PyQt6.QtGui import QPixmap
from PyQt6.QtWidgets import (
    QApplication,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

RESERVED_USERS = {
    "root",
    "liveuser",
    "sourceless-setup",
    "daemon",
    "bin",
    "sys",
    "sync",
    "games",
    "man",
    "mail",
    "news",
    "uucp",
    "operator",
    "adm",
    "wheel",
    "nobody",
    "sddm",
    "systemd-network",
    "systemd-resolve",
    "polkitd",
    "dbus",
}

LOGO_PATHS = [
    "/usr/share/icons/hicolor/scalable/apps/sourceless-logo.svg",
    "/usr/share/pixmaps/sourceless-logo.png",
    "/usr/share/sourceless/Resources/sourceless-team.png",
]


class ApplyWorker(QThread):
    """Runs root provisioning off the UI thread."""

    finished_signal = pyqtSignal(bool, str)

    def __init__(self, fullname, username, hostname, password):
        super().__init__()
        self.fullname = fullname
        self.username = username
        self.hostname = hostname
        self.password = password

    def run(self):
        try:
            proc = subprocess.run(
                [
                    "sudo",
                    "-n",
                    "/usr/bin/sourceless-oobe-apply",
                    "--fullname",
                    self.fullname,
                    "--username",
                    self.username,
                    "--hostname",
                    self.hostname,
                ],
                input=f"{self.password}\n",
                capture_output=True,
                text=True,
                timeout=30,
            )
            if proc.returncode == 0:
                self.finished_signal.emit(True, "Workspace configured. Launching login screen...")
            else:
                err = (proc.stderr or proc.stdout or "Provisioning failed.").strip()
                self.finished_signal.emit(False, err)
        except Exception as exc:
            self.finished_signal.emit(False, str(exc))


class SourcelessOOBEWindow(QMainWindow):
    """Full-screen LockScreen-styled First-Boot OOBE window."""

    def __init__(self):
        super().__init__()
        self._username_edited = False
        self._setup_complete = False
        self._worker = None

        self.setWindowTitle("SourceLess OS — First-Boot Setup")
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint
        )

        self._build_ui()
        self._apply_styles()
        self._update_clock()

        self._clock_timer = QTimer(self)
        self._clock_timer.timeout.connect(self._update_clock)
        self._clock_timer.start(1000)

    def closeEvent(self, event):
        if not self._setup_complete:
            event.ignore()
            return
        super().closeEvent(event)

    def keyPressEvent(self, event):
        if event.key() in (Qt.Key.Key_Escape, Qt.Key.Key_F4) and (
            event.modifiers() & Qt.KeyboardModifier.AltModifier
        ):
            event.ignore()
            return
        super().keyPressEvent(event)

    def _find_logo(self):
        for p in LOGO_PATHS:
            if os.path.exists(p):
                return p
        return None

    def _build_ui(self):
        root = QWidget()
        root.setObjectName("oobeCanvas")
        self.setCentralWidget(root)

        outer = QVBoxLayout(root)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)

        # Top Cyber HUD Bar matching LockScreenUi.qml
        hud = QFrame()
        hud.setObjectName("cyberHud")
        hud.setFixedHeight(54)
        hud_layout = QHBoxLayout(hud)
        hud_layout.setContentsMargins(24, 0, 24, 0)
        hud_layout.setSpacing(12)

        logo_label = QLabel()
        logo_path = self._find_logo()
        if logo_path:
            pix = QPixmap(logo_path).scaled(
                24,
                24,
                Qt.AspectRatioMode.KeepAspectRatio,
                Qt.TransformationMode.SmoothTransformation,
            )
            logo_label.setPixmap(pix)
        hud_layout.addWidget(logo_label)

        brand_lbl = QLabel("SOURCELESS OS")
        brand_lbl.setObjectName("hudBrand")
        hud_layout.addWidget(brand_lbl)

        sep1 = QFrame()
        sep1.setObjectName("hudSep")
        sep1.setFixedSize(1, 16)
        hud_layout.addWidget(sep1)

        dot = QLabel()
        dot.setObjectName("hudDot")
        dot.setFixedSize(8, 8)
        hud_layout.addWidget(dot)

        sub_lbl = QLabel("FIRST BOOT // USER WORKSPACE SETUP")
        sub_lbl.setObjectName("hudSub")
        hud_layout.addWidget(sub_lbl)

        hud_layout.addStretch(1)

        self.date_lbl = QLabel()
        self.date_lbl.setObjectName("hudDate")
        hud_layout.addWidget(self.date_lbl)

        sep2 = QFrame()
        sep2.setObjectName("hudSep")
        sep2.setFixedSize(1, 16)
        hud_layout.addWidget(sep2)

        self.clock_lbl = QLabel()
        self.clock_lbl.setObjectName("hudClock")
        hud_layout.addWidget(self.clock_lbl)

        outer.addWidget(hud)

        # Centered Card Container
        center_wrap = QVBoxLayout()
        center_wrap.setContentsMargins(24, 24, 24, 24)
        center_wrap.addStretch(1)

        card_row = QHBoxLayout()
        card_row.addStretch(1)

        card_border = QFrame()
        card_border.setObjectName("cardGradientBorder")
        card_border.setFixedWidth(520)
        border_layout = QVBoxLayout(card_border)
        border_layout.setContentsMargins(2, 2, 2, 2)

        card = QFrame()
        card.setObjectName("oobeCard")
        card_layout = QVBoxLayout(card)
        card_layout.setContentsMargins(34, 30, 34, 28)
        card_layout.setSpacing(14)

        badge = QLabel("WELCOME TO SOURCELESS OS")
        badge.setObjectName("welcomeBadge")
        badge.setAlignment(Qt.AlignmentFlag.AlignCenter)
        card_layout.addWidget(badge, alignment=Qt.AlignmentFlag.AlignLeft)

        title = QLabel("Create Your Account")
        title.setObjectName("cardTitle")
        card_layout.addWidget(title)

        desc = QLabel(
            "Configure your personal workspace before entering SourceLess OS. "
            "Administrative root access remains locked unless explicitly enabled by Support."
        )
        desc.setObjectName("cardDesc")
        desc.setWordWrap(True)
        card_layout.addWidget(desc)

        card_layout.addSpacing(4)

        self.fullname_input = self._add_field(
            card_layout, "Full Name", "e.g. Alex Mercer"
        )
        self.fullname_input.textChanged.connect(self._on_fullname_changed)

        self.username_input = self._add_field(
            card_layout, "Username", "lowercase letters, digits, '-' or '_'"
        )
        self.username_input.textEdited.connect(self._on_username_edited)

        self.hostname_input = self._add_field(
            card_layout, "Device Name (Hostname)", "sourceless-pc", default_val="sourceless-pc"
        )

        pw_row = QHBoxLayout()
        pw_row.setSpacing(12)

        pw_col = QVBoxLayout()
        pw_col.setSpacing(5)
        pw_lbl = QLabel("Password (min 6 chars)")
        pw_lbl.setObjectName("fieldLabel")
        self.password_input = QLineEdit()
        self.password_input.setObjectName("oobeInput")
        self.password_input.setEchoMode(QLineEdit.EchoMode.Password)
        self.password_input.setPlaceholderText("Enter password")
        pw_col.addWidget(pw_lbl)
        pw_col.addWidget(self.password_input)

        cf_col = QVBoxLayout()
        cf_col.setSpacing(5)
        cf_lbl = QLabel("Confirm Password")
        cf_lbl.setObjectName("fieldLabel")
        self.confirm_input = QLineEdit()
        self.confirm_input.setObjectName("oobeInput")
        self.confirm_input.setEchoMode(QLineEdit.EchoMode.Password)
        self.confirm_input.setPlaceholderText("Repeat password")
        self.confirm_input.returnPressed.connect(self._handle_submit)
        cf_col.addWidget(cf_lbl)
        cf_col.addWidget(self.confirm_input)

        pw_row.addLayout(pw_col)
        pw_row.addLayout(cf_col)
        card_layout.addLayout(pw_row)

        self.show_pw_btn = QPushButton("Show Passwords")
        self.show_pw_btn.setObjectName("ghostBtn")
        self.show_pw_btn.setCheckable(True)
        self.show_pw_btn.toggled.connect(self._toggle_password_visibility)
        card_layout.addWidget(self.show_pw_btn, alignment=Qt.AlignmentFlag.AlignRight)

        self.status_lbl = QLabel("")
        self.status_lbl.setObjectName("statusError")
        self.status_lbl.setWordWrap(True)
        self.status_lbl.hide()
        card_layout.addWidget(self.status_lbl)

        self.submit_btn = QPushButton("Complete Setup & Continue")
        self.submit_btn.setObjectName("primaryBtn")
        self.submit_btn.setFixedHeight(44)
        self.submit_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self.submit_btn.clicked.connect(self._handle_submit)
        card_layout.addWidget(self.submit_btn)

        sec_note = QLabel("Standard User Account  |  Support Unlock: sudo sourceless-unlock")
        sec_note.setObjectName("secNote")
        sec_note.setAlignment(Qt.AlignmentFlag.AlignCenter)
        card_layout.addWidget(sec_note)

        border_layout.addWidget(card)
        card_row.addWidget(card_border)
        card_row.addStretch(1)

        center_wrap.addLayout(card_row)
        center_wrap.addStretch(1)
        outer.addLayout(center_wrap, stretch=1)

    def _add_field(self, parent_layout, label_text, placeholder, default_val=""):
        lbl = QLabel(label_text)
        lbl.setObjectName("fieldLabel")
        inp = QLineEdit()
        inp.setObjectName("oobeInput")
        inp.setPlaceholderText(placeholder)
        if default_val:
            inp.setText(default_val)
        parent_layout.addWidget(lbl)
        parent_layout.addWidget(inp)
        return inp

    def _apply_styles(self):
        self.setStyleSheet(
            """
            #oobeCanvas {
                background-color: #090B12;
            }
            #cyberHud {
                background-color: #0D101B;
                border-bottom: 1px solid rgba(115, 104, 247, 0.35);
            }
            #hudBrand {
                color: #E8ECFF;
                font-size: 13px;
                font-weight: 800;
                letter-spacing: 2px;
            }
            #hudSep {
                background-color: rgba(148, 155, 192, 0.3);
            }
            #hudDot {
                background-color: #A7FF52;
                border-radius: 4px;
            }
            #hudSub, #hudDate {
                color: #949BC0;
                font-size: 11px;
                font-weight: 600;
                letter-spacing: 1.4px;
            }
            #hudClock {
                color: #E8ECFF;
                font-size: 13px;
                font-weight: 700;
            }
            #cardGradientBorder {
                border-radius: 20px;
                background: qlineargradient(
                    x1:0, y1:0, x2:1, y2:1,
                    stop:0 #A7FF52, stop:0.5 #6E62FF, stop:1 #6054F2
                );
            }
            #oobeCard {
                background-color: #111524;
                border-radius: 18px;
            }
            #welcomeBadge {
                color: #A7FF52;
                background-color: rgba(167, 255, 82, 0.14);
                border: 1px solid rgba(167, 255, 82, 0.38);
                border-radius: 999px;
                padding: 4px 12px;
                font-size: 10px;
                font-weight: 700;
                letter-spacing: 1.5px;
            }
            #cardTitle {
                color: #E8ECFF;
                font-size: 23px;
                font-weight: 700;
            }
            #cardDesc {
                color: #949BC0;
                font-size: 12px;
            }
            #fieldLabel {
                color: #E8ECFF;
                font-size: 12px;
                font-weight: 600;
            }
            #oobeInput {
                background-color: #0A0D16;
                border: 1px solid rgba(148, 155, 192, 0.28);
                border-radius: 8px;
                padding: 9px 12px;
                color: #E8ECFF;
                font-size: 13px;
            }
            #oobeInput:focus {
                border: 1px solid #A7FF52;
            }
            #primaryBtn {
                background-color: #6054F2;
                border: 1px solid rgba(167, 255, 82, 0.3);
                border-radius: 10px;
                color: #FFFFFF;
                font-size: 14px;
                font-weight: 700;
            }
            #primaryBtn:hover {
                background-color: #7368F7;
            }
            #primaryBtn:disabled {
                background-color: rgba(96, 84, 242, 0.45);
                color: rgba(255, 255, 255, 0.6);
            }
            #ghostBtn {
                background: transparent;
                border: none;
                color: #A7FF52;
                font-size: 11px;
                font-weight: 600;
            }
            #statusError {
                color: #F2546D;
                font-size: 12px;
                font-weight: 600;
            }
            #statusSuccess {
                color: #A7FF52;
                font-size: 12px;
                font-weight: 600;
            }
            #secNote {
                color: #949BC0;
                font-size: 11px;
                padding-top: 4px;
            }
            """
        )

    def _update_clock(self):
        now = QDateTime.currentDateTime()
        self.date_lbl.setText(now.toString("ddd, dd MMM yyyy").upper())
        self.clock_lbl.setText(now.toString("HH:mm:ss"))

    def _on_fullname_changed(self, text):
        if self._username_edited:
            return
        slug = re.sub(r"[^a-z0-9_-]", "", text.strip().lower().replace(" ", ""))
        if slug and not re.match(r"^[a-z_]", slug):
            slug = "u" + slug
        self.username_input.setText(slug[:31])

    def _on_username_edited(self, _text):
        self._username_edited = True

    def _toggle_password_visibility(self, checked):
        mode = QLineEdit.EchoMode.Normal if checked else QLineEdit.EchoMode.Password
        self.password_input.setEchoMode(mode)
        self.confirm_input.setEchoMode(mode)
        self.show_pw_btn.setText("Hide Passwords" if checked else "Show Passwords")

    def _show_status(self, message, is_error=True):
        self.status_lbl.setObjectName("statusError" if is_error else "statusSuccess")
        self.status_lbl.style().unpolish(self.status_lbl)
        self.status_lbl.style().polish(self.status_lbl)
        self.status_lbl.setText(message)
        self.status_lbl.show()

    def _validate(self):
        fullname = self.fullname_input.text().strip()
        username = self.username_input.text().strip()
        hostname = self.hostname_input.text().strip().lower()
        pw = self.password_input.text()
        cf = self.confirm_input.text()

        if not fullname:
            return None, "Please enter your full name."
        if not re.match(r"^[a-z_][a-z0-9_-]{0,31}$", username):
            return None, "Username must start with a lowercase letter and use only a-z, 0-9, '-', or '_'."
        if username in RESERVED_USERS:
            return None, f"The username '{username}' is reserved by the system."
        if not re.match(r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", hostname):
            return None, "Hostname may contain lowercase letters, digits, and interior hyphens only."
        if len(pw) < 6:
            return None, "Password must be at least 6 characters long."
        if pw != cf:
            return None, "Passwords do not match."

        return (fullname, username, hostname, pw), None

    def _handle_submit(self):
        if self._worker is not None and self._worker.isRunning():
            return

        payload, err = self._validate()
        if err:
            self._show_status(err, is_error=True)
            return

        fullname, username, hostname, pw = payload
        self.submit_btn.setEnabled(False)
        self.submit_btn.setText("Provisioning Workspace...")
        self._show_status("Applying account configuration...", is_error=False)

        self._worker = ApplyWorker(fullname, username, hostname, pw)
        self._worker.finished_signal.connect(self._on_apply_finished)
        self._worker.start()

    def _on_apply_finished(self, ok, message):
        if ok:
            self._setup_complete = True
            self._show_status(message, is_error=False)
            QTimer.singleShot(1200, self.close)
        else:
            self.submit_btn.setEnabled(True)
            self.submit_btn.setText("Complete Setup & Continue")
            self._show_status(f"Setup failed: {message}", is_error=True)


def main():
    app = QApplication(sys.argv)
    win = SourcelessOOBEWindow()
    win.showFullScreen()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
