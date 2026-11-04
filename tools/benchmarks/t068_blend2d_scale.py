#!/usr/bin/env python3
"""T-068 opt-in 512/1024/2048 CPU scaling screen for native Blend2D.

The checked native path is independent of Godot's canonical coverage geometry.
Returned A8 coverage is checked against native selection, and its RGBA8 result
is *fully* reconstructed with an independent Python source-over oracle. 128/256
pixel display regions are only modeled as hypothetical full-update byte costs;
no Godot texture upload or physical pointer-to-frame latency is measured.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import math
import platform
import statistics
import tempfile
import zlib
from functools import lru_cache
from pathlib import Path
from typing import Any

from t068_blend2d_brush import NativeBrush, compile_bridge
from t068_blend2d_cpu import PINNED_SOURCE_SHA256, verify_archive
from t068_skia_brush import canonical_pixels

SIDES = (512, 1024, 2048)
REGIONS = (128, 256)
PATTERN = bytes((23, 45, 67, 0, 119, 31, 217, 77,
                 7, 183, 29, 255, 65, 13, 177, 128))
CASES: tuple[dict[str, Any], ...] = (
    {"id": "hard4_long", "width": 4.0, "path": ((-56, -4), (56, 4)),
     "selection": "rect128", "paint": (243, 51, 119, 193), "erase": False},
    {"id": "round256", "width": 256.0, "path": ((0, 0),),
     "selection": "rect256", "paint": (29, 207, 15, 128), "erase": False},
    {"id": "cross64_sparse_erase", "width": 64.0,
     "path": ((-90, -90), (90, 90), (-90, 90), (90, -90)),
     "selection": "sparse256", "paint": (13, 99, 183, 0), "erase": True},
    {"id": "transparent_noop", "width": 64.0, "path": ((-30, 0), (30, 0)),
     "selection": "rect128", "paint": (255, 127, 17, 0), "erase": False},
)
TIMINGS = ("prep_us", "call_us", "output_unpack_us", "native_stencil_us", "native_composite_us")


@lru_cache(maxsize=3)
def source_bytes(side: int) -> bytes:
    if side not in SIDES:
        raise ValueError("Unsupported scale tile size")
    return PATTERN * (side * side // 4)


@lru_cache(maxsize=12)
def selection_bytes(side: int, selection: str) -> bytes:
    if side not in SIDES or selection not in ("rect128", "rect256", "sparse256"):
        raise ValueError("Unsupported selection")
    span = 128 if selection == "rect128" else 256
    lo = (side - span) // 2
    mask = bytearray(side * side)
    for y in range(lo, lo + span):
        offset = y * side + lo
        if selection == "sparse256":
            mask[offset:offset + span] = bytes(int((x + y) % 3 != 0)
                                                for x in range(lo, lo + span))
        else:
            mask[offset:offset + span] = bytes([1]) * span
    return bytes(mask)


def points_for(side: int, case: dict[str, Any]) -> list[list[float]]:
    center = side / 2.0
    return [[center + x, center + y] for x, y in case["path"]]


def _pack_coverage(side: int, coverage: set[int]) -> str:
    binary = bytearray(side * side)
    for index in coverage:
        binary[index] = 1
    return base64.b64encode(zlib.compress(binary, level=9)).decode("ascii")


def _unpack_coverage(side: int, text: str) -> set[int]:
    if not isinstance(text, str) or len(text) > 200_000:
        raise ValueError("Invalid bounded coverage encoding")
    try:
        compressed = base64.b64decode(text, validate=True)
        decoder = zlib.decompressobj()
        binary = decoder.decompress(compressed, side * side + 1)
        if (not decoder.eof or decoder.unused_data or decoder.unconsumed_tail
                or len(binary) != side * side or decoder.flush()):
            raise ValueError("Invalid coverage compressed length or trailing bytes")
    except (ValueError, zlib.error) as exc:
        raise ValueError("Invalid bounded coverage encoding") from exc
    if any(value not in (0, 1) for value in binary):
        raise ValueError("Nonbinary coverage")
    return {index for index, value in enumerate(binary) if value}


def _display_regions(source: bytes, output: bytes, coverage: set[int], side: int) -> dict[str, dict[str, int]]:
    changed = [index for index in coverage
               if source[index * 4:index * 4 + 4] != output[index * 4:index * 4 + 4]]
    result = {}
    for region in REGIONS:
        touched = {(index // side // region, index % side // region) for index in changed}
        result[str(region)] = {"touched_tiles": len(touched), "hypothetical_full_upload_bytes":
                               len(touched) * region * region * 4}
    return result


def screen(bridge: Path, trials: int = 5) -> dict[str, Any]:
    if not 3 <= trials <= 31:
        raise ValueError("Trials must be 3..31")
    native = NativeBrush(bridge)
    rows = []
    for side in SIDES:
        source = source_bytes(side)
        for case in CASES:
            selection = selection_bytes(side, case["selection"])
            path = points_for(side, case)
            first: tuple[bytes, set[int], int] | None = None
            samples: dict[str, list[float]] = {key: [] for key in TIMINGS}
            for _ in range(trials):
                output, coverage, timings, changed = native.render(
                    source, side, path, case["width"], case["paint"], case["erase"],
                    selection, threshold=128)
                if first is not None and (output, coverage, changed) != first:
                    raise AssertionError(f"Nondeterministic native scale output: {side}/{case['id']}")
                first = output, coverage, changed
                for key in TIMINGS:
                    value = timings[key]
                    if not math.isfinite(value) or value < 0:
                        raise AssertionError(f"Invalid native {key} timing")
                    samples[key].append(round(value, 3))
            assert first is not None
            output, coverage, changed = first
            if any(not selection[i] for i in coverage):
                raise AssertionError("Native coverage escapes the selection")
            if canonical_pixels(source, coverage, case["paint"], case["erase"]) != output:
                raise AssertionError("Native large-tile pixels differ from canonical RGBA8")
            if changed != sum(source[i*4:i*4+4] != output[i*4:i*4+4] for i in coverage):
                raise AssertionError("Changed pixel count incorrect")
            rows.append({
                "side": side, "id": case["id"], "selection_sha256": hashlib.sha256(selection).hexdigest(),
                "source_sha256": hashlib.sha256(source).hexdigest(),
                "coverage_zlib_base64": _pack_coverage(side, coverage),
                "coverage_count": len(coverage), "changed_pixels": changed,
                "output_sha256": hashlib.sha256(output).hexdigest(),
                "display_regions": _display_regions(source, output, coverage, side),
                "whole_tile_output_bytes": len(source),
                "samples_us": samples,
            })
    return {"schema": 1, "benchmark": "T-068 native Blend2D large tile scaling",
            "source_version": "0.21.2", "source_sha256": PINNED_SOURCE_SHA256,
            "trials": trials, "sides": list(SIDES), "display_region_sizes": list(REGIONS),
            "threshold": 128, "rows": rows, "cases_per_side": len(CASES),
            "limitations": ["Blend2D A8 geometry is not a Godot brush parity claim",
                            "128/256 display tile bytes are hypothetical, not measured texture uploads",
                            "Detached ctypes/C++ CPU calls only; no Godot publication or physical display timing"]}


def validate_evidence(payload: dict[str, Any]) -> None:
    """Replay every recorded selected pixel and verify complete two-run integrity."""
    if (payload.get("schema") != 1 or not isinstance(payload.get("runs"), list)
            or not 1 <= len(payload["runs"]) <= 3):
        raise ValueError("Invalid scaling evidence envelope")
    expected = {(side, case["id"]) for side in SIDES for case in CASES}
    signatures = []
    for run in payload["runs"]:
        rows = run.get("rows")
        if (run.get("schema") != 1 or run.get("source_version") != "0.21.2"
                or run.get("source_sha256") != PINNED_SOURCE_SHA256
                or run.get("sides") != list(SIDES) or run.get("display_region_sizes") != list(REGIONS)
                or run.get("threshold") != 128 or run.get("cases_per_side") != len(CASES)
                or type(run.get("trials")) is not int or not 3 <= run["trials"] <= 31
                or not isinstance(rows, list) or len(rows) != len(expected)):
            raise ValueError("Invalid native scaling run")
        keys = [(r.get("side"), r.get("id")) for r in rows]
        if set(keys) != expected or len(keys) != len(set(keys)):
            raise ValueError("Invalid native scaling case coverage")
        signatures_by_case = {}
        for row in rows:
            side, case_id = row["side"], row["id"]
            case = next(c for c in CASES if c["id"] == case_id)
            source = source_bytes(side)
            selection = selection_bytes(side, case["selection"])
            coverage = _unpack_coverage(side, row.get("coverage_zlib_base64"))
            output = canonical_pixels(source, coverage, case["paint"], case["erase"])
            changed = sum(source[i*4:i*4+4] != output[i*4:i*4+4] for i in coverage)
            if (not all(selection[index] for index in coverage)
                    or row.get("coverage_count") != len(coverage)
                    or row.get("changed_pixels") != changed
                    or row.get("source_sha256") != hashlib.sha256(source).hexdigest()
                    or row.get("selection_sha256") != hashlib.sha256(selection).hexdigest()
                    or row.get("output_sha256") != hashlib.sha256(output).hexdigest()
                    or row.get("whole_tile_output_bytes") != len(source)
                    or row.get("display_regions") != _display_regions(source, output, coverage, side)):
                raise ValueError(f"Invalid native scaling pixel/region evidence: {side}/{case_id}")
            samples = row.get("samples_us")
            if (not isinstance(samples, dict) or set(samples) != set(TIMINGS)
                    or any(not isinstance(v, list) or len(v) != run["trials"]
                           or any(type(t) not in (int, float) or not math.isfinite(t) or t < 0 for t in v)
                           for v in samples.values())):
                raise ValueError(f"Invalid native scaling timing evidence: {side}/{case_id}")
            signatures_by_case[(side, case_id)] = (row["coverage_zlib_base64"],
                                                  row["output_sha256"], changed)
        signatures.append(signatures_by_case)
    if any(signature != signatures[0] for signature in signatures[1:]):
        raise ValueError("Different native coverage or RGBA8 between scaling runs")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--library-dir", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=2)
    parser.add_argument("--trials", type=int, default=5)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.runs <= 3:
        parser.error("Runs must be 1..3")
    verify_archive(args.archive)
    with tempfile.TemporaryDirectory(prefix="t068-blend2d-scale-") as temporary:
        library = compile_bridge(args.source, args.library_dir, Path(temporary))
        reports = [screen(library, args.trials) for _ in range(args.runs)]
    payload = {"schema": 1, "runs": reports,
               "platform": {"system": platform.system(), "machine": platform.machine(),
                            "python": platform.python_version()},
               "scope": "isolated native A8 + exact RGBA8 CPU; no Godot or GPU"}
    validate_evidence(payload)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"T068_BLEND2D_SCALE_PASSED: {len(CASES) * len(SIDES) * args.runs} "
          f"canonical output comparisons across {args.runs} runs")


if __name__ == "__main__":
    main()
