"""Pure-Python contracts for the T-095 opt-in owner-device trace analyzer."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "analyze_t095_trace.py"
spec = importlib.util.spec_from_file_location("t095_trace_analyzer", SCRIPT)
assert spec and spec.loader
analyzer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyzer)


def record(*, backend: str = "Legacy", start: int = 1000) -> dict:
    """Return a minimal schema-accurate export fixture."""
    return {
        "schema": 1, "capture_kind": "engine_timing_only", "backend": backend,
        "zoom": 7.86, "brush_width_px": 60.0,
        "viewport_px": [520, 400], "image_size_px": [512, 512],
        "down_us": start, "release_us": start + 100_000,
        "commit_us": start + 180_000,
        "samples_received": 6, "segments_staged": 6, "max_pending": 4,
        "sample_to_stage_us": [500, 1000, 2000, 3000],
        "sample_to_stage_total": 7, "max_sample_to_stage_us": 7000,
        "stage_batches_us": [300, 100, 400], "stage_batch_total": 3,
        "frame_phase_total": 5, "frame_post_draw_matches": 2,
        "frame_preview_stage_submissions": 3,
        "preview_stage_post_draw_matches": 2,
        "preview_input_post_draw_matches": 1,
        "max_frame_oldest_pending_age_us": 9900,
        "frame_phases_us": [
            {"full_draw_cpu_us": 1000, "compose_cpu_us": 150,
             "texture_cpu_us": 100, "preview_index_cpu_us": 20,
             "oldest_pending_age_us": 6000,
             "preview_input_to_frame_end_us": 9500,
             "preview_input_to_post_draw_us": 12000,
             "frame_end_to_post_draw_us": 2500},
            {"full_draw_cpu_us": 7000, "compose_cpu_us": 1000,
             "texture_cpu_us": 900, "preview_index_cpu_us": 40,
             "oldest_pending_age_us": 8900,
             "preview_input_to_frame_end_us": 0},
        ],
    }


class T095TraceAnalyzerTest(unittest.TestCase):
    def test_retained_window_and_absent_callbacks(self) -> None:
        summary = analyzer.summarize_stroke(record(), 1)
        stage = summary["metrics"]["sample_to_stage"]
        self.assertEqual(stage["retained"], 4)
        self.assertEqual(stage["total"], 7)
        self.assertTrue(stage["truncated"])
        self.assertEqual(stage["p50_ms"], 1.0)
        self.assertEqual(stage["p95_ms"], 3.0)
        self.assertEqual(summary["lifetime_max_ms"]["sample_to_stage"], 7.0)
        self.assertEqual(summary["metrics"]["preview_input_to_callback"]["retained"], 1)
        self.assertEqual(summary["metrics"]["preview_input_to_callback"]["p95_ms"], 12.0)
        self.assertEqual(summary["metrics"]["preview_input_to_draw"]["retained"], 2)
        self.assertEqual(summary["metrics"]["preview_input_to_draw"]["p50_ms"], 0.0)
        self.assertEqual(summary["metrics"]["full_draw"]["total"], 5)
        self.assertEqual(summary["metrics"]["full_draw"]["retained"], 2)
        self.assertEqual(summary["release_to_commit_ms"], 80.0)
        # The real Godot exporter emits [0,0] for a document with no bounds.
        empty_bounds = record()
        empty_bounds["image_size_px"] = [0, 0]
        self.assertEqual(analyzer.summarize_stroke(empty_bounds, 2)["image_size_px"], [0, 0])

    def test_empty_window_does_not_fake_zero_latency(self) -> None:
        row = record()
        row["frame_phases_us"] = []
        row["sample_to_stage_us"] = []
        row["sample_to_stage_total"] = 200
        summary = analyzer.summarize_stroke(row, 1)
        self.assertIsNone(summary["metrics"]["preview_input_to_callback"]["p95_ms"])
        self.assertIsNone(summary["metrics"]["sample_to_stage"]["p50_ms"])
        self.assertEqual(summary["metrics"]["sample_to_stage"]["total"], 200)

    def test_invalid_schema_units_and_counters_fail_closed(self) -> None:
        corruptions = [
            {"schema": 2}, {"capture_kind": "physical_input_to_photon"},
            {"backend": "malicious\nname"}, {"zoom": "7.86"},
            {"brush_width_px": float("nan")}, {"brush_width_px": 10**1000},
            {"release_us": 100},
            {"sample_to_stage_total": 1}, {"frame_phase_total": 1},
            {"frame_post_draw_matches": 6},
            {"preview_input_post_draw_matches": 4},
            {"stage_batches_us": [True]},
            {"frame_phases_us": [{"full_draw_cpu_us": -1}]},
            {"sample_to_stage_us": list(range(4097))},
        ]
        for edits in corruptions:
            with self.subTest(edits=list(edits)):
                row = record()
                row.update(edits)
                with self.assertRaises(analyzer.TraceError):
                    analyzer.summarize_stroke(row, 1)

    def test_inconsistent_retained_histories_fail_closed(self) -> None:
        """Never report a false lifetime maximum or impossible callback coverage."""
        corruptions = [
            ("sample_max_under_retained", {"max_sample_to_stage_us": 2_999}),
            ("pending_max_under_retained", {"max_frame_oldest_pending_age_us": 8_899}),
            ("callback_count_under_retained", {"frame_post_draw_matches": 0}),
            ("input_match_count_under_retained", {"preview_input_post_draw_matches": 0}),
            ("stage_matches_exceed_submissions", {"preview_stage_post_draw_matches": 4}),
            ("stage_to_draw_without_submission", {
                "frame_preview_stage_submissions": 0,
                "frame_phases_us": [
                    {"preview_stage_to_frame_end_us": 400},
                ],
            }),
            ("stage_callback_without_match", {
                "preview_stage_post_draw_matches": 0,
                "frame_phases_us": [
                    {"preview_stage_to_frame_end_us": 400,
                     "preview_stage_to_post_draw_us": 800,
                     "frame_end_to_post_draw_us": 400},
                ],
            }),
            ("callback_delay_without_frame_match", {
                "frame_phases_us": [
                    {"preview_input_to_post_draw_us": 900},
                ],
            }),
        ]
        for name, edits in corruptions:
            with self.subTest(name=name):
                row = record()
                row.update(edits)
                with self.assertRaises(analyzer.TraceError):
                    analyzer.summarize_stroke(row, 1)

    def test_different_backends_or_zoom_never_aggregate_together(self) -> None:
        a = analyzer.summarize_stroke(record(), 1)
        b = analyzer.summarize_stroke(record(start=200_000), 2)
        changed = record(backend="Hokusai", start=450_000)
        changed["zoom"] = 4.5
        c = analyzer.summarize_stroke(changed, 3)
        report = analyzer.aggregate([a, b, c])
        self.assertEqual([group["strokes"] for group in report["groups"]], [2, 1])
        self.assertEqual(report["groups"][0]["release_to_commit"]["p95_ms"], 80)
        self.assertIn("NOT physical", analyzer.human_report(report))

    def test_multiple_jsonl_files_and_command_line_json(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "first.jsonl"
            second = Path(directory) / "second.jsonl"
            first.write_text(json.dumps(record()) + "\n", encoding="utf8")
            second.write_text("\n" + json.dumps(record(start=220_000)) + "\n", encoding="utf8")
            completed = subprocess.run([sys.executable, str(SCRIPT), "--json", str(first), str(second)],
                                       capture_output=True, text=True, check=False)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            data = json.loads(completed.stdout)
            self.assertEqual(len(data["strokes"]), 2)
            self.assertEqual(data["measurement"], "godot_engine_only_not_input_to_photon")
            self.assertEqual(len(data["groups"]), 2)
            self.assertEqual([group["strokes"] for group in data["groups"]], [1, 1])
            self.assertEqual(data["schema"], "t095_trace_analysis_v3")
            self.assertEqual(data["cohort_boundary"],
                             "input_file_and_observed_timestamp_epoch_plus_brush_settings_not_verified_hardware")
            self.assertNotIn("private", completed.stdout)
            second.write_text("{\"schema\": 1\n", encoding="utf8")
            failed = subprocess.run([sys.executable, str(SCRIPT), str(first), str(second)],
                                    capture_output=True, text=True, check=False)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("T095_TRACE_ANALYSIS_FAILED", failed.stderr)
            self.assertEqual(failed.stdout, "")

    def test_separate_input_files_never_pool_indistinguishable_hardware(self) -> None:
        """Identical canvas settings cannot prove identical owner hardware."""
        with tempfile.TemporaryDirectory() as directory:
            slow = Path(directory) / "device_a.jsonl"
            fast = Path(directory) / "device_b.jsonl"
            slow.write_text(json.dumps(record()) + "\n", encoding="utf8")
            second = record(start=240_000)
            second["commit_us"] = second["release_us"] + 5_000
            fast.write_text(json.dumps(second) + "\n", encoding="utf8")
            analysis = analyzer.aggregate(analyzer.read_traces([slow, fast]))
            self.assertEqual(len(analysis["groups"]), 2)
            self.assertEqual([g["source_file_index"] for g in analysis["groups"]], [1, 2])
            self.assertEqual([g["release_to_commit"]["p95_ms"] for g in analysis["groups"]],
                             [80.0, 5.0])
            self.assertEqual([s["source_file_index"] for s in analysis["strokes"]], [1, 2])
            self.assertIn("file #1", analyzer.human_report(analysis))
            self.assertIn("file #2", analyzer.human_report(analysis))
            self.assertNotIn("device_a.jsonl", analyzer.human_report(analysis))

    def test_multiple_strokes_from_one_file_remain_a_single_cohort(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "same-file.jsonl"
            rows = [record(), record(start=250_000)]
            path.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf8")
            analysis = analyzer.aggregate(analyzer.read_traces([path]))
            self.assertEqual(len(analysis["groups"]), 1)
            self.assertEqual(analysis["groups"][0]["strokes"], 2)
            self.assertEqual(analysis["groups"][0]["source_file_index"], 1)

    def test_restarted_clock_inside_one_file_does_not_pool_strokes(self) -> None:
        """An appended JSONL file can span Godot launches with reset ticks."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "appended.jsonl"
            rows = [record(start=1_000), record(start=250_000),
                    record(start=900), record(start=280_000)]
            for row in rows[2:]:
                row["commit_us"] = row["release_us"] + 5_000
            path.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf8")
            analysis = analyzer.aggregate(analyzer.read_traces([path]))
            self.assertEqual([stroke["timestamp_epoch_index"] for stroke in analysis["strokes"]],
                             [1, 1, 2, 2])
            self.assertEqual([group["strokes"] for group in analysis["groups"]], [2, 2])
            self.assertEqual([group["release_to_commit"]["p95_ms"]
                              for group in analysis["groups"]], [80.0, 5.0])
            self.assertEqual([group["timestamp_epoch_index"]
                              for group in analysis["groups"]], [1, 2])
            self.assertIn("epoch #2", analyzer.human_report(analysis))
            self.assertNotIn("appended.jsonl", analyzer.human_report(analysis))

    def test_append_reset_with_overlapping_commit_intervals_is_isolated(self) -> None:
        """Non-overlapping completed strokes cannot overlap within one Canvas session.

        A restarted clock may advance beyond the preceding down timestamp
        while remaining behind its commit timestamp. Comparing only down_us
        misses that observable boundary and pools unrelated device timings.
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "overlapping-clocks.jsonl"
            first = record(start=1_000_000)  # commit=1_180_000
            restarted = record(start=1_150_000)  # down increases, but before commit
            restarted["commit_us"] = restarted["release_us"] + 5_000
            later = record(start=1_400_000)
            later["commit_us"] = later["release_us"] + 5_000
            path.write_text("".join(json.dumps(row) + "\n" for row in
                                    (first, restarted, later)), encoding="utf8")
            analysis = analyzer.aggregate(analyzer.read_traces([path]))
            self.assertEqual([s["timestamp_epoch_index"] for s in analysis["strokes"]],
                             [1, 2, 2])
            self.assertEqual([g["strokes"] for g in analysis["groups"]], [1, 2])
            self.assertEqual([g["release_to_commit"]["p95_ms"]
                              for g in analysis["groups"]], [80.0, 5.0])
            # No file names, unverified device IDs, or fake photon latency.
            self.assertNotIn(path.name, analyzer.human_report(analysis))
            self.assertIn("NOT physical", analyzer.human_report(analysis))

    def test_oversized_record_fails_without_partial_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "huge.jsonl"
            path.write_bytes(b" " * (analyzer.MAX_LINE_BYTES + 1) + b"\n")
            with self.assertRaises(analyzer.TraceError):
                analyzer.read_traces([path])


if __name__ == "__main__":
    unittest.main()
