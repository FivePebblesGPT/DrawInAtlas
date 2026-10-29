"""Run each Godot raster alternative in fresh processes and report median metrics."""

from __future__ import annotations

import argparse
import itertools
import json
import re
import statistics
import subprocess

Metric = str | int | float | bool


def number(row: dict[str, Metric], key: str) -> float:
    value = row[key]
    if not isinstance(value, (int, float)):
        raise ValueError(f"Expected numeric metric: {key}")
    return float(value)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument(
        "--store", action="store_true",
        help="Measure production transactions instead of codec containers",
    )
    parser.add_argument(
        "--fixture", choices=("sparse", "ink", "multi", "detail"),
        help="Rerun one fixture",
    )
    args = parser.parse_args()
    if args.repeats < 1:
        parser.error("--repeats must be positive")
    summaries: list[dict[str, Metric]] = []
    for fixture, codec, compression in itertools.product(
        (args.fixture,) if args.fixture else ("sparse", "ink", "multi", "detail"),
        ("store",) if args.store else ("image", "webp", "raw", "zstd"),
        ("compressed",) if args.store else ("plain", "compressed"),
    ):
        samples: list[dict[str, Metric]] = []
        for _ in range(args.repeats):
            process = subprocess.run(
                [
                    "/usr/bin/time", "-f", "ATLAS_RSS_KIB %M", args.engine,
                    "--headless", "--path", ".", "--script",
                    "res://tests/benchmarks/raster_codec.gd", "--",
                    fixture, codec, compression,
                ],
                capture_output=True, text=True, timeout=120, check=False,
            )
            output = process.stdout + process.stderr
            if process.returncode or re.search(r"SCRIPT ERROR:|^ERROR:|FAILED", output, re.M):
                raise RuntimeError(output)
            prefix = "ATLAS_STORE_RESULT " if args.store else "ATLAS_CODEC_RESULT "
            result_line = next(
                line for line in output.splitlines() if line.startswith(prefix)
            )
            sample: dict[str, Metric] = json.loads(result_line.removeprefix(prefix))
            sample["peak_rss_kib"] = int(next(
                line.split()[1] for line in output.splitlines() if line.startswith("ATLAS_RSS_KIB ")
            ))
            if sample["exact"] is not True or sample.get("isolated", True) is not True:
                raise RuntimeError("Pixel fidelity or resource isolation failed")
            samples.append(sample)
        summary = dict(samples[0])
        for key in samples[0]:
            if type(samples[0][key]) in (int, float):
                summary[key] = statistics.median(number(sample, key) for sample in samples)
        summaries.append(summary)
        prefix = "ATLAS_STORE_MEDIAN " if args.store else "ATLAS_CODEC_MEDIAN "
        print(prefix + json.dumps(summary, sort_keys=True), flush=True)
    if args.store:
        return
    print("fixture codec compressed bytes save_ms load_ms second_ms peak_static_MiB peak_RSS_MiB")
    for row in summaries:
        print(
            f"{row['fixture']} {row['codec']} {row['compressed']} {row['bytes']} "
            f"{number(row, 'save_ms'):.2f} {number(row, 'load_ms'):.2f} "
            f"{number(row, 'second_load_ms'):.2f} "
            f"{number(row, 'peak_static') / 2**20:.2f} "
            f"{number(row, 'peak_rss_kib') / 1024:.2f}",
            flush=True,
        )


if __name__ == "__main__":
    main()
