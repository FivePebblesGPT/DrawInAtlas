"""Send an actual X11 key press/release to a native popup in software-display tests.

Window.push_input() does not dispatch Godot's native PopupMenu window events.
This test-only helper requires X11 and libXtst, but no window manager or pip packages.
"""
from __future__ import annotations

import ctypes as c
import sys


def main(keysym: str) -> None:
    x11 = c.CDLL("libX11.so.6")
    xtest = c.CDLL("libXtst.so.6")
    x11.XOpenDisplay.argtypes = [c.c_char_p]
    x11.XOpenDisplay.restype = c.c_void_p
    x11.XStringToKeysym.argtypes = [c.c_char_p]
    x11.XStringToKeysym.restype = c.c_ulong
    x11.XKeysymToKeycode.argtypes = [c.c_void_p, c.c_ulong]
    x11.XKeysymToKeycode.restype = c.c_ubyte
    xtest.XTestFakeKeyEvent.argtypes = [c.c_void_p, c.c_uint, c.c_int, c.c_ulong]
    x11.XSync.argtypes = [c.c_void_p, c.c_int]
    x11.XCloseDisplay.argtypes = [c.c_void_p]
    display = x11.XOpenDisplay(None)
    if not display:
        raise RuntimeError("No X11 test display")
    try:
        key = x11.XKeysymToKeycode(display, x11.XStringToKeysym(keysym.encode()))
        if not key:
            raise ValueError(f"Unknown X11 keysym: {keysym}")
        for pressed in (1, 0):
            if not xtest.XTestFakeKeyEvent(display, key, pressed, 0):
                raise RuntimeError("XTest key injection failed")
        x11.XSync(display, 0)
    finally:
        x11.XCloseDisplay(display)


if __name__ == "__main__":
    main(sys.argv[1])
