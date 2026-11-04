#!/usr/bin/env python3
"""Opt-in T-068 ABBA software-rendered contention witness (NOT physical latency).

Runs fresh Godot processes in idle/loaded/loaded/idle order, with a separate
CPU worker only during each loaded phase. The paired contrasts reveal order
sensitivity; they do not prove causal interference or physical presentation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
import subprocess
import sys
from pathlib import Path
from typing import Any

import t068_visual_contention as contention
import t068_visual_device as visual

SOURCE = Path(__file__).resolve()
PHASES = ("idle", "background_cpu", "background_cpu", "idle")
LIMITATIONS = [
    "ABBA order counterbalances two software-rendered sessions per condition, not scheduling or thermal history",
    "Five synthetic events per workload per phase; frame_post_draw is not physical scan-out",
    "Worker CPU ticks show activity, not shared-core contention or causation",
    "Process RSS/HWM is not brush heap or GPU VRAM; no Windows, hardware input or portable-release evidence",
]


def source_hashes() -> dict[str, str]:
    return {
        **contention.source_hashes(),
        str(SOURCE.relative_to(visual.ROOT)): hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    }


def contrasts(phases: list[dict[str, Any]]) -> dict[str, dict[str, float]]:
    rows = [phase["visual"]["stress"]["rows"] for phase in phases]
    result: dict[str, dict[str, float]] = {}
    for case_index, (name, _) in enumerate(visual.CASES):
        medians = [r[case_index]["event_to_frame_post_draw"]["median_ms"] for r in rows]
        first = round(medians[1] - medians[0], 3)
        second = round(medians[2] - medians[3], 3)
        result[name] = {
            "idle_first_ms": first,
            "loaded_first_ms": second,
            "average_ms": round((first + second) / 2, 3),
        }
    return result


def validate(record: Any) -> None:
    if (not isinstance(record, dict) or set(record) != {
            "schema", "sources", "platform", "profile", "phases", "contrasts_ms", "limitations"
        } or record["schema"] != "t068-visual-counterbalanced-v1" or
        record["sources"] != source_hashes() or record["platform"] != "Linux" or
        record["profile"] != "software" or record["limitations"] != LIMITATIONS):
        raise ValueError("Invalid counterbalanced evidence envelope")
    phases = record["phases"]
    if (not isinstance(phases, list) or len(phases) != 4 or
        any(not isinstance(phase, dict) or set(phase) != {"name", "visual", "worker_ticks"}
            for phase in phases) or
        tuple(phase["name"] for phase in phases) != PHASES):
        raise ValueError("Missing or reordered ABBA phases")
    renderer: tuple[Any, Any] | None = None
    for phase in phases:
        visual.validate(phase["visual"])
        if phase["visual"]["profile"] != "software":
            raise ValueError("Hardware run cannot count as software evidence")
        identity = (phase["visual"]["stress"]["adapter"],
                    phase["visual"]["glxinfo_renderer"])
        if renderer is not None and identity != renderer:
            raise ValueError("Renderer changed across phases")
        renderer = identity
        ticks = phase["worker_ticks"]
        if phase["name"] == "idle":
            if ticks is not None:
                raise ValueError("Idle phase has an active competitor")
        elif (not isinstance(ticks, dict) or set(ticks) != {"before", "after"} or
              any(type(v) is not int or v < 0 for v in ticks.values()) or
              ticks["after"] <= ticks["before"]):
            raise ValueError("Background worker activity not proven")
    expected = contrasts(phases)
    observed = record["contrasts_ms"]
    if (not isinstance(observed, dict) or set(observed) != set(expected) or
        any(not isinstance(observed[name], dict) or set(observed[name]) != set(stats) or
            any(type(observed[name][field]) not in (float, int) or
                not math.isfinite(observed[name][field]) or
                abs(observed[name][field] - value) > 0.00051
                for field, value in stats.items())
            for name, stats in expected.items())):
        raise ValueError("Forged ABBA frame contrasts")


def loaded_visual(godot: Path) -> tuple[dict[str, Any], dict[str, int]]:
    process = subprocess.Popen([sys.executable, str(contention.SOURCE), "--worker"],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    try:
        if process.stdout is None or process.stdout.readline().strip() != "T068_CPU_WORKER_READY":
            raise RuntimeError("Background CPU worker did not start")
        before = contention.cpu_ticks(process.pid)
        frame = visual.live(godot, "software")
        after = contention.cpu_ticks(process.pid)
        if after <= before:
            raise RuntimeError("Background CPU worker did not consume CPU")
        return frame, {"before": before, "after": after}
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        if process.stdout is not None:
            process.stdout.close()


def live(godot: Path) -> dict[str, Any]:
    if platform.system() != "Linux":
        raise RuntimeError("Linux /proc is required")
    phases: list[dict[str, Any]] = []
    for name in PHASES:
        if name == "idle":
            frame, ticks = visual.live(godot, "software"), None
        else:
            frame, ticks = loaded_visual(godot)
        phases.append({"name": name, "visual": frame, "worker_ticks": ticks})
    record = {
        "schema": "t068-visual-counterbalanced-v1", "sources": source_hashes(),
        "platform": "Linux", "profile": "software", "phases": phases,
        "contrasts_ms": contrasts(phases), "limitations": LIMITATIONS,
    }
    validate(record)
    return record


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--evidence", type=Path)
    args = parser.parse_args()
    if args.evidence:
        validate(json.loads(args.evidence.read_text(encoding="utf-8")))
        print("T068_VISUAL_COUNTERBALANCED_REPLAY_PASSED")
        return
    if args.godot is None or args.output is None:
        parser.error("Live run requires --godot and --output")
    record = live(args.godot)
    args.output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("T068_VISUAL_COUNTERBALANCED_PASSED", len(record["phases"]), "phases")


if __name__ == "__main__":
    main()
