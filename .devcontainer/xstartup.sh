#!/usr/bin/env bash
# KasmVNC xstartup — launches XFCE desktop session
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE
dbus-launch --exit-with-session startxfce4
