#!/usr/bin/env python3
"""Build and run the isolated T-068 native-thread CPU jitter benchmark.

The timed loop is entirely C++ and has no Python GIL or ctypes per-call
scheduling overhead. This is NOT a Godot extension or input-to-frame test.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import platform
import subprocess

SOURCE = Path(__file__).with_name("t068_thread_jitter.cpp")
KERNEL = Path(__file__).with_name("t068_raster_kernel.cpp")
HEADER = ["case", "mode", "workers", "trials", "candidates", "changed",
          "median_ms", "p95_ms", "max_ms", "checked_calls"]


def compile_benchmark(directory: Path) -> Path:
    """Compile the unintegrated native benchmark outside the repository."""
    directory.mkdir(parents=True, exist_ok=True)
    executable = directory / "t068-native-thread-jitter"
    subprocess.run(["g++", "-std=c++17", "-O3", "-pthread", "-Wall", "-Wextra",
                    "-Werror", str(SOURCE), str(KERNEL), "-o", str(executable)], check=True)
    return executable


def parse_tsv(stdout: str, size: int, trials: int, workers: tuple[int, ...]) -> dict:
    """Reject malformed, incomplete and nonfinite native measurement output."""
    import math
    lines = [line.split("\t") for line in stdout.strip().splitlines()]
    if not lines or lines[0] != HEADER:
        raise ValueError("Unexpected native benchmark header")
    expected = {(name, mode, worker) for name in (
        "overlapping_source_over", "masked_erase", "exact_replace")
        for mode in ("sparse", "full") for worker in workers}
    rows = []
    seen = set()
    for fields in lines[1:]:
        if len(fields) != len(HEADER):
            raise ValueError("Malformed native benchmark row")
        record = dict(zip(HEADER, fields))
        try:
            record.update({key: int(record[key]) for key in (
                "workers", "trials", "candidates", "changed", "checked_calls")})
            record.update({key: float(record[key]) for key in (
                "median_ms", "p95_ms", "max_ms")})
        except (ValueError, TypeError) as exc:
            raise ValueError("Invalid native benchmark numeric field") from exc
        key = (record["case"], record["mode"], record["workers"])
        if key not in expected or key in seen:
            raise ValueError("Unexpected or duplicate native benchmark case")
        seen.add(key)
        if (record["trials"] != trials or
                record["checked_calls"] != record["workers"] * trials or
                record["candidates"] < record["changed"] or record["changed"] <= 0 or
                not all(math.isfinite(record[name]) and record[name] > 0
                        for name in ("median_ms", "p95_ms", "max_ms")) or
                not 0 < record["median_ms"] <= record["p95_ms"] <= record["max_ms"]):
            raise ValueError("Native measurement counts or timings invalid")
        rows.append(record)
    if seen != expected:
        raise ValueError("Missing native benchmark cases")
    return {
        "schema": "t068-native-thread-jitter-v1", "platform": platform.platform(),
        "measurement": "C++ std::thread workers with private RGBA8/mask/delta/output buffers",
        "not_measured": ["Godot/GDExtension boundary", "UI input", "texture upload",
                         "screen presentation", "Windows hardware", "GPU VRAM"],
        "region": size, "trials_per_worker": trials, "workers": list(workers),
        "validation": "exact native deltas, unchanged source and full-buffer output after every worker run",
        "rows": rows,
    }


def run(executable: Path, region: int, trials: int, workers: tuple[int, ...]) -> dict:
    if region < 128 or region > 1024 or region % 64 != 0 or trials < 3 or trials > 2000:
        raise ValueError("Invalid region or trial bounds")
    if not workers or len(set(workers)) != len(workers) or any(x < 1 or x > 16 for x in workers):
        raise ValueError("Worker counts must be unique and bounded")
    completed = subprocess.run([str(executable), str(region), str(trials),
                                *(str(count) for count in workers)],
                               capture_output=True, text=True, check=True, timeout=120)
    return parse_tsv(completed.stdout, region, trials, workers)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=Path("/tmp/t068-native-jitter"))
    parser.add_argument("--output", type=Path, default=Path("/tmp/t068-native-jitter.json"))
    parser.add_argument("--trials", type=int, default=101)
    parser.add_argument("--region", type=int, default=256)
    parser.add_argument("--workers", type=int, nargs="+", default=[1, 2, 4])
    args = parser.parse_args()
    result = run(compile_benchmark(args.build_dir), args.region,
                 args.trials, tuple(args.workers))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"T068_NATIVE_THREAD_JITTER_PASSED {len(result['rows'])} cases; "
          f"output={args.output}")


if __name__ == "__main__":
    main()
