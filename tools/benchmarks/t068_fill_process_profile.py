#!/usr/bin/env python3
"""Sample native Godot fill-to-frame runs and Linux process RSS.

Run only in a disposable Linux X11/Mesa environment, not fast push CI.
The tested event is a synthetic Godot GUI-input adapter, not production
Bucket UI, a physical mouse, GPU scan-out, or native-kernel integration.

Samples ``/proc`` every few milliseconds and records the Godot process's
resident memory, *not* the xvfb-run/Xvfb wrapper's memory. VmHWM is the kernel's
whole-process RSS high water, including startup/imports; post-ready peaks are
sampled estimates, not an exact allocation trace.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import signal
import statistics
import subprocess
import sys
import time
from typing import Any


SCRIPT = "res://tests/drawing_fill_frame_native.gd"
REQUIRED_SIZES = (32, 64, 96)


@dataclass(frozen=True)
class MemorySample:
    rss_kib: int
    high_water_kib: int
    swap_kib: int


def parse_linux_status(text: str) -> MemorySample | None:
    """Parse only kernel-provided KiB values from /proc/PID/status.

    Parameters
    ----------
    text : str
        Contents of one Linux process status file.

    Returns
    -------
    MemorySample | None
        Resident-memory statistics, or None if a required value is absent.
    """
    values: dict[str, int] = {}
    for line in text.splitlines():
        field, _, data = line.partition(":")
        if field not in {"VmRSS", "VmHWM", "VmSwap"}:
            continue
        parts = data.strip().split()
        if len(parts) != 2 or parts[1] != "kB" or not parts[0].isdigit():
            return None
        values[field] = int(parts[0])
    if "VmRSS" not in values or "VmHWM" not in values:
        return None
    return MemorySample(values["VmRSS"], values["VmHWM"], values.get("VmSwap", 0))


def sample_pid(pid: int) -> MemorySample | None:
    try:
        return parse_linux_status(Path(f"/proc/{pid}/status").read_text())
    except (OSError, UnicodeError):
        return None


def descendants(parent_pid: int) -> set[int]:
    """Walk kernel parent/child membership without external dependencies."""
    pending = [parent_pid]
    found: set[int] = set()
    while pending:
        pid = pending.pop()
        if pid in found:
            continue
        found.add(pid)
        try:
            children = Path(f"/proc/{pid}/task/{pid}/children").read_text().split()
        except OSError:
            continue  # Process may have exited between sampling passes.
        pending.extend(int(child) for child in children if child.isdigit())
    return found


def matches_witness(executable: Path, argv: list[bytes], godot: Path) -> bool:
    # An xvfb-run shell receives every argument but is not the engine process.
    return executable == godot.resolve() and b"--script" in argv and SCRIPT.encode() in argv


def find_witness_pid(parent_pid: int, godot: Path) -> int | None:
    # Some constrained /proc mounts do not expose task/<pid>/children.
    # xvfb-run's Godot child remains in our newly created session/process group.
    for path in Path("/proc").iterdir():
        if not path.name.isdigit():
            continue
        pid = int(path.name)
        try:
            if os.getpgid(pid) != parent_pid:
                continue
            cmdline = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
            executable = Path(f"/proc/{pid}/exe").resolve(strict=True)
        except OSError:
            continue
        # xvfb-run is a shell wrapper with the Godot command among its argv.
        # Only measure the actual engine executable, never its 832-KiB shell.
        if matches_witness(executable, cmdline, godot):
            return pid
    return None


def validate_witness(raw: Any, trials: int) -> None:
    """Fail closed on nonpassing, incomplete or mismatched measurements."""
    if not isinstance(raw, dict) or raw.get("schema") != "t068-bucket-frame-v1":
        raise ValueError("unsupported fill-to-frame evidence schema")
    if raw.get("failures") != 0 or raw.get("configured_trials_per_size") != trials:
        raise ValueError("witness failed or did not use the requested trial count")
    cases = raw.get("cases")
    if not isinstance(cases, list) or len(cases) != len(REQUIRED_SIZES):
        raise ValueError("missing bounded fill sizes")
    for size, case in zip(REQUIRED_SIZES, cases):
        if not isinstance(case, dict) or case.get("size") != size or case.get("trials") != trials:
            raise ValueError("incorrect native fill case/trial count")
        for name in ("cpu_dispatch", "event_to_frame_post_draw"):
            stats = case.get(name)
            if not isinstance(stats, dict):
                raise ValueError(f"missing {name} statistics")
            samples = stats.get("samples_ms")
            if not isinstance(samples, list) or len(samples) != trials or any(
                isinstance(v, bool) or not isinstance(v, (float, int)) or not 0 <= v < 1e5
                for v in samples
            ):
                raise ValueError(f"invalid {name} latency samples")
    if not isinstance(raw.get("checks"), int) or raw["checks"] < trials * 3 * 5:
        raise ValueError("too few native checks")


def profile_once(
    godot: Path, root: Path, directory: Path, index: int, trials: int,
    sample_ms: int, timeout_seconds: int,
) -> dict[str, Any]:
    marker = directory / f"run_{index}.ready"
    log_path = directory / f"run_{index}.log"
    json_path = directory / f"run_{index}.json"
    screenshot_path = directory / f"run_{index}.png"
    command = [
        "xvfb-run", "-a", "-s", "-screen 0 1280x900x24", str(godot),
        "--audio-driver", "Dummy", "--rendering-driver", "opengl3",
        "--rendering-method", "gl_compatibility", "--path", str(root),
        "--script", SCRIPT, "--", "--trials", str(trials),
        "--output", str(json_path), "--screenshot", str(screenshot_path),
        "--ready-file", str(marker),
    ]
    rss_samples: list[int] = []
    ready_samples: list[int] = []
    high_water_samples: list[int] = []
    swap_peak = 0
    attached_pid: int | None = None
    start = time.monotonic()
    with log_path.open("wb") as log:
        process = subprocess.Popen(
            command, cwd=root, stdout=log, stderr=subprocess.STDOUT,
            start_new_session=True,
            env={**os.environ, "GODOT_SILENCE_ROOT_WARNING": "1"},
        )
        try:
            while process.poll() is None:
                if time.monotonic() - start > timeout_seconds:
                    raise TimeoutError(f"native fill witness exceeded {timeout_seconds}s")
                pid = find_witness_pid(process.pid, godot)
                if pid is not None:
                    attached_pid = pid
                    memory = sample_pid(pid)
                    if memory is not None:
                        rss_samples.append(memory.rss_kib)
                        high_water_samples.append(memory.high_water_kib)
                        swap_peak = max(swap_peak, memory.swap_kib)
                        if marker.is_file():
                            ready_samples.append(memory.rss_kib)
                time.sleep(sample_ms / 1000)
        except BaseException:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise
        return_code = process.wait()
    output = log_path.read_text(encoding="utf-8", errors="replace")
    if return_code != 0 or "T068_FILL_FRAME_PASSED" not in output or any(
        token in output for token in ("SCRIPT ERROR:", "T068_FILL_FRAME_FAILED:", "ERROR:")
    ):
        raise RuntimeError(f"native fill witness failed in {log_path} (exit={return_code})")
    if not json_path.is_file() or not screenshot_path.is_file() or screenshot_path.stat().st_size == 0:
        raise RuntimeError("native fill evidence or framebuffer missing")
    witness: dict[str, Any] = json.loads(json_path.read_text())
    validate_witness(witness, trials)
    if attached_pid is None or len(rss_samples) < 2 or not ready_samples:
        raise RuntimeError("could not sample the Godot process before and after readiness")
    return {
        "run": index,
        "godot_pid": attached_pid,
        "elapsed_wall_ms": round((time.monotonic() - start) * 1000, 3),
        "memory": {
            "source": "Linux /proc/PID/status (Godot only; KiB)",
            "sample_interval_ms_requested": sample_ms,
            "samples": len(rss_samples),
            "post_ready_samples": len(ready_samples),
            "whole_process_vmhwm_kib": max(high_water_samples),
            "max_sampled_vmrss_kib": max(rss_samples),
            "rss_at_first_ready_sample_kib": ready_samples[0],
            "max_sampled_post_ready_rss_kib": max(ready_samples),
            "max_sampled_post_ready_delta_kib": max(ready_samples) - ready_samples[0],
            "max_sampled_swap_kib": swap_peak,
        },
        "witness_checks": witness["checks"],
        "cases": witness["cases"],
        "files": {"log": log_path.name, "json": json_path.name, "frame": screenshot_path.name},
    }


def summarize(runs: list[dict[str, Any]]) -> dict[str, Any]:
    """Keep distribution summaries per run; never pool correlated trials."""
    rows: list[dict[str, Any]] = []
    for size_index, size in enumerate(REQUIRED_SIZES):
        cpu = [row["cases"][size_index]["cpu_dispatch"]["median_ms"] for row in runs]
        frame = [row["cases"][size_index]["event_to_frame_post_draw"]["median_ms"] for row in runs]
        rows.append({
            "size": size,
            "run_median_cpu_ms": cpu,
            "run_median_frame_ms": frame,
            "median_of_cpu_run_medians_ms": round(statistics.median(cpu), 3),
            "median_of_frame_run_medians_ms": round(statistics.median(frame), 3),
        })
    return {"cases": rows}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=2)
    parser.add_argument("--trials", type=int, default=21)
    parser.add_argument("--sample-ms", type=int, default=10)
    parser.add_argument("--timeout-seconds", type=int, default=240)
    args = parser.parse_args(argv)
    if not sys.platform.startswith("linux") or not Path("/proc/self/status").exists():
        parser.error("external process memory sampling currently requires Linux /proc")
    if not 1 <= args.runs <= 5 or not 5 <= args.trials <= 40 or not 5 <= args.sample_ms <= 100:
        parser.error("runs must be 1..5, trials 5..40, sample-ms 5..100")
    if args.timeout_seconds < 30 or args.timeout_seconds > 600:
        parser.error("timeout-seconds must be 30..600")
    if not args.godot.is_file():
        parser.error("Godot executable not found")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parents[2]
    results = [profile_once(args.godot.resolve(), root, args.output_dir, index,
                            args.trials, args.sample_ms, args.timeout_seconds)
               for index in range(1, args.runs + 1)]
    evidence = {
        "schema": "t068-linux-fill-process-profile-v1",
        "engine": "pinned Godot 4.8 beta 2 required by caller",
        "platform": sys.platform,
        "runs": results,
        "summary": summarize(results),
        "limitations": (
            "Synthetic Godot GUI adapter through DrawingEditSession and software frame_post_draw; "
            "not production Bucket UI, physical hardware input, scan-out, or GPU VRAM. "
            "Linux VmHWM covers process lifetime; sampled RSS may miss short spikes, "
            "and post-ready change includes renderer allocations and repeated new documents. "
            "Latency p95 is an empirical short-run order statistic, not a calibrated service SLO."
        ),
    }
    destination = args.output_dir / "evidence.json"
    destination.write_text(json.dumps(evidence, indent=2) + "\n")
    print(f"T068_LINUX_FILL_PROFILE_PASSED runs={len(results)} trials={args.trials} "
          f"checks={sum(r['witness_checks'] for r in results)} evidence={destination}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, TimeoutError, ValueError) as error:
        print(f"T068_LINUX_FILL_PROFILE_FAILED: {error}", file=sys.stderr)
        raise SystemExit(1) from error
