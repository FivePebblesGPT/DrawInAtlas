#!/usr/bin/env python3
"""T-105: Windows exported Drawing app launch, process CPU and peak working set.

Execute on real Windows x64 after a native-free Drawing export. Headless launch
and OS memory are not a physical GPU memory measurement or Brush gesture.
"""
from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
import json
import math
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import threading
import tempfile
import time
from typing import Any

from t068_release_gate import check_launch_log, inspect_distribution


def nearest(values: list[float], fraction: float) -> float:
    """Nearest-rank quantile without Linux-only resource dependencies."""
    if not values or any(not math.isfinite(v) or v < 0 for v in values):
        raise ValueError("Invalid Windows process measurements")
    return sorted(values)[math.ceil(len(values) * fraction) - 1]


class ProcessMemoryCounters(ctypes.Structure):
    """PSAPI PROCESS_MEMORY_COUNTERS as defined by Windows SDK."""
    _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                ("PeakWorkingSetSize", ctypes.c_size_t),
                ("WorkingSetSize", ctypes.c_size_t),
                ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                ("PagefileUsage", ctypes.c_size_t),
                ("PeakPagefileUsage", ctypes.c_size_t)]


def filetime_ms(value: wintypes.FILETIME) -> float:
    """Convert Windows 100ns CPU FILETIME ticks to milliseconds."""
    return ((int(value.dwHighDateTime) << 32) + int(value.dwLowDateTime)) / 10_000.0


def launch_once(directory: Path, *, frames: int = 120, timeout: int = 45) -> dict[str, Any]:
    """Run a copied PCK/PE from a clean profile and read Windows process counters."""
    if sys.platform != "win32" or frames < 5 or timeout < 1:
        raise RuntimeError("Native Windows launch required")
    with tempfile.TemporaryDirectory(prefix="t105-windows-export-") as temporary:
        base = Path(temporary)
        for folder in ("profile", "cache", "data", "work", "distribution"):
            (base / folder).mkdir()
        for filename in ("Drawing.exe", "Drawing.pck"):
            shutil.copy2(directory / filename, base / "distribution" / filename)
        env = {**os.environ, "USERPROFILE": str(base / "profile"),
               "APPDATA": str(base / "data"),
               "LOCALAPPDATA": str(base / "cache"),
               "GODOT_SILENCE_ROOT_WARNING": "1"}
        env.pop("GODOT_PROJECT_PATH", None)
        start = time.perf_counter()
        proc = subprocess.Popen([str(base / "distribution/Drawing.exe"),
                                 "--headless", "--quit-after", str(frames)],
                                cwd=base / "work", env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        handle = wintypes.HANDLE(int(proc._handle))
        psapi = ctypes.WinDLL("psapi", use_last_error=True)
        psapi.GetProcessMemoryInfo.argtypes = (wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD)
        psapi.GetProcessMemoryInfo.restype = wintypes.BOOL
        peaks: list[int] = []
        stop = threading.Event()
        def monitor() -> None:
            while not stop.is_set():
                counter = ProcessMemoryCounters()
                counter.cb = ctypes.sizeof(counter)
                if psapi.GetProcessMemoryInfo(handle, ctypes.byref(counter), counter.cb):
                    if counter.PeakWorkingSetSize > 0:
                        peaks.append(int(counter.PeakWorkingSetSize))
                elif proc.poll() is not None:
                    break
                stop.wait(0.01)
        watcher = threading.Thread(target=monitor, daemon=True)
        watcher.start()
        try:
            out, err = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            proc.kill()
            proc.communicate()
            raise RuntimeError("Windows standalone launch timed out") from exc
        finally:
            stop.set()
            watcher.join(timeout=3)
        elapsed = (time.perf_counter() - start) * 1000
        if not peaks:
            raise RuntimeError("Windows PE exited without OS working-set observations")
        kernel, user = wintypes.FILETIME(), wintypes.FILETIME()
        creation, exit_time = wintypes.FILETIME(), wintypes.FILETIME()
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.GetProcessTimes.argtypes = (wintypes.HANDLE, ctypes.c_void_p,
                                            ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
        kernel32.GetProcessTimes.restype = wintypes.BOOL
        if not kernel32.GetProcessTimes(handle, ctypes.byref(creation), ctypes.byref(exit_time),
                                        ctypes.byref(kernel), ctypes.byref(user)):
            raise OSError(ctypes.get_last_error(), "Windows process CPU query failed")
        leaks = check_launch_log(out + "\n" + err, proc.returncode)
        return {"returncode": proc.returncode, "elapsed_ms": round(elapsed, 3),
                "cpu_user_ms": round(filetime_ms(user), 3),
                "cpu_system_ms": round(filetime_ms(kernel), 3),
                "peak_working_set_bytes": max(peaks),
                "recognized_godot_shutdown_leaks": leaks}


def measure(distribution: Path, runs: int = 3) -> dict[str, Any]:
    """Produce a Windows-only process-residency report; VRAM remains unknown."""
    if sys.platform != "win32" or platform.machine().lower() not in ("amd64", "x86_64"):
        raise RuntimeError("Actual Windows x64 host required")
    if not 2 <= runs <= 10:
        raise ValueError("At least two Windows runs required")
    binary = inspect_distribution(distribution, "windows")
    measurements = [launch_once(distribution) for _ in range(runs)]
    return {"schema": 1, "ticket": "T-105", "platform": "windows-x86_64",
            "release": binary, "runs": measurements,
            "summary": {key: {"p50": nearest([float(row[key]) for row in measurements], 0.5),
                              "p95": nearest([float(row[key]) for row in measurements], 0.95)}
                        for key in ("elapsed_ms", "cpu_user_ms", "cpu_system_ms", "peak_working_set_bytes")},
            "vram": "not_measured", "physical_pointer_latency": "not_measured",
            "limitation": "Headless Windows exported Godot process; no GPU VRAM or full Brush gesture"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--distribution", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = measure(args.distribution)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("T105_WINDOWS_RELEASE_PASSED: isolated PE/PCK CPU and OS working set; VRAM open")


if __name__ == "__main__":
    main()
