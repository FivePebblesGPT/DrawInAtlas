#!/usr/bin/env python3
"""T-068 opt-in X11 software-frame jitter with a bounded external CPU load.

Comparisons are sequential and not randomized; p95 is a five-sample order
statistic. This is NOT physical input-to-photon latency, hardware or VRAM.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import subprocess
import sys
from pathlib import Path
from typing import Any

import t068_visual_device as visual

SOURCE = Path(__file__).resolve()
PHASES = ("idle", "background_cpu")
LIMITATIONS = [
    "Sequential idle-then-loaded software-rendered runs; thermal and order effects unbalanced",
    "Five synthetic Godot events per workload per phase; frame_post_draw is not scan-out",
    "CPU competitor may run on a different core; worker CPU ticks prove activity, not interference",
    "Whole-Godot-process RSS only; no physical input, GPU VRAM, Windows or release result",
]


def source_hashes() -> dict[str, str]:
    return {**visual.source_hashes(),
            str(SOURCE.relative_to(visual.ROOT)): hashlib.sha256(SOURCE.read_bytes()).hexdigest()}


def cpu_ticks(pid: int) -> int:
    """Read Linux task utime+stime, correctly skipping the parenthesized comm field."""
    stat = Path(f"/proc/{pid}/stat").read_text(encoding="ascii")
    rest = stat[stat.rfind(")") + 2:].split()
    if len(rest) < 13:
        raise ValueError("Truncated process CPU data")
    return int(rest[11]) + int(rest[12])


def worker() -> None:
    """CPU-only, independent-process load with a stdout readiness handshake."""
    import hashlib as _hashlib

    print("T068_CPU_WORKER_READY", flush=True)
    seed = b"T068 local contention worker"
    while True:
        seed = _hashlib.pbkdf2_hmac("sha256", seed, seed, 25000)


def median_delta(idle: dict[str, Any], loaded: dict[str, Any]) -> dict[str, float]:
    idle_rows = idle["stress"]["rows"]
    loaded_rows = loaded["stress"]["rows"]
    return {a["name"]: round(b["event_to_frame_post_draw"]["median_ms"] -
                             a["event_to_frame_post_draw"]["median_ms"], 3)
            for a, b in zip(idle_rows, loaded_rows)}


def validate(record: Any) -> None:
    if (not isinstance(record, dict) or set(record) != {
            "schema", "sources", "platform", "profile", "phases", "worker_ticks",
            "frame_median_delta_ms", "limitations"} or
        record["schema"] != "t068-visual-contention-v1" or
        record["sources"] != source_hashes() or
        record["platform"] != "Linux" or record["profile"] != "software" or
        record["limitations"] != LIMITATIONS):
        raise ValueError("Invalid visual-contention evidence envelope")
    phases = record["phases"]
    if (not isinstance(phases, list) or len(phases) != 2 or
        any(not isinstance(p, dict) or set(p) != {"name", "visual"}
            for p in phases) or
        [p["name"] for p in phases] != list(PHASES)):
        raise ValueError("Incomplete or reordered phases")
    for phase in phases:
        visual.validate(phase["visual"])
        if phase["visual"]["profile"] != "software":
            raise ValueError("Hardware profile must not count as software evidence")
    ticks = record["worker_ticks"]
    if (not isinstance(ticks, dict) or set(ticks) != {"before", "after"} or
        any(type(v) is not int or v < 0 for v in ticks.values()) or
        ticks["after"] <= ticks["before"]):
        raise ValueError("Background CPU worker activity not established")
    differences = record["frame_median_delta_ms"]
    expected = median_delta(phases[0]["visual"], phases[1]["visual"])
    if (not isinstance(differences, dict) or set(differences) != set(expected) or
        any(type(value) not in (float, int) or
            not math.isfinite(value) or abs(value - expected[key]) > .00051
            for key, value in differences.items())):
        raise ValueError("Forged frame jitter comparison")


def live(godot: Path) -> dict[str, Any]:
    if platform.system() != "Linux":
        raise RuntimeError("Linux /proc is required")
    idle = visual.live(godot, "software")
    process = subprocess.Popen([sys.executable, str(SOURCE), "--worker"],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               text=True)
    try:
        if process.stdout is None or process.stdout.readline().strip() != "T068_CPU_WORKER_READY":
            raise RuntimeError("Background CPU worker did not start")
        before = cpu_ticks(process.pid)
        loaded = visual.live(godot, "software")
        after = cpu_ticks(process.pid)
        record: dict[str, Any] = {
            "schema": "t068-visual-contention-v1", "sources": source_hashes(),
            "platform": "Linux", "profile": "software",
            "phases": [{"name": "idle", "visual": idle},
                       {"name": "background_cpu", "visual": loaded}],
            "worker_ticks": {"before": before, "after": after},
            "frame_median_delta_ms": median_delta(idle, loaded),
            "limitations": LIMITATIONS,
        }
        validate(record)
        return record
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        if process.stdout is not None:
            process.stdout.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--evidence", type=Path)
    args = parser.parse_args()
    if args.worker:
        worker()
        return
    if args.evidence is not None:
        validate(json.loads(args.evidence.read_text(encoding="utf-8")))
        print("T068_VISUAL_CONTENTION_REPLAY_PASSED")
        return
    if args.godot is None or args.output is None:
        parser.error("Live measurement requires --godot and --output")
    record = live(args.godot)
    args.output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("T068_VISUAL_CONTENTION_PASSED", record["worker_ticks"]["after"] -
          record["worker_ticks"]["before"], "CPU ticks")


if __name__ == "__main__":
    main()
