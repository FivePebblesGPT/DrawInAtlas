#!/usr/bin/env python3
"""T-068: replay two-run native large-tile evidence against real Godot coverage.

No native executable is invoked here: the independent pinned Blend2D full-tile
results are verified by t068_blend2d_scale and cross-checked against a fixture
produced by the real Godot DrawingEditSession. Only geometry differs; both
sides are recomposited independently against identical canonical RGBA8 input.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import math
import zlib
from functools import lru_cache
from pathlib import Path
from typing import Any

from t068_blend2d_scale import (
    CASES, SIDES, _unpack_coverage, selection_bytes, source_bytes, validate_evidence,
)
from t068_cairo_cpu import source_over

ROOT = Path(__file__).resolve().parents[2]
ORACLE = ROOT / "tools/benchmarks/t068_blend2d_large_oracle.json"
SCALE = ROOT / "docs/benchmarks/T068_2026-11-04_blend2d_scale.json"
ANCHOR_X = "9007199254740993"
ANCHOR_Y = "-9007199254740993"
TRANSFORMS: dict[str, list[float]] = {
    "hard4_long": [2.0, 0.0, 0.0, 2.0, 5.0, -3.0],
    "round256": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
    "cross64_sparse_erase": [0.0, 1.0, -1.0, 0.0, 20.0, -4.0],
    "transparent_noop": [1.0, 0.0, 0.5, 1.0, -5.0, 2.0],
}


def _decode_coverage(text: Any, side: int) -> set[int]:
    """Reject oversized, truncated, nonbinary, or concatenated DEFLATE data."""
    if not isinstance(text, str) or not 1 <= len(text) <= 200_000:
        raise ValueError("Invalid large-oracle encoding")
    try:
        encoded = base64.b64decode(text, validate=True)
        stream = zlib.decompressobj()
        decoded = stream.decompress(encoded, side * side + 1)
        if (len(decoded) != side * side or not stream.eof or stream.unused_data
                or stream.unconsumed_tail or stream.flush()):
            raise ValueError("Invalid large-oracle bitmap bounds")
    except (ValueError, zlib.error) as exc:
        raise ValueError("Invalid large-oracle bitmap") from exc
    if any(v not in (0, 1) for v in decoded):
        raise ValueError("Nonbinary large-oracle coverage")
    return {i for i, covered in enumerate(decoded) if covered}


def parse_oracle(payload: dict[str, Any]) -> dict[tuple[int, str], set[int]]:
    """Validate source specification, inverse view mapping, mask and coverage."""
    expected_keys = {(side, c["id"]) for side in SIDES for c in CASES}
    rows = payload.get("cases")
    if (payload.get("schema") != 1 or payload.get("generator") !=
            "tests/drawing_t068_blend2d_large_oracle.gd"
            or payload.get("sides") != list(SIDES)
            or payload.get("anchor_x") != ANCHOR_X or payload.get("anchor_y") != ANCHOR_Y
            or not isinstance(payload.get("godot_version"), str)
            or not payload["godot_version"].startswith("4.8-beta2")
            or not isinstance(rows, list) or len(rows) != len(expected_keys)):
        raise ValueError("Invalid Godot large-oracle envelope")
    identifiers = [(r.get("side"), r.get("id")) for r in rows if isinstance(r, dict)]
    if len(identifiers) != len(rows) or len(set(identifiers)) != len(rows) or set(identifiers) != expected_keys:
        raise ValueError("Missing or duplicate large-oracle case")
    parsed = {}
    cases = {c["id"]: c for c in CASES}
    for row in rows:
        side, case_id = row["side"], row["id"]
        spec = cases[case_id]
        coefficients = TRANSFORMS[case_id]
        local = [[side / 2 + x, side / 2 + y] for x, y in spec["path"]]
        if (row.get("width") != spec["width"] or row.get("paint") != list(spec["paint"])
                or row.get("erase") is not spec["erase"] or row.get("selection") != spec["selection"]
                or row.get("relative_path") != [list(p) for p in spec["path"]]
                or row.get("local_path") != local or row.get("transform") != coefficients
                or not isinstance(row.get("view_path"), list)
                or len(row["view_path"]) != len(local)):
            raise ValueError(f"Large-oracle specification modified: {side}/{case_id}")
        xx, xy, yx, yy, tx, ty = coefficients
        determinant = xx * yy - xy * yx
        if not math.isfinite(determinant) or abs(determinant) < 0.001:
            raise ValueError("Invalid oracle transform")
        for (x, y), view in zip(local, row["view_path"]):
            if (not isinstance(view, list) or len(view) != 2
                    or any(type(v) not in (int, float) or not math.isfinite(v) for v in view)
                    or abs(view[0] - (xx * x + yx * y + tx)) > 1e-5
                    or abs(view[1] - (xy * x + yy * y + ty)) > 1e-5):
                raise ValueError(f"Invalid transformed large-oracle pointer: {side}/{case_id}")
            inverse_x = (yy * (view[0] - tx) - yx * (view[1] - ty)) / determinant
            inverse_y = (xx * (view[1] - ty) - xy * (view[0] - tx)) / determinant
            if abs(inverse_x - x) > 1e-5 or abs(inverse_y - y) > 1e-5:
                raise ValueError("Large-oracle inverse mapping is not exact")
        covered = _decode_coverage(row.get("coverage_deflate_base64"), side)
        if (not covered or type(row.get("coverage_count")) is not int
                or row["coverage_count"] != len(covered)
                or row.get("blank_source_changed_pixels") !=
                (0 if spec["erase"] or spec["paint"][3] == 0 else len(covered))):
            raise ValueError(f"Godot coverage count/blank changed mismatch: {side}/{case_id}")
        selection = selection_bytes(side, spec["selection"])
        if any(not selection[i] for i in covered):
            raise ValueError(f"Godot large-oracle coverage escaped selection: {side}/{case_id}")
        parsed[side, case_id] = covered
    return parsed


def _changed_at(source: bytes, index: int, paint: tuple[int, int, int, int], erase: bool) -> bool:
    """Different stencil pixels only alter the final RGBA8 if paint changes them."""
    offset = index * 4
    before = tuple(source[offset:offset + 4])
    after = (0, 0, 0, 0) if erase else source_over(paint, before)
    return after != before


def compare(oracle: dict[str, Any], native: dict[str, Any],
            native_path: Path = SCALE) -> dict[str, Any]:
    """Compute every mismatch from complete independently verified bitmaps."""
    # Reject substituted in-memory data: the comparison is specifically of the
    # checked-in Godot fixture and the independently replayed native runs.
    if (oracle != json.loads(ORACLE.read_text(encoding="utf-8"))
            or native != json.loads(native_path.read_text(encoding="utf-8"))):
        raise ValueError("Unpinned large-oracle or native scale evidence")
    godot = parse_oracle(oracle)
    validate_evidence(native)
    entries = []
    native_runs = native["runs"]
    for run_number, run in enumerate(native_runs, 1):
        for row in run["rows"]:
            side, case_id = row["side"], row["id"]
            case = next(c for c in CASES if c["id"] == case_id)
            theirs = _unpack_coverage(side, row["coverage_zlib_base64"])
            ours = godot[side, case_id]
            missing, extra = sorted(ours - theirs), sorted(theirs - ours)
            source = source_bytes(side)
            pixel_mismatches = sum(_changed_at(source, index, case["paint"], case["erase"])
                                   for index in missing + extra)
            entries.append({
                "run": run_number, "side": side, "id": case_id,
                "godot_coverage": len(ours), "native_coverage": len(theirs),
                "missing_count": len(missing), "extra_count": len(extra),
                "rgba8_mismatched_pixels": pixel_mismatches,
                "first_missing": missing[:12], "first_extra": extra[:12],
            })
    return {
        "schema": 1,
        "godot_oracle_sha256": hashlib.sha256(ORACLE.read_bytes()).hexdigest(),
        "native_scale_sha256": hashlib.sha256(native_path.read_bytes()).hexdigest(),
        "runs": len(native_runs), "comparisons": len(entries), "rows": entries,
        "summary": {
            "nonparity_coverage": sum(bool(r["missing_count"] or r["extra_count"]) for r in entries),
            "nonparity_rgba8": sum(r["rgba8_mismatched_pixels"] > 0 for r in entries),
            "total_missing_pixels": sum(r["missing_count"] for r in entries),
            "total_extra_pixels": sum(r["extra_count"] for r in entries),
        },
        "limitations": [
            "Godot oracle is empty-source coverage only; RGBA8 recomposed with independent canonical formula",
            "Native A8 stencil is binary threshold 128 with pixel-local selection, not transformed four-corner scope",
            "Existing full-tile native trials are reused; no matched Godot CPU timing or GPU presentation",
        ],
    }


@lru_cache(maxsize=1)
def _pinned_comparison() -> dict[str, Any]:
    """Replay reference artifacts only once when checking many mutations."""
    oracle = json.loads(ORACLE.read_text(encoding="utf-8"))
    native = json.loads(SCALE.read_text(encoding="utf-8"))
    return compare(oracle, native)


def validate_comparison(payload: dict[str, Any], oracle: dict[str, Any], native: dict[str, Any]) -> None:
    if (oracle != json.loads(ORACLE.read_text(encoding="utf-8"))
            or native != json.loads(SCALE.read_text(encoding="utf-8"))
            or payload != _pinned_comparison()):
        raise ValueError("Large parity evidence does not replay against pinned fixtures")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--oracle", type=Path, default=ORACLE)
    parser.add_argument("--native-evidence", type=Path, default=SCALE)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.oracle.resolve() != ORACLE.resolve():
        parser.error("Reproduction requires the checked-in Godot coverage fixture")
    if args.output.resolve() in (args.oracle.resolve(), args.native_evidence.resolve()):
        parser.error("Output must not overwrite either source evidence file")
    oracle = json.loads(args.oracle.read_text(encoding="utf-8"))
    native = json.loads(args.native_evidence.read_text(encoding="utf-8"))
    result = compare(oracle, native, args.native_evidence)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"T068_LARGE_PARITY_PASSED: {result['comparisons']} verified Godot/native "
          f"comparisons; {result['summary']['nonparity_coverage']} coverage and "
          f"{result['summary']['nonparity_rgba8']} RGBA8 non-parity cases")


if __name__ == "__main__":
    main()
