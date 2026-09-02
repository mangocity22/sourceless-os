#!/usr/bin/env python3
# /usr/bin/sourceless-hotkey-listener.py
# Low-level kernel input event listener for Sourceless-OS Break-Glass recovery

import glob
import os
import select
import struct
import subprocess
import sys
import time

# Linux input_event 64-bit structure: timeval (16 bytes), uint16 type, uint16 code, int32 value
EVENT_FORMAT = "qqHHi"
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)

EV_KEY = 1

# Standard keycodes from linux/input-event-codes.h
KEY_LEFTCTRL = 29
KEY_RIGHTCTRL = 97
KEY_LEFTALT = 56
KEY_RIGHTALT = 100
KEY_LEFTSHIFT = 42
KEY_RIGHTSHIFT = 54
KEY_LEFTMETA = 125
KEY_RIGHTMETA = 126
KEY_F12 = 88
KEY_U = 22

CTRL_KEYS = {KEY_LEFTCTRL, KEY_RIGHTCTRL}
ALT_KEYS = {KEY_LEFTALT, KEY_RIGHTALT}
SHIFT_KEYS = {KEY_LEFTSHIFT, KEY_RIGHTSHIFT}
META_KEYS = {KEY_LEFTMETA, KEY_RIGHTMETA}

pressed_keys = set()
last_trigger_time = 0.0

def trigger_recovery():
    global last_trigger_time
    current_time = time.time()
    # Debounce trigger to avoid multiple rapid executions
    if current_time - last_trigger_time < 5.0:
        return
    last_trigger_time = current_time
    subprocess.Popen(["/usr/bin/bash", "/usr/bin/sourceless-unlock"], close_fds=True)

def evaluate_chord():
    has_ctrl = bool(pressed_keys & CTRL_KEYS)
    has_alt = bool(pressed_keys & ALT_KEYS)
    has_shift = bool(pressed_keys & SHIFT_KEYS)
    has_meta = bool(pressed_keys & META_KEYS)

    # Chord 1: Ctrl + Alt + Shift + F12
    if has_ctrl and has_alt and has_shift and (KEY_F12 in pressed_keys):
        trigger_recovery()
        return

    # Chord 2: Ctrl + Alt + Shift + U (safe from hypervisor/browser intercepts)
    if has_ctrl and has_alt and has_shift and (KEY_U in pressed_keys):
        trigger_recovery()
        return

    # Chord 3: Super + Alt + U
    if has_meta and has_alt and (KEY_U in pressed_keys):
        trigger_recovery()
        return

def main():
    epoll = select.epoll()
    fd_to_path = {}

    def attach_devices():
        for path in glob.glob("/dev/input/event*"):
            if path not in fd_to_path.values():
                try:
                    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
                    epoll.register(fd, select.EPOLLIN)
                    fd_to_path[fd] = path
                except (OSError, PermissionError):
                    pass

    attach_devices()
    last_device_scan = time.time()

    while True:
        # Rescan for new input devices every 5 seconds
        if time.time() - last_device_scan > 5.0:
            last_device_scan = time.time()
            attach_devices()

        try:
            events = epoll.poll(timeout=1.0)
        except IOError:
            continue

        for fd, event_mask in events:
            if event_mask & select.EPOLLIN:
                try:
                    raw_data = os.read(fd, EVENT_SIZE * 16)
                except OSError:
                    try:
                        epoll.unregister(fd)
                        os.close(fd)
                    except Exception:
                        pass
                    fd_to_path.pop(fd, None)
                    continue

                cursor = 0
                while cursor + EVENT_SIZE <= len(raw_data):
                    sec, usec, ev_type, ev_code, ev_val = struct.unpack_from(EVENT_FORMAT, raw_data, cursor)
                    cursor += EVENT_SIZE

                    if ev_type == EV_KEY:
                        if ev_val == 1:  # Key press
                            pressed_keys.add(ev_code)
                            evaluate_chord()
                        elif ev_val == 0:  # Key release
                            pressed_keys.discard(ev_code)

if __name__ == "__main__":
    main()