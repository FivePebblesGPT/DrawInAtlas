#!/usr/bin/env python3
"""T-068: detached native whole-pixel convex scope vs AtlasFill._allows_pixel.

Uses the real Godot 4.8b2 Atlas scope fixture. This isolates transformed
four-corner eligibility, NOT Blend2D AA raster geometry or physical latency.
"""

from __future__ import annotations

import argparse
import base64
import ctypes
import hashlib
import json
import math
import platform
import tempfile
from pathlib import Path
from typing import Any

from t068_blend2d_brush import NativeBrush, compile_bridge
from t068_blend2d_cpu import PINNED_SOURCE_SHA256, ROOT, verify_archive

ORACLE = ROOT / "tools/benchmarks/t068_quad_scope_oracle.json"
ORACLE_SHA256 = "de2511fa9b6a902662b633dc5a6b99a53fc51cc141d7a4333e39255be6264a0f"
CASE_IDS = ("rect_identity", "rotated", "shear", "mirror", "nonuniform_density",
            "diamond", "disabled", "empty_enabled")
SIDE = 64


class QuadScope:
    """Checked ctypes facade for a native detached 0/1 selection bitmap."""

    def __init__(self, library: Path) -> None:
        native = ctypes.CDLL(str(library))
        version = native.t068_blend2d_brush_abi_version
        version.restype = ctypes.c_int32
        if version() != 1:
            raise RuntimeError("Unexpected Blend2D bridge version")
        self.function = native.t068_blend2d_quad_selection
        self.function.restype = ctypes.c_int32
        self.function.argtypes = (ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int32,
                                  ctypes.c_void_p, ctypes.c_uint64, ctypes.c_double,
                                  ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int32,
                                  ctypes.c_int32)

    def render(self, case: dict[str, Any], side: int = SIDE) -> bytes:
        """Generate native eligibility; do not accept shortened/nonbinary output."""
        transform = case["transform"]
        polygon = case["polygon"]
        if (not 1 <= side <= 2048 or len(transform) != 6 or
                len(polygon) > 32 or any(len(p) != 2 for p in polygon) or
                any(not math.isfinite(float(v)) for v in transform + [v for p in polygon for v in p])):
            raise ValueError("Invalid quad scope coefficients")
        t = (ctypes.c_double * 6)(*transform)
        vertices = (ctypes.c_double * (2 * len(polygon)))(*(v for pair in polygon for v in pair))
        output = (ctypes.c_uint8 * (side * side))()
        count = self.function(output, side * side, side, t, ctypes.sizeof(t),
                              case["density"], vertices if polygon else None,
                              ctypes.sizeof(vertices), len(polygon), int(case["enabled"]))
        if count < 0:
            raise RuntimeError(f"Native quad selection rejected input: {count}")
        mask = bytes(output)
        if any(value not in (0, 1) for value in mask) or count != mask.count(1):
            raise AssertionError("Native quad mask is not binary or complete")
        return mask


def load_oracle() -> dict[str, Any]:
    """Pin generator, metadata and each complete Godot mask, not just counts."""
    if hashlib.sha256(ORACLE.read_bytes()).hexdigest() != ORACLE_SHA256:
        raise ValueError("Godot quad fixture differs from pinned file")
    oracle = json.loads(ORACLE.read_text(encoding="utf-8"))
    rows = oracle.get("cases")
    if (oracle.get("schema") != 1 or oracle.get("side") != SIDE or
            oracle.get("generator") != "tests/drawing_t068_quad_scope_oracle.gd" or
            not oracle.get("godot_version", "").startswith("4.8-beta2") or
            not isinstance(rows, list) or tuple(r.get("id") for r in rows) != CASE_IDS):
        raise ValueError("Invalid Godot quad fixture")
    for row in rows:
        try:
            mask = base64.b64decode(row["mask_base64"], validate=True)
        except (ValueError, KeyError) as error:
            raise ValueError("Invalid quad mask encoding") from error
        if (len(mask) != SIDE * SIDE or mask.count(1) != row.get("allowed") or
                any(v not in (0, 1) for v in mask)):
            raise ValueError("Invalid Godot scope mask contents")
    return oracle


def screen(library: Path, runs: int = 2) -> dict[str, Any]:
    if runs != 2:
        raise ValueError("Two independent deterministic runs are required")
    oracle = load_oracle()
    native = QuadScope(library)
    reports = []
    for _ in range(runs):
        rows = []
        for case in oracle["cases"]:
            expected = base64.b64decode(case["mask_base64"], validate=True)
            actual = native.render(case)
            missing = [i for i, (a, b) in enumerate(zip(expected, actual)) if a and not b]
            extra = [i for i, (a, b) in enumerate(zip(expected, actual)) if b and not a]
            rows.append({"id": case["id"], "native_allowed": actual.count(1),
                         "mask_sha256": hashlib.sha256(actual).hexdigest(),
                         "missing_indices": missing, "extra_indices": extra})
        reports.append(rows)
    result = {"schema": 1, "source_sha256": PINNED_SOURCE_SHA256,
              "godot_oracle_sha256": ORACLE_SHA256,
              "comparison": "all four transformed raster pixel corners inside convex board-space scope",
              "runs": reports, "summary": {"runs": runs, "cases_per_run": len(CASE_IDS),
                                            "mismatched_cases": sum(bool(r["missing_indices"] or r["extra_indices"])
                                                                    for run in reports for r in run)},
              "limitations": ["CPU mask precomputation only; no native Godot publication or GPU timings",
                              "Fixtures avoid exact polygon-edge/corner ties; boundary inclusion needs separate parity",
                              "Existing Blend2D A8 brush stencil retains geometric mismatches"]}
    validate_evidence(result)
    return result


def validate_evidence(payload: dict[str, Any]) -> None:
    """Rebuild expected masks and reject any missing/altered comparison row."""
    oracle = load_oracle()
    runs = payload.get("runs")
    if (payload.get("schema") != 1 or payload.get("source_sha256") != PINNED_SOURCE_SHA256 or
            payload.get("godot_oracle_sha256") != ORACLE_SHA256 or
            not isinstance(runs, list) or len(runs) != 2):
        raise ValueError("Invalid quad evidence envelope")
    sig = None
    mismatch = 0
    for rows in runs:
        if not isinstance(rows, list) or [r.get("id") for r in rows] != list(CASE_IDS):
            raise ValueError("Missing/duplicate quad comparison")
        current = []
        for row, case in zip(rows, oracle["cases"]):
            expected = base64.b64decode(case["mask_base64"], validate=True)
            missing, extra = row.get("missing_indices"), row.get("extra_indices")
            if (not isinstance(missing, list) or not isinstance(extra, list)
                    or any(type(i) is not int or i < 0 or i >= SIDE * SIDE for i in missing + extra)
                    or missing != sorted(set(missing)) or extra != sorted(set(extra))
                    or any(expected[i] != 1 for i in missing)
                    or any(expected[i] != 0 for i in extra)):
                raise ValueError("Invalid quad discrepancy indices")
            actual = bytearray(expected)
            for i in missing:
                actual[i] = 0
            for i in extra:
                actual[i] = 1
            if (row.get("native_allowed") != actual.count(1) or
                    row.get("mask_sha256") != hashlib.sha256(actual).hexdigest()):
                raise ValueError("Quad evidence cannot be reconstructed")
            mismatch += bool(missing or extra)
            current.append((row["native_allowed"], row["mask_sha256"], missing, extra))
        if sig is not None and sig != current:
            raise ValueError("Native quad masks differ across runs")
        sig = current
    if payload.get("summary") != {"runs": 2, "cases_per_run": len(CASE_IDS),
                                   "mismatched_cases": mismatch}:
        raise ValueError("Quad evidence summary inconsistent")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--library-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    verify_archive(args.archive)
    with tempfile.TemporaryDirectory(prefix="t068-quad-") as destination:
        bridge = compile_bridge(args.source, args.library_dir, Path(destination))
        evidence = screen(bridge)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"T068_QUAD_SCOPE_PASSED: 16 native/Godot mask comparisons; "
          f"{evidence['summary']['mismatched_cases']} mismatched cases")


if __name__ == "__main__":
    main()
