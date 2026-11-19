#!/usr/bin/env python3
"""Root-level local helper daemon for the SourceLess OS Anaconda WebUI installer.

Exposes a localhost HTTP API (127.0.0.1:18443) for:
  - Enforcing initial en_US.UTF-8 locale, US keyboard, and locked root state via Anaconda D-Bus.
  - Inspecting physical target disks via lsblk.
  - Persisting user-selected maximum disk allocation (GiB) to /run/anaconda/sourceless_max_disk_gib
    for enforcement by the Blivet partitioning hook.
"""

import json
import os
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 18443
BUS_ADDR_FILE = "/run/anaconda/bus.address"
LIMIT_FILE = "/run/anaconda/sourceless_max_disk_gib"
DEFAULTS_FLAG = "/run/anaconda/.sourceless_defaults_applied"

_INIT_LOCK = threading.Lock()


def read_anaconda_bus_address():
    """Return the Anaconda private D-Bus address if available."""
    if not os.path.exists(BUS_ADDR_FILE):
        return None
    try:
        with open(BUS_ADDR_FILE, "r", encoding="utf-8") as fh:
            addr = fh.read().strip()
        if addr.startswith("DBUS_SESSION_BUS_ADDRESS="):
            addr = addr.split("=", 1)[1].strip().strip("'\"")
        return addr or None
    except OSError:
        return None


def _run_gdbus(bus_addr, dest, obj_path, iface, method, *args):
    """Invoke a D-Bus method on the Anaconda bus without raising on failure."""
    cmd = [
        "gdbus",
        "call",
        "--address",
        bus_addr,
        "--dest",
        dest,
        "--object-path",
        obj_path,
        "--method",
        f"{iface}.{method}",
        *args,
    ]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        return res.returncode == 0
    except Exception:
        return False


def apply_installer_defaults_once():
    """Set default language (en_US.UTF-8), US keyboard, and locked root once per boot."""
    with _INIT_LOCK:
        if os.path.exists(DEFAULTS_FLAG):
            return {"applied": False, "reason": "already_applied"}

        bus_addr = read_anaconda_bus_address()
        if not bus_addr:
            return {"applied": False, "reason": "bus_unavailable"}

        loc_dest = "org.fedoraproject.Anaconda.Modules.Localization"
        loc_path = "/org/fedoraproject/Anaconda/Modules/Localization"
        loc_ok = _run_gdbus(bus_addr, loc_dest, loc_path, loc_dest, "SetLanguage", "en_US.UTF-8")
        _run_gdbus(bus_addr, loc_dest, loc_path, loc_dest, "SetXLayouts", "['us']")
        _run_gdbus(bus_addr, loc_dest, loc_path, loc_dest, "SetVirtualConsoleKeymap", "us")

        usr_dest = "org.fedoraproject.Anaconda.Modules.Users"
        usr_path = "/org/fedoraproject/Anaconda/Modules/Users"
        usr_ok = _run_gdbus(bus_addr, usr_dest, usr_path, usr_dest, "SetIsRootAccountLocked", "true")
        _run_gdbus(bus_addr, usr_dest, usr_path, usr_dest, "SetIsRootEnabled", "false")

        if loc_ok or usr_ok:
            os.makedirs(os.path.dirname(DEFAULTS_FLAG), exist_ok=True)
            with open(DEFAULTS_FLAG, "w", encoding="utf-8") as fh:
                fh.write("1\n")
            return {"applied": True, "localization": loc_ok, "users": usr_ok}

        return {"applied": False, "reason": "dbus_calls_failed"}


def get_disk_info():
    """Return physical candidate disks and any currently persisted disk size limit."""
    disks = []
    try:
        res = subprocess.run(
            ["lsblk", "-J", "-b", "-d", "-o", "NAME,SIZE,TYPE,RM,MODEL"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if res.returncode == 0:
            data = json.loads(res.stdout)
            for dev in data.get("blockdevices", []):
                name = str(dev.get("name") or "")
                dtype = str(dev.get("type") or "")
                if dtype != "disk":
                    continue
                if name.startswith(("loop", "zram", "sr", "ram")):
                    continue
                size_bytes = int(dev.get("size") or 0)
                if size_bytes <= 0:
                    continue
                disks.append(
                    {
                        "name": name,
                        "path": f"/dev/{name}",
                        "size_bytes": size_bytes,
                        "size_gib": round(size_bytes / (1024 ** 3), 2),
                        "size_gb": round(size_bytes / (1000 ** 3), 2),
                        "removable": bool(dev.get("rm")),
                        "model": (dev.get("model") or "").strip(),
                    }
                )
    except Exception:
        pass

    current_limit = None
    if os.path.exists(LIMIT_FILE):
        try:
            with open(LIMIT_FILE, "r", encoding="utf-8") as fh:
                current_limit = float(fh.read().strip())
        except Exception:
            current_limit = None

    return {"disks": disks, "limit_gib": current_limit}


def set_disk_limit(limit_gib):
    """Persist or clear /run/anaconda/sourceless_max_disk_gib."""
    os.makedirs("/run/anaconda", exist_ok=True)
    if limit_gib is None:
        if os.path.exists(LIMIT_FILE):
            os.remove(LIMIT_FILE)
        return {"ok": True, "limit_gib": None}

    val = float(limit_gib)
    if val <= 0:
        if os.path.exists(LIMIT_FILE):
            os.remove(LIMIT_FILE)
        return {"ok": True, "limit_gib": None}

    tmp_path = f"{LIMIT_FILE}.tmp"
    with open(tmp_path, "w", encoding="utf-8") as fh:
        fh.write(f"{round(val, 2)}\n")
    os.replace(tmp_path, LIMIT_FILE)
    return {"ok": True, "limit_gib": round(val, 2)}


class InstallerHelperHandler(BaseHTTPRequestHandler):
    """HTTP request handler with CORS support for Cockpit/WebUI requests."""

    def log_message(self, format, *args):
        """Suppress noisy stderr request logs."""
        return

    def _send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Cache-Control", "no-store")

    def _send_json(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self._send_cors_headers()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self._send_cors_headers()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        if self.path.rstrip("/") == "/disk-info":
            self._send_json(200, get_disk_info())
            return
        if self.path.rstrip("/") == "/health":
            self._send_json(200, {"status": "ok"})
            return
        self._send_json(404, {"error": "not_found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length > 0 else b"{}"
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except Exception:
            self._send_json(400, {"error": "invalid_json"})
            return

        path = self.path.rstrip("/")
        if path == "/set-disk-limit":
            try:
                res = set_disk_limit(body.get("limit_gib"))
                self._send_json(200, res)
            except Exception as exc:
                self._send_json(400, {"error": str(exc)})
            return

        if path == "/init-defaults":
            res = apply_installer_defaults_once()
            self._send_json(200, res)
            return

        self._send_json(404, {"error": "not_found"})


def _background_dbus_bootstrap():
    """Wait for Anaconda's private D-Bus socket and apply defaults automatically."""
    for _ in range(120):
        res = apply_installer_defaults_once()
        if res.get("applied") or res.get("reason") == "already_applied":
            return
        time.sleep(1)


def main():
    os.makedirs("/run/anaconda", exist_ok=True)
    threading.Thread(target=_background_dbus_bootstrap, daemon=True).start()
    server = ThreadingHTTPServer((HOST, PORT), InstallerHelperHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
