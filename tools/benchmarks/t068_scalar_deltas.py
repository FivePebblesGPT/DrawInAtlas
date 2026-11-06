#!/usr/bin/env python3
"""T-068: detached scalar brush, canonical 12-byte sparse RGBA8 delta wire.

This is a *transfer-size* screen, not a Godot transaction, CPU timing,
texture upload or input-to-visible benchmark. Small output is checked against
real Godot pixels; large output uses Godot coverage and Python compositing.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from functools import lru_cache
import struct
import tempfile
from pathlib import Path
from typing import Any

from t068_scalar_hard_brush import (LARGE_SHA256, ROOT, SMALL_SHA256, SOURCE,
                                    ScalarBrush, compile_kernel)
from t068_scalar_rgba8 import fixtures
from t068_skia_brush import canonical_pixels

EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_scalar_deltas.json"
MAX_CHANGED = 65536
LIMITATIONS = [
    "Detached C++17 ctypes ABI: native payload bytes only; no measured Godot marshaling or document publication",
    "16 small Godot cases have actual pixel-output oracles; 12 large cases have Godot coverage and independently composited patterned pixels",
    "Caller bounds output to 65536 changes; denser gestures must retry with a larger capacity or use a full tile",
    "No native SIMD, memory/RSS peak, GPU upload, physical Windows/Linux p95 or standalone release result",
]


def reference(case: tuple[Any, ...]) -> tuple[dict[str, Any], bytes]:
    """Construct the full sparse wire from independent canonical before/after."""
    identifier, side, source, _path, _width, _selection, indices, paint, erase, godot_sha = case
    expected = canonical_pixels(source, indices, paint, erase)
    full_sha = hashlib.sha256(expected).hexdigest()
    if godot_sha is not None and full_sha != godot_sha:
        raise ValueError(f"Actual Godot pixel output differs: {identifier}")
    records = bytearray(b"\x00\x00\x00\x00")
    changed = 0
    for index in sorted(indices):
        offset = index * 4
        before, after = source[offset:offset + 4], expected[offset:offset + 4]
        if before != after:
            records.extend(struct.pack("<I", index) + before + after)
            changed += 1
    struct.pack_into("<I", records, 0, changed)
    if changed > MAX_CHANGED:
        raise ValueError(f"Case exceeds pinned sparse transfer budget: {identifier}")
    row = {
        "id": identifier,
        "side": side,
        "covered": len(indices),
        "changed_pixels": changed,
        "source_sha256": hashlib.sha256(source).hexdigest(),
        "full_rgba8_sha256": full_sha,
        "payload_sha256": hashlib.sha256(records).hexdigest(),
        "payload_bytes": len(records),
        "full_tile_bytes": len(source),
        "transfer_bytes_avoided": len(source) - len(records),
        "oracle": "godot_pixels" if godot_sha is not None else "godot_coverage_python_rgba8",
    }
    return row, bytes(records)


def reconstruct(source: bytes, payload: bytes) -> bytes:
    """Fail-closed independently decoded stream, including original bytes."""
    if len(payload) < 4:
        raise ValueError("Truncated delta header")
    count = struct.unpack_from("<I", payload, 0)[0]
    if count > len(source) // 4 or len(payload) != 4 + count * 12:
        raise ValueError("Invalid delta record count/size")
    output = bytearray(source)
    previous = -1
    for offset in range(4, len(payload), 12):
        index = struct.unpack_from("<I", payload, offset)[0]
        if index <= previous or index >= len(source) // 4:
            raise ValueError("Noncanonical delta order/index")
        previous = index
        at = index * 4
        before, after = payload[offset + 4:offset + 8], payload[offset + 8:offset + 12]
        if before != source[at:at + 4] or before == after:
            raise ValueError("Stale or redundant delta")
        output[at:at + 4] = after
    return bytes(output)


def run(library: Path) -> dict[str, Any]:
    native = ScalarBrush(library)
    cases = fixtures()
    rows = []
    for case in cases:
        row, expected_wire = reference(case)
        rows.append((row, expected_wire))
    runs = []
    for _ in range(2):
        observed = []
        for case, (row, expected_wire) in zip(cases, rows, strict=True):
            identifier, side, source, path, width, selection, _, paint, erase, _ = case
            payload = native.deltas(source, side, path, width, selection, paint,
                                    erase, max_changes=min(MAX_CHANGED, side * side))
            if payload != expected_wire or hashlib.sha256(reconstruct(source, payload)).hexdigest() != row["full_rgba8_sha256"]:
                raise AssertionError(f"Native sparse RGBA8 differs from canonical pixels: {identifier}")
            observed.append(row)
        runs.append(observed)
    payload = {
        "schema": 1,
        "native_source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "small_oracle_sha256": SMALL_SHA256,
        "large_oracle_sha256": LARGE_SHA256,
        "max_changed_pixels": MAX_CHANGED,
        "runs": runs,
        "summary": {"runs": 2, "cases_per_run": len(cases),
                    "exact_sparse_rgba8": 2 * len(cases),
                    "total_payload_bytes_per_run": sum(row["payload_bytes"] for row, _ in rows),
                    "total_full_tile_bytes_per_run": sum(row["full_tile_bytes"] for row, _ in rows)},
        "limitations": LIMITATIONS,
    }
    validate(payload)
    return payload


@lru_cache(maxsize=1)
def _reference_rows() -> tuple[dict[str, Any], ...]:
    """Precompute pinned fixture rows for multiple negative validation tests."""
    return tuple(reference(case)[0] for case in fixtures())


def validate(payload: dict[str, Any]) -> None:
    """Reject tampered claims instead of trusting saved hashes/counts."""
    if type(payload) is not dict:
        raise ValueError("Invalid scalar delta evidence root")
    rows = list(_reference_rows())
    expected_summary = {
        "runs": 2, "cases_per_run": len(rows), "exact_sparse_rgba8": 2 * len(rows),
        "total_payload_bytes_per_run": sum(row["payload_bytes"] for row in rows),
        "total_full_tile_bytes_per_run": sum(row["full_tile_bytes"] for row in rows),
    }
    if (payload.get("schema") != 1 or payload.get("max_changed_pixels") != MAX_CHANGED or
        payload.get("native_source_sha256") != hashlib.sha256(SOURCE.read_bytes()).hexdigest() or
        payload.get("small_oracle_sha256") != SMALL_SHA256 or
        payload.get("large_oracle_sha256") != LARGE_SHA256 or
        type(payload.get("runs")) is not list or payload["runs"] != [rows, rows] or
        payload.get("summary") != expected_summary or payload.get("limitations") != LIMITATIONS):
        raise ValueError("Invalid or non-replayable scalar sparse evidence")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="t068-scalar-deltas-") as folder:
        evidence = run(compile_kernel(Path(folder)))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"T068_SCALAR_DELTAS_PASSED: {evidence['summary']['exact_sparse_rgba8']} byte-exact sparse replay cases")


if __name__ == "__main__":
    main()
