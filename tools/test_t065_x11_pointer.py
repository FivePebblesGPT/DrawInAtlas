#!/usr/bin/env python3
"""Targeted OS-pointer drag witness for T-065; requires X11 and python-xlib.

Uses the XTEST extension to deliver real mouse events to Godot, not direct
calls to Control._drop_data. Run on a disposable Xvfb desktop, never push CI.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import time

from Xlib import X, XK, display
from Xlib.ext import xtest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--screenshot", type=Path)
    args = parser.parse_args()
    dpy = display.Display()
    if not dpy.query_extension("XTEST").present:
        raise RuntimeError("XTEST extension is unavailable")
    with TemporaryDirectory(prefix="drawinatlas-t065-pointer-") as work:
        handshake = Path(work)
        env = os.environ.copy()
        env["T065_POINTER_HANDSHAKE"] = str(handshake)
        if args.screenshot:
            env["T065_POINTER_SCREENSHOT"] = str(args.screenshot)
        command = [args.godot, "--path", str(args.project), "--rendering-driver", "opengl3", "-s", "res://tests/asset_browser_atlas_pointer_native.gd"]
        process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            ready_path = handshake / "ready.json"
            start = time.monotonic()
            while not ready_path.exists() and time.monotonic() - start < 35 and process.poll() is None:
                time.sleep(0.05)
            if not ready_path.exists():
                raise RuntimeError("Godot did not publish drag coordinates")
            ready = json.loads(ready_path.read_text())
            source = tuple(round(v) for v in ready["source"])
            target = tuple(round(v) for v in ready["target"])
            print(f"Actual XTEST drag: {source} -> {target}", flush=True)
            def marker(name: str, timeout: float = 20.0) -> None:
                deadline = time.monotonic() + timeout
                while not (handshake / name).exists() and time.monotonic() < deadline:
                    if process.poll() is not None:
                        raise RuntimeError(f"Godot ended before {name}")
                    time.sleep(0.05)
                if not (handshake / name).exists():
                    raise TimeoutError(f"Timed out waiting for {name}")

            def move_to(point: tuple[int, int]) -> None:
                xtest.fake_input(dpy, X.MotionNotify, x=point[0], y=point[1])
                dpy.sync()

            def drag_to(destination: tuple[int, int], cancel_with_escape: bool = False) -> None:
                move_to(source)
                time.sleep(0.18)
                xtest.fake_input(dpy, X.ButtonPress, detail=1)
                dpy.sync()
                time.sleep(0.12)
                for step in range(1, 31):
                    fraction = step / 30.0
                    point = (round(source[0] + (destination[0] - source[0]) * fraction),
                             round(source[1] + (destination[1] - source[1]) * fraction))
                    move_to(point)
                    time.sleep(0.04)
                time.sleep(0.35)
                if cancel_with_escape:
                    escape_keycode = dpy.keysym_to_keycode(XK.string_to_keysym("Escape"))
                    xtest.fake_input(dpy, X.KeyPress, detail=escape_keycode)
                    dpy.sync()
                    time.sleep(0.15)
                    xtest.fake_input(dpy, X.KeyRelease, detail=escape_keycode)
                    dpy.sync()
                    time.sleep(0.15)
                xtest.fake_input(dpy, X.ButtonRelease, detail=1)
                dpy.sync()
                time.sleep(0.3)

            move_to(source)
            time.sleep(0.18)
            xtest.fake_input(dpy, X.ButtonPress, detail=1)
            dpy.sync()
            time.sleep(0.15)
            xtest.fake_input(dpy, X.ButtonRelease, detail=1)
            dpy.sync()
            time.sleep(0.2)
            (handshake / "clicked").write_text("done\n")
            marker("drag_ready")
            drag_to(target)
            (handshake / "dropped").write_text("done\n")
            marker("cancel_ready")
            invalid = tuple(round(v) for v in ready["invalid"])
            drag_to(invalid)
            (handshake / "cancelled").write_text("done\n")
            marker("escape_ready")
            drag_to(target, cancel_with_escape=True)
            (handshake / "escaped").write_text("done\n")
            output, _ = process.communicate(timeout=20)
            print(output)
            return process.returncode or 0
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()


if __name__ == "__main__":
    sys.exit(main())
