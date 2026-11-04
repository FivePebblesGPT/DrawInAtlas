#!/usr/bin/env python3
"""T-068: exact Godot brush geometry AND canonical RGBA8 via detached C++17.

Large Godot cases were generated with a blank source, so their geometry is
checked against Godot while their patterned-source compositing is checked
against an independent Python reference. This is not a publication benchmark.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import tempfile
from pathlib import Path
from typing import Any

from t068_blend2d_scale import CASES, source_bytes
from t068_scalar_hard_brush import (LARGE_SHA256, ROOT, SMALL_SHA256, SOURCE,
                                    ScalarBrush, compile_kernel, expected_mask, inputs)
from t068_skia_brush import canonical_pixels, load_oracle

EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_scalar_rgba8.json"


def fixtures() -> list[tuple[str, int, bytes, list[list[float]], float,
                             bytes, set[int], tuple[int, int, int, int], bool, str | None]]:
    """Frozen inputs, including original source color and Godot output digest."""
    _side, small_source, small = load_oracle()
    small_by_id = {case["id"]: case for case in small}
    large_by_id = {case["id"]: case for case in CASES}
    cases = []
    for identifier, side, path, width, selection, indices, after_sha in inputs():
        if identifier.startswith("small/"):
            entry = small_by_id[identifier.removeprefix("small/")]
            source = small_source
        else:
            entry = large_by_id[identifier.split("/")[-1]]
            source = source_bytes(side)
        cases.append((identifier, side, source, path, width, selection, indices,
                      tuple(entry["paint"]), bool(entry["erase"]), after_sha))
    return cases


def expected_row(case: tuple[str, int, bytes, list[list[float]], float, bytes,
                             set[int], tuple[int, int, int, int], bool, str | None]) -> dict[str, Any]:
    identifier, side, source, _path, _width, selection, indices, paint, erase, godot_sha = case
    expected = canonical_pixels(source, indices, paint, erase)
    digest = hashlib.sha256(expected).hexdigest()
    if godot_sha is not None and digest != godot_sha:
        raise ValueError("Pinned small Godot RGBA8 differs from reference")
    changed = sum(source[index * 4:index * 4 + 4] != expected[index * 4:index * 4 + 4]
                  for index in indices)
    return {"id": identifier, "side": side, "covered": len(indices),
            "changed_pixels": changed, "source_sha256": hashlib.sha256(source).hexdigest(),
            "selection_sha256": hashlib.sha256(selection).hexdigest(),
            "coverage_sha256": hashlib.sha256(expected_mask(side, indices)).hexdigest(),
            "output_sha256": digest,
            "godot_output_sha256": godot_sha}


def run(library: Path) -> dict[str, Any]:
    native = ScalarBrush(library)
    cases = fixtures()
    runs = []
    for _ in range(2):
        rows = []
        for case in cases:
            identifier, side, source, path, width, selection, indices, paint, erase, _ = case
            output, coverage = native.composite(source, side, path, width, selection, paint, erase)
            reference = expected_row(case)
            if (hashlib.sha256(output).hexdigest() != reference["output_sha256"] or
                    coverage != expected_mask(side, indices) or
                    output != canonical_pixels(source, indices, paint, erase)):
                raise AssertionError(f"Native RGBA8/coverage differs from pinned oracle: {identifier}")
            rows.append(reference)
        runs.append(rows)
    payload = {"schema": 1, "native_source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
               "small_oracle_sha256": SMALL_SHA256, "large_oracle_sha256": LARGE_SHA256,
               "runs": runs, "summary": {"runs": 2, "cases_per_run": len(cases),
                                           "exact_coverage_and_rgba8": len(cases) * 2},
               "limitations": [
                   "Detached C++17 and Python ctypes: no Godot marshaling, document publication, or GPU upload",
                   "Small RGBA8 matches actual Godot output; large Godot oracle checks empty-source coverage only",
                   "Large RGBA8 is independently reconstructed on the scale benchmark's patterned source",
                   "No matched latency/p95, VRAM, physical Windows/Linux hardware, or standalone release testing"]}
    validate(payload)
    return payload


def validate(payload: dict[str, Any]) -> None:
    """Reconstruct every byte digest and changed count from pinned sources."""
    cases = fixtures()
    rows = [expected_row(case) for case in cases]
    if (type(payload) is not dict or payload.get("schema") != 1 or
            payload.get("native_source_sha256") != hashlib.sha256(SOURCE.read_bytes()).hexdigest() or
            payload.get("small_oracle_sha256") != SMALL_SHA256 or
            payload.get("large_oracle_sha256") != LARGE_SHA256 or
            type(payload.get("runs")) is not list or len(payload["runs"]) != 2 or
            any(run != rows for run in payload["runs"]) or
            payload.get("summary") != {"runs": 2, "cases_per_run": len(cases),
                                       "exact_coverage_and_rgba8": len(cases) * 2} or
            type(payload.get("limitations")) is not list or
            payload["limitations"] != [
                "Detached C++17 and Python ctypes: no Godot marshaling, document publication, or GPU upload",
                "Small RGBA8 matches actual Godot output; large Godot oracle checks empty-source coverage only",
                "Large RGBA8 is independently reconstructed on the scale benchmark's patterned source",
                "No matched latency/p95, VRAM, physical Windows/Linux hardware, or standalone release testing"]):
        raise ValueError("Invalid or nonreplayable T-068 scalar RGBA8 evidence")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="t068-scalar-rgba8-") as folder:
        payload = run(compile_kernel(Path(folder)))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"T068_SCALAR_RGBA8_PASSED: {payload['summary']['exact_coverage_and_rgba8']} "
          "exact native/Godot-or-reference comparisons")


if __name__ == "__main__":
    main()
