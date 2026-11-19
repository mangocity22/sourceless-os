#!/usr/bin/bash
# Disable KDE DrKonqi crash handler popups globally
export KDE_DEBUG=1

# Enforce KWin software cursor inside Virtual Machines so hardware cursor
# planes (QXL/Virtio/VMware/VBoxVGA) do not desync on rotated/inverted outputs.
if systemd-detect-virt -q 2>/dev/null; then
    export KWIN_FORCE_SW_CURSOR=1
fi
