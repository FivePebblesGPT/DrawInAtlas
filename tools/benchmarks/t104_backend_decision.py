#!/usr/bin/env python3
"""Rebuild T-104's operation decision from pinned T-068 source/parity data.

Detached native-call times are never presented as editor timings. A backend
with even one canonical output/coverage mismatch is not an equivalent drop-in.
The report is reproducible without importing Skia, Blend2D, or a native binary.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import statistics
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "benchmarks"))
import t068_matched_brush as matched  # noqa: E402
import t068_native_memory as native_memory  # noqa: E402
import t068_skia_brush as skia_brush  # noqa: E402
import t068_visual_counterbalanced as visual  # noqa: E402

EVIDENCE = ROOT / "docs" / "benchmarks"
FILES = {
    "matched": ("T068_2026-11-04_matched_brush.json", "dafefde39ed0e16ef4c111c540b8e29387aca0b7638c32e9113045fd10392e34"),
    "memory": ("T068_2026-11-04_native_process_memory.json", "77246a21c96148caf21f533f54611dd0ce7d8ac1232e7d9b7b42185da5045d56"),
    "skia": ("T068_2026-11-04_skia_brush.json", "f1df8bef7828046e7b0fff4ed16f0f37d3a194830a96f76b50da57c9483ab37f"),
    "visual": ("T068_2026-11-04_visual_counterbalanced_software.json", "d4a23ae81b524552957cf2fc66ff345b27d5bbb677b651b9920700369f7da80f"),
}
OUTPUT = EVIDENCE / "T104_2026-11-12_backend_decision.json"


def load_pinned(key: str) -> dict[str, Any]:
    filename, expected = FILES[key]
    raw = (EVIDENCE / filename).read_bytes()
    if hashlib.sha256(raw).hexdigest() != expected:
        raise ValueError(f"Unpinned {key} evidence")
    return json.loads(raw)


def nearest_rank(values: list[int], q: float) -> int:
    """Return the retained-window nearest-rank integer percentile."""
    import math
    if not values or any(type(v) is not int or v <= 0 for v in values):
        raise ValueError("Invalid samples")
    return sorted(values)[math.ceil(q * len(values)) - 1]


def build() -> dict[str, Any]:
    pair = load_pinned("matched")
    memory = load_pinned("memory")
    skia = load_pinned("skia")
    v = load_pinned("visual")
    matched.validate(pair)
    native_memory.validate(memory)
    visual.validate(v)
    _, _, godot_cases = skia_brush.load_oracle()
    expected_ids = [case["id"] for case in godot_cases]
    if skia.get("ticket") != "T-068" or len(skia.get("runs", [])) != 2:
        raise ValueError("Missing Skia comparative runs")
    oracle_sha = hashlib.sha256(skia_brush.ORACLE_FILE.read_bytes()).hexdigest()
    skia_rows = []
    for run in skia["runs"]:
        if (run.get("godot_fixture_sha256") != oracle_sha or
            run.get("skia_version") != "144.1" or
            [r["id"] for r in run.get("cases", [])] != expected_ids):
            raise ValueError("Wrong Skia oracle or incomplete run")
        for row, spec in zip(run["cases"], godot_cases):
            if (row["godot_covered"] != len(spec["coverage_indices"]) or
                row.get("trials") != 7 or
                any(type(row.get(k)) is not int or row[k] < 0
                    for k in ("missing_godot_coverage", "extra_skia_coverage",
                              "direct_rgba8_mismatched_pixels",
                              "skia_mask_plus_canonical_blend_mismatched_pixels")) or
                row["skia_covered"] != row["godot_covered"] - row["missing_godot_coverage"] + row["extra_skia_coverage"]):
                raise ValueError("Invalid Skia case or canonical coverage")
        skia_rows.append(run["cases"])
    # Parity is assessed on the complete fixture corpus, not just cherry-picked
    # passing dabs. Transparent no-op coverage is still a geometry mismatch.
    s_fail = sorted({r["id"] for run in skia_rows for r in run
                     if any(r[k] for k in ("missing_godot_coverage", "extra_skia_coverage",
                                             "direct_rgba8_mismatched_pixels"))})
    pairs: list[dict[str, Any]] = []
    for case in pair["cases"]:
        rows = [next(r for r in run if r["id"] == case) for run in pair["runs"]]
        comparable = all(not any(row["parity"]["blend2d"][k] for k in
                                 ("missing", "extra", "pixel_mismatch")) for row in rows)
        samples = {backend: [value for row in rows for value in row["call_ns"][backend]]
                   for backend in ("scalar", "blend2d")}
        pairs.append({
            "case": case, "side": rows[0]["side"], "canonical_pixels_sha256": rows[0]["godot_pixels_sha256"],
            "blend2d_exact": comparable,
            "blend2d_missing": rows[0]["parity"]["blend2d"]["missing"],
            "blend2d_extra": rows[0]["parity"]["blend2d"]["extra"],
            "blend2d_changed_pixels_different": rows[0]["parity"]["blend2d"]["pixel_mismatch"],
            "warm_native_only_us": {backend: {
                "n": len(values), "p50": nearest_rank(values, 0.5) // 1000,
                "p95": nearest_rank(values, 0.95) // 1000,
                "max": max(values) // 1000,
            } for backend, values in samples.items()},
        })
    memory_rows = []
    for side in native_memory.SIDES:
        for backend in native_memory.BACKENDS:
            values = [r["hwm_after_call_kib"] for run in memory["runs"] for r in run
                      if r["side"] == side and r["backend"] == backend]
            memory_rows.append({"side": side, "backend": backend, "workers": len(values),
                                "linux_python_process_hwm_kib": {
                                    "p50": nearest_rank(values, 0.5),
                                    "p95": nearest_rank(values, 0.95)}})
    return {
        "schema": "t104-operation-decision-v1",
        "source_artifacts_sha256": {key: sha for key, (_, sha) in FILES.items()},
        "matching_corpus": {"cases": pairs, "scalar_exact": True,
                            "blend2d_exact_cases": sum(r["blend2d_exact"] for r in pairs),
                            "blend2d_noncomparable_cases": [r["case"] for r in pairs if not r["blend2d_exact"]],
                            "boundary": "warm preallocated Python-to-native ABI calls only; not full editor"},
        "skia": {"version": "144.1", "cases": len(expected_ids),
                 "noncomparable_cases": s_fail,
                 "boundary": "Python Skia raster-local mask/direct draws; excludes Godot and native C++ integration"},
        "memory": {"native_workers": memory_rows,
                   "boundary": "fresh Linux /proc Python worker HWM incl ctypes buffers, not Godot RSS or VRAM"},
        "editor_boundary": {
            "comparable_fixture": "T-095 real-Godot 96px opaque red 512x512, 100 synthetic pointer events, full source SHA, framebuffer and undo",
            "record": "docs/evidence/T-104-2026-11-12-operation-backends.md",
            "nativehard_warm_full_editor": "not established: 3-stroke run stalled after success marker; process exit unverified",
            "physical_input_to_photon": "not measured",
        },
        "decisions": [
            {"operation": "hard_brush_and_eraser", "default": "choose_optimized_gdscript",
             "nativehard": "defer_default_keep_optional", "blend2d": "reject_drop_in_nonparity",
             "skia": "reject_drop_in_nonparity", "hokusai": "not_comparable_preset_model"},
            {"operation": "natural_media_myb_preset", "default": "choose_optional_hokusai_with_fallback",
             "nativehard": "not_comparable_hard_model", "blend2d": "not_comparable",
             "skia": "not_comparable", "hokusai": "choose_optional_existing"},
            {"operation": "flood_fill", "default": "defer_native_keep_gdscript",
             "nativehard": "not_comparable", "blend2d": "not_comparable",
             "skia": "not_comparable", "hokusai": "not_comparable"},
            {"operation": "paths_shapes_text_antialiasing", "default": "defer_no_matched_editor_feature",
             "nativehard": "not_comparable", "blend2d": "defer_possible_future",
             "skia": "defer_possible_future", "hokusai": "not_comparable"},
            {"operation": "preview_compositing_texture_upload", "default": "choose_godot_cache",
             "nativehard": "not_comparable", "blend2d": "not_comparable",
             "skia": "not_comparable", "hokusai": "not_comparable"},
            {"operation": "tile_publication_history_undo", "default": "choose_sparse_gdscript",
             "nativehard": "not_comparable", "blend2d": "not_comparable",
             "skia": "not_comparable", "hokusai": "not_comparable"},
        ],
        "limitations": [
            "No equivalent end-to-end Godot+storage+display runs for Blend2D or Skia",
            "Godot fixed-color hard brush is not equivalent to .myb natural-media dabs",
            "Kernel warm-call CPU does not include input, preview, publication, image texture, or GPU presentation",
            "Native worker memory is not Godot RSS/VRAM; no Windows/MSVC/export evidence (T-105)",
            "All frame callbacks are software timing; no physical input-to-photon or owner acceptance",
        ],
    }


def validate(report: dict[str, Any]) -> None:
    if report != build():
        raise ValueError("Decision report diverged from pinned parity, memory or operation policy")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if args.verify:
        validate(json.loads(args.output.read_text(encoding="utf-8")))
    else:
        report = build()
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        validate(report)
    print("T104_BACKEND_DECISION_PASSED")


if __name__ == "__main__":
    main()
