"""Move/click the actual X11 pointer in native popup tests."""
from __future__ import annotations

import ctypes as c
import sys


def main(x: int, y: int, click: bool) -> None:
    x11 = c.CDLL("libX11.so.6")
    xtest = c.CDLL("libXtst.so.6")
    x11.XOpenDisplay.argtypes = [c.c_char_p]
    x11.XOpenDisplay.restype = c.c_void_p
    x11.XSync.argtypes = [c.c_void_p, c.c_int]
    x11.XCloseDisplay.argtypes = [c.c_void_p]
    xtest.XTestFakeMotionEvent.argtypes = [c.c_void_p, c.c_int, c.c_int, c.c_int, c.c_ulong]
    xtest.XTestFakeButtonEvent.argtypes = [c.c_void_p, c.c_uint, c.c_int, c.c_ulong]
    display = x11.XOpenDisplay(None)
    if not display:
        raise RuntimeError("No X11 test display")
    try:
        if not xtest.XTestFakeMotionEvent(display, -1, x, y, 0):
            raise RuntimeError("XTest pointer motion failed")
        if click:
            for pressed in (1, 0):
                if not xtest.XTestFakeButtonEvent(display, 1, pressed, 0):
                    raise RuntimeError("XTest click failed")
        x11.XSync(display, 0)
    finally:
        x11.XCloseDisplay(display)


if __name__ == "__main__":
    main(int(sys.argv[1]), int(sys.argv[2]), sys.argv[3] == "click")
