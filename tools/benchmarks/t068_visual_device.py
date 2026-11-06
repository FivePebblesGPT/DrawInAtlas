#!/usr/bin/env python3
"""T-068 Linux Godot synthetic-frame/RSS witness; NOT event-to-photon latency.

Use --profile software under Xvfb/llvmpipe. --profile hardware requires an
independently non-software GL renderer and still cannot certify physical input,
display scan-out, VRAM or Windows. This tool never alters the app's raster path.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
GODOT_SCRIPT = ROOT / "tests/drawing_latency_stress_visual.gd"
SOURCES = (GODOT_SCRIPT, Path(__file__).resolve())
CASES = (("dab_4px", 4), ("dab_32px", 32), ("dab_64px", 64),
         ("long_4px", 4), ("cross_4px", 4))
SOFTWARE_MARKERS = ("llvmpipe", "softpipe", "swrast", "software rasterizer",
                    "swiftshader", "lavapipe", "virgl", "zink (llvmpipe")
TRIALS = 5
CHECKS = 81


def source_hashes() -> dict[str, str]:
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in SOURCES}


def status_memory(pid: int) -> dict[str, int] | None:
    """Return VmRSS/VmHWM in KiB, or None when the process has exited."""
    try:
        status = Path(f"/proc/{pid}/status").read_text(encoding="ascii")
    except (FileNotFoundError, ProcessLookupError):
        return None
    values: dict[str, int] = {}
    for line in status.splitlines():
        match = re.fullmatch(r"(VmRSS|VmHWM):\s+(\d+)\s+kB", line)
        if match:
            values[match.group(1)] = int(match.group(2))
    if set(values) != {"VmRSS", "VmHWM"} or values["VmHWM"] < values["VmRSS"]:
        return None
    return values


def gl_renderer() -> str | None:
    """Do not infer a physical device from Godot's API alone."""
    try:
        result = subprocess.run(["glxinfo", "-B"], text=True,
                                capture_output=True, timeout=15, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode:
        return None
    for line in result.stdout.splitlines():
        if line.strip().startswith("OpenGL renderer string:"):
            return line.split(":", 1)[1].strip() or None
    return None


def software_renderer(name: str) -> bool:
    return any(marker in name.lower() for marker in SOFTWARE_MARKERS)


def validate_hardware(renderer: str | None, adapter: str, environment: dict[str, str]) -> None:
    if not renderer or not adapter or software_renderer(renderer) or software_renderer(adapter):
        raise ValueError("A verified non-software OpenGL renderer and Godot adapter are required")
    if environment.get("LIBGL_ALWAYS_SOFTWARE", "").lower() not in ("", "0", "false"):
        raise ValueError("LIBGL_ALWAYS_SOFTWARE is enabled")
    if environment.get("GALLIUM_DRIVER", "").lower() in ("llvmpipe", "softpipe", "swrast"):
        raise ValueError("Software GALLIUM_DRIVER is enabled")


def check_samples(stats: Any) -> list[float]:
    if not isinstance(stats, dict) or set(stats) != {"median_ms", "p95_ms", "samples_ms"}:
        raise ValueError("Missing raw timing statistics")
    samples = stats["samples_ms"]
    if not isinstance(samples, list) or len(samples) != TRIALS or any(
        type(x) not in (float, int) or not math.isfinite(x) or x <= 0 for x in samples
    ):
        raise ValueError("Invalid timing samples")
    ordered = sorted(samples)
    for key, computed in (("median_ms", ordered[2]), ("p95_ms", ordered[4])):
        value = stats[key]
        if type(value) not in (float, int) or not math.isfinite(value) or abs(value - computed) > 0.00051:
            raise ValueError(f"Forged {key}")
    return samples


def validate_stress(stress: Any) -> None:
    if (not isinstance(stress, dict) or stress.get("schema") != "t068-native-stress-v1" or
        type(stress.get("checks")) is not int or stress["checks"] != CHECKS or
        type(stress.get("failures")) is not int or stress["failures"] != 0 or
        str(stress.get("driver", "")).lower() != "x11" or
        not isinstance(stress.get("renderer"), str) or not stress["renderer"] or
        not isinstance(stress.get("adapter"), str) or not stress["adapter"] or
        not isinstance(stress.get("engine"), dict) or
        not isinstance(stress.get("rows"), list) or len(stress["rows"]) != len(CASES)):
        raise ValueError("Invalid Godot framebuffer witness")
    if (stress["engine"].get("major") != 4 or stress["engine"].get("minor") != 8 or
        stress["engine"].get("status") != "beta2"):
        raise ValueError("Not the pinned Godot 4.8 family")
    for row, (name, width) in zip(stress["rows"], CASES):
        if (not isinstance(row, dict) or row.get("name") != name or
            row.get("world_width") != width or row.get("synthetic_gestures") != TRIALS):
            raise ValueError("Missing or changed brush workload")
        cpu = check_samples(row.get("cpu_dispatch"))
        frame = check_samples(row.get("event_to_frame_post_draw"))
        if any(f < c for c, f in zip(cpu, frame)):
            raise ValueError("Frame completed before CPU dispatch")


def validate(record: Any) -> None:
    if (not isinstance(record, dict) or record.get("schema") != "t068-visual-process-v1" or
        record.get("sources") != source_hashes() or record.get("platform") != "Linux" or
        record.get("profile") not in ("software", "hardware") or
        type(record.get("sample_interval_ms")) is not int or
        record["sample_interval_ms"] != 20 or
        not isinstance(record.get("machine"), str) or not record["machine"] or
        not isinstance(record.get("glxinfo_renderer"), (str, type(None)))):
        raise ValueError("Invalid process-witness envelope")
    validate_stress(record.get("stress"))
    memory = record.get("process_memory_kib")
    if not isinstance(memory, dict) or set(memory) != {"rss_samples", "hwm_samples", "rss_peak", "hwm_peak"}:
        raise ValueError("Missing memory samples")
    rss = memory["rss_samples"]
    hwm = memory["hwm_samples"]
    if (not isinstance(rss, list) or not isinstance(hwm, list) or len(rss) != len(hwm) or
        not rss or any(type(v) is not int or v <= 0 for v in rss + hwm) or
        any(h < r for h, r in zip(hwm, rss)) or
        any(b < a for a, b in zip(hwm, hwm[1:])) or
        memory["rss_peak"] != max(rss) or memory["hwm_peak"] != max(hwm)):
        raise ValueError("Invalid RSS/high-water series")
    if record["profile"] == "hardware":
        validate_hardware(record["glxinfo_renderer"], record["stress"]["adapter"], {})
    elif not (software_renderer(record["stress"]["adapter"]) or
              (record["glxinfo_renderer"] and software_renderer(record["glxinfo_renderer"]))):
        raise ValueError("Software profile lacks a software-renderer witness")
    if record.get("limitations") != [
        "Synthetic Godot X11 events and frame_post_draw, not physical event-to-photon timing",
        "RSS/HWM cover the entire Godot process; sampled every 20ms, not isolated raster allocations",
        "OpenGL adapter metadata is not VRAM measurement or Windows portability evidence",
    ]:
        raise ValueError("Limitations removed or changed")


def live(godot: Path, profile: str) -> dict[str, Any]:
    if platform.system() != "Linux" or not Path("/proc/self/status").is_file():
        raise RuntimeError("Linux /proc is required")
    if not godot.is_file():
        raise FileNotFoundError(f"Godot executable missing: {godot}")
    renderer = gl_renderer()
    if profile == "hardware":
        validate_hardware(renderer, renderer or "", dict(os.environ))
    with tempfile.TemporaryDirectory(prefix="t068-visual-process-") as directory:
        output = Path(directory) / "stress.json"
        log = Path(directory) / "godot.log"
        with log.open("wb") as log_file:
            proc = subprocess.Popen([
                str(godot.resolve()), "--path", str(ROOT), "--display-driver", "x11",
                "--rendering-driver", "opengl3", "--audio-driver", "Dummy",
                "--script", "res://tests/drawing_latency_stress_visual.gd", "--",
                "--output", str(output),
            ], stdout=log_file, stderr=subprocess.STDOUT,
                env={**os.environ, "GODOT_SILENCE_ROOT_WARNING": "1"})
            rss: list[int] = []
            hwm: list[int] = []
            deadline = time.monotonic() + 150
            try:
                while proc.poll() is None:
                    if time.monotonic() > deadline:
                        raise TimeoutError("Godot process exceeded 150 seconds")
                    snapshot = status_memory(proc.pid)
                    if snapshot is not None:
                        rss.append(snapshot["VmRSS"])
                        hwm.append(snapshot["VmHWM"])
                    time.sleep(0.02)
                proc.wait(timeout=5)
            except BaseException:
                proc.kill()
                proc.wait()
                raise
        if proc.returncode:
            raise RuntimeError(f"Godot exited {proc.returncode}: {log.read_text(errors='replace')[-2500:]}")
        if not output.is_file():
            raise RuntimeError("Godot did not produce framebuffer evidence")
        stress = json.loads(output.read_text(encoding="utf-8"))
        validate_stress(stress)
        if profile == "hardware":
            validate_hardware(renderer, stress["adapter"], dict(os.environ))
        if not rss:
            raise RuntimeError("No Godot process-memory samples recorded")
        result = {
            "schema": "t068-visual-process-v1", "sources": source_hashes(),
            "platform": platform.system(), "machine": platform.machine(), "profile": profile,
            "glxinfo_renderer": renderer, "sample_interval_ms": 20, "stress": stress,
            "process_memory_kib": {"rss_samples": rss, "hwm_samples": hwm,
                                   "rss_peak": max(rss), "hwm_peak": max(hwm)},
            "limitations": [
                "Synthetic Godot X11 events and frame_post_draw, not physical event-to-photon timing",
                "RSS/HWM cover the entire Godot process; sampled every 20ms, not isolated raster allocations",
                "OpenGL adapter metadata is not VRAM measurement or Windows portability evidence",
            ],
        }
        validate(result)
        return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, help="Godot 4.8 beta 2 Linux executable")
    parser.add_argument("--profile", choices=("software", "hardware"), default="software")
    parser.add_argument("--evidence", type=Path, help="Validate existing JSON instead of running")
    parser.add_argument("--output", type=Path, help="Write JSON evidence")
    args = parser.parse_args()
    if args.evidence:
        record = json.loads(args.evidence.read_text(encoding="utf-8"))
        validate(record)
        print("T068_VISUAL_PROCESS_REPLAY_PASSED")
        return
    if not args.godot or not args.output:
        parser.error("Live runs require --godot and --output")
    record = live(args.godot, args.profile)
    args.output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("T068_VISUAL_PROCESS_PASSED", len(record["stress"]["rows"]),
          record["process_memory_kib"]["hwm_peak"], "KiB HWM")


if __name__ == "__main__":
    main()
