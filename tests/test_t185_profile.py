"""Reject incomplete/mislabelled benchmark logs before recording evidence."""
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools/run_t185_profile.py"
spec = importlib.util.spec_from_file_location("t185_profile", SCRIPT)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TestT185Profiler(unittest.TestCase):
    def test_nearest_rank_percentile(self) -> None:
        self.assertEqual(module.distribution([1, 2, 3, 10, 100])["p95"], 100)
        self.assertEqual(module.distribution([10, 1, 4, 8])["p50"], 4)
        with self.assertRaises(ValueError):
            module.distribution([])

    def fixture(self) -> str:
        entries = []
        for index, (zoom, kind) in enumerate(module.EXPECTED):
            entries.append("T185_RUN " + json.dumps({
                "index": index, "zoom": zoom, "case": kind, "tool": "Eraser" if kind == "eraser" else "Brush",
                "native_backend": "Hokusai", "commit_revision_delta": 1, "input_events": 14,
                "width_px": 96, "opacity": 1, "canvas_px": [900, 600],
                "before_sha256": "a" * 64, "after_sha256": "b" * 64, "coverage": 60,
                "display_tiles_before": 0 if kind == "cold_brush" else 4,
                "native_stage": {"batch_calls": 4, "dirty_entries": 4, "unique_tiles": 2,
                                 "revisited_entries": 2, "apply_us": 10,
                                 "authorize_us": 3, "dirty_query_us": 2, "stamp_us": 1, "index_us": 1},
                "native_ffi_stats": {"tile_ffi_calls": 3, "tile_pixel_stream_calls": 0,
                                     "tile_bytes_exported": index * 32 + 32},
                "first_submit_ms": 2, "first_postdraw_ms": 3, "release_to_commit_ms": 8,
                "release_to_settled_ms": 9, "total_to_settled_ms": 80,
                "post_draw_intervals_us": [15_000, 84_000], "process_frame_intervals_us": [16_000, 90_000],
                "input_delivery_intervals_us": [17_000], "frame_phases_us": [{"full_draw_cpu_us": 100}],
                "stage_cpu_us": 30, "compose_cpu_us": 50, "texture_cpu_us": 2,
                "preview_index_cpu_us": 1, "commit_cpu_us": 3, "bytes_uploaded": 1024}))
        return "\n".join(entries + ["T185_PROFILE_PASSED cases=8 failures=0"])

    def test_valid_complete_eight(self) -> None:
        self.assertEqual(len(module.extract(self.fixture())), 8)

    def test_incomplete_and_wrong_backend_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "8 complete"):
            module.extract("\n".join(self.fixture().splitlines()[1:]))
        with self.assertRaisesRegex(ValueError, "metadata"):
            module.extract(self.fixture().replace('"Hokusai"', '"Legacy"', 1))
        with self.assertRaisesRegex(ValueError, "cache state"):
            module.extract(self.fixture().replace('"display_tiles_before": 0', '"display_tiles_before": 4', 1))
        with self.assertRaisesRegex(ValueError, "no committed"):
            module.extract(self.fixture().replace('"after_sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"',
                                                 '"after_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"', 1))
        with self.assertRaisesRegex(ValueError, "failures"):
            module.extract(self.fixture() + "\nT185_FAILED: something")

    def test_exit_is_required_even_if_marker_exists(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            source = path / "capture.log"
            source.write_text(self.fixture())
            output = path / "out"
            output.mkdir()
            missing_exit = module.ingest_trial(source, output, 0)
            self.assertFalse(missing_exit["valid"])
            self.assertEqual(missing_exit["exit"], 124)
            self.assertIn("no confirmed zero exit", missing_exit["validation_error"])
            source.with_suffix(".time").write_text("\tExit status: 0\n")
            valid_exit = module.ingest_trial(source, output, 1)
            self.assertTrue(valid_exit["valid"])
            self.assertEqual(valid_exit["exit"], 0)

    def test_median_and_frame_thresholds(self) -> None:
        data = module.summarize([{"valid": True, "rows": module.extract(self.fixture())}])
        row = data["0.54/cold_brush"]
        self.assertEqual(row["post_draw_intervals_us"]["long_83ms"], 1)
        self.assertEqual(row["post_draw_intervals_us"]["p95"], 84)
        self.assertEqual(row["native_tile_export_delta_bytes"]["p50"], 32)


if __name__ == "__main__":
    unittest.main()
