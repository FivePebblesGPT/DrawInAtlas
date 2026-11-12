#!/usr/bin/env python3
"""T-105 Linux standalone Drawing export process residency and launch CPU screen.

This measures the *exported Godot application process*, not a Python/ctypes
native kernel worker or GPU VRAM. It does not synthesize a Windows pass.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import resource
import shutil
import subprocess
import tempfile
import threading
import time
from typing import Any

from t068_release_gate import check_launch_log, inspect_distribution, inspect_stage

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools/benchmarks/t105_release_residency.py"
RELEASE_GATE = ROOT / "tools/benchmarks/t068_release_gate.py"
LIMITATIONS = (
    "Linux /proc VmRSS/VmHWM of isolated exported Godot process, not detached native worker",
    "OS CPU includes startup and idle --quit-after frames, NOT a 96px Brush gesture",
    "Xvfb/Dummy/headless process memory cannot determine physical GPU VRAM residency",
    "Windows/MSVC and real Windows exported launch remain NOT TESTED until separately run",
)


def digest(path: Path) -> str:
    """SHA-256 of actual input bytes."""
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def nearest(values: list[float], p: float) -> float:
    """Compute nearest-rank percentile for finite nonnegative observations."""
    if not values or any(not math.isfinite(v) or v < 0 for v in values):
        raise ValueError("Missing or invalid measurement")
    return sorted(values)[math.ceil(len(values) * p) - 1]


def read_status(pid: int) -> dict[str, int]:
    """Read Linux kernel KiB RSS and HWM while the export is alive."""
    values: dict[str, int] = {}
    for line in Path(f"/proc/{pid}/status").read_text(encoding="ascii").splitlines():
        key, _, text = line.partition(":")
        if key in ("VmRSS", "VmHWM"):
            parts = text.split()
            if len(parts) != 2 or parts[1] != "kB":
                raise ValueError("Non-kilobyte Linux memory status")
            values[key] = int(parts[0])
    if set(values) != {"VmRSS", "VmHWM"} or min(values.values()) <= 0:
        raise ValueError("Missing RSS/HWM in live Godot process")
    return values


def launch_once(distribution: Path, *, frames: int = 120, timeout: int = 45) -> dict[str, Any]:
    """Launch a clean copied release, collect direct-child CPU and RSS/HWM.

    Parameters
    ----------
    distribution : Path
        Validated release containing ``Drawing.x86_64`` and ``Drawing.pck``.
    frames : int
        Engine frames to run before automatic shutdown; CPU is idle/startup,
        not an input-to-visible Brush workload.
    timeout : int
        Hard process watchdog in seconds.
    """
    if platform.system() != "Linux" or frames < 5 or timeout < 1:
        raise ValueError("Linux export launch parameters invalid")
    with tempfile.TemporaryDirectory(prefix="t105-export-") as temporary:
        base = Path(temporary)
        for name in ("home", "data", "config", "cache", "work", "distribution"):
            (base / name).mkdir()
        for name in ("Drawing.x86_64", "Drawing.pck"):
            shutil.copy2(distribution / name, base / "distribution" / name)
        env = {**os.environ, "HOME": str(base / "home"),
               "XDG_DATA_HOME": str(base / "data"),
               "XDG_CONFIG_HOME": str(base / "config"),
               "XDG_CACHE_HOME": str(base / "cache"),
               "GODOT_SILENCE_ROOT_WARNING": "1"}
        env.pop("GODOT_PROJECT_PATH", None)
        before = resource.getrusage(resource.RUSAGE_CHILDREN)
        start = time.perf_counter()
        proc = subprocess.Popen([str(base / "distribution" / "Drawing.x86_64"),
                                 "--headless", "--quit-after", str(frames)],
                                cwd=base / "work", env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True)
        peaks: list[dict[str, int]] = []
        sampling_errors: list[str] = []
        stop = threading.Event()
        def monitor() -> None:
            while not stop.is_set():
                try:
                    peaks.append(read_status(proc.pid))
                except (FileNotFoundError, ProcessLookupError):
                    break
                except ValueError as exc:
                    # /proc may expose empty VmRSS just after exec or while
                    # the process becomes a zombie. Require valid samples later.
                    if str(exc) != "Missing RSS/HWM in live Godot process":
                        sampling_errors.append(str(exc))
                        break
                stop.wait(0.005)
        watcher = threading.Thread(target=monitor, daemon=True)
        watcher.start()
        try:
            out, err = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            proc.kill()
            proc.communicate()
            raise RuntimeError("Export launch exceeded watchdog") from exc
        finally:
            stop.set()
            watcher.join(timeout=3)
        elapsed = (time.perf_counter() - start) * 1000
        after = resource.getrusage(resource.RUSAGE_CHILDREN)
        leaks = check_launch_log(out + "\n" + err, proc.returncode)
        if sampling_errors:
            raise RuntimeError("Invalid Godot memory sampler: " + sampling_errors[0])
        if not peaks:
            raise RuntimeError("Godot process exited before any /proc memory sample")
        return {"returncode": proc.returncode, "sample_count": len(peaks),
                "elapsed_ms": round(elapsed, 3),
                "cpu_user_ms": round((after.ru_utime - before.ru_utime) * 1000, 3),
                "cpu_system_ms": round((after.ru_stime - before.ru_stime) * 1000, 3),
                "rss_peak_kib": max(row["VmRSS"] for row in peaks),
                "hwm_peak_kib": max(row["VmHWM"] for row in peaks),
                "recognized_godot_shutdown_leaks": leaks}


def measure(stage: Path, distribution: Path, runs: int = 3, frames: int = 120) -> dict[str, Any]:
    """Build a source-pinned, replayable, deliberately incomplete portability report."""
    if platform.system() != "Linux" or not 2 <= runs <= 10:
        raise ValueError("Linux process and at least two trials required")
    stage_info = inspect_stage(stage)
    release_info = inspect_distribution(distribution, "linux")
    observations = [launch_once(distribution, frames=frames) for _ in range(runs)]
    keys = ("elapsed_ms", "cpu_user_ms", "cpu_system_ms", "rss_peak_kib", "hwm_peak_kib")
    result = {"schema": 1, "ticket": "T-105", "platform": "linux-x86_64",
              "source_sha256": {str(path.relative_to(ROOT)): digest(path)
                                for path in (SOURCE, RELEASE_GATE)},
              "stage": stage_info, "release": release_info,
              "engine": "4.8.beta3.official.c51ff06e8", "frames": frames,
              "runs": observations,
              "summary": {key: {"p50": nearest([float(r[key]) for r in observations], 0.5),
                                "p95": nearest([float(r[key]) for r in observations], 0.95),
                                "max": max(float(r[key]) for r in observations)}
                          for key in keys},
              "windows": {"status": "not_tested"},
              "vram": {"status": "not_measured"},
              "complete": False, "limitations": list(LIMITATIONS)}
    validate(result)
    return result


def validate(result: Any) -> None:
    """Reject missing observations, forged percentiles, or unsupported full-pass claims."""
    if (type(result) is not dict or set(result) != {
        "schema", "ticket", "platform", "source_sha256", "stage", "release",
        "engine", "frames", "runs", "summary", "windows", "vram", "complete", "limitations"}
        or result["schema"] != 1 or result["ticket"] != "T-105" or
        result["platform"] != "linux-x86_64" or result["engine"] != "4.8.beta3.official.c51ff06e8" or
        result["source_sha256"] != {str(p.relative_to(ROOT)): digest(p)
                                    for p in (SOURCE, RELEASE_GATE)} or
        result["windows"] != {"status": "not_tested"} or
        result["vram"] != {"status": "not_measured"} or
        result["complete"] is not False or result["limitations"] != list(LIMITATIONS) or
        not isinstance(result["stage"], dict) or
        type(result["stage"].get("file_count")) is not int or
        result["stage"]["file_count"] < 20 or
        type(result["stage"].get("font_license_sha256")) is not str or
        len(result["stage"]["font_license_sha256"]) != 64 or
        result["release"].get("platform") != "linux" or
        result["release"].get("native_extension_shipped") is not False or
        result["release"].get("inspection") != "structure_only" or
        type(result["frames"]) is not int or result["frames"] < 5 or
        not isinstance(result["runs"], list) or not 2 <= len(result["runs"]) <= 10):
        raise ValueError("Incomplete or falsified Linux-only T-105 report")
    for item in ("binary", "pack"):
        record = result["release"].get(item, {})
        if (not isinstance(record, dict) or type(record.get("size")) is not int or
            record["size"] < (4096 if item == "binary" else 64) or
            record.get("name") != ("Drawing.x86_64" if item == "binary" else "Drawing.pck") or
            not isinstance(record.get("sha256"), str) or
            len(record["sha256"]) != 64 or
            any(c not in "0123456789abcdef" for c in record["sha256"])):
            raise ValueError("Missing exact release binary/pack digest")
    keys = ("elapsed_ms", "cpu_user_ms", "cpu_system_ms", "rss_peak_kib", "hwm_peak_kib")
    for row in result["runs"]:
        if (not isinstance(row, dict) or set(row) != {
            "returncode", "sample_count", "recognized_godot_shutdown_leaks", *keys}
            or row["returncode"] != 0 or
            type(row["sample_count"]) is not int or row["sample_count"] < 1 or
            type(row["recognized_godot_shutdown_leaks"]) is not int or
            row["recognized_godot_shutdown_leaks"] < 0 or
            any(type(row[k]) not in (float, int) or not math.isfinite(row[k]) or row[k] < 0
                for k in keys) or
            row["rss_peak_kib"] <= 0 or row["hwm_peak_kib"] < row["rss_peak_kib"] or
            row["elapsed_ms"] <= 0):
            raise ValueError("Missing or invalid process measurement")
    if set(result["summary"]) != set(keys):
        raise ValueError("Missing summary metrics")
    for key in keys:
        vals = [float(r[key]) for r in result["runs"]]
        if result["summary"][key] != {
            "p50": nearest(vals, 0.5), "p95": nearest(vals, 0.95), "max": max(vals)}:
            raise ValueError("Altered T-105 process percentile")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path)
    parser.add_argument("--distribution", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--frames", type=int, default=120)
    args = parser.parse_args()
    if args.verify:
        validate(json.loads(args.output.read_text(encoding="utf-8")))
        print("T105_LINUX_RELEASE_REPLAY_PASSED: release CPU/RSS verified; Windows and VRAM open")
        return
    if not args.stage or not args.distribution:
        parser.error("--stage and --distribution required for live test")
    result = measure(args.stage, args.distribution, args.runs, args.frames)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("T105_LINUX_RELEASE_PASSED: isolated standalone CPU/RSS, Windows/VRAM not tested")


if __name__ == "__main__":
    main()
