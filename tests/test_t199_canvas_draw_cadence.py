"""T-199: bound Canvas draw submission gaps without using global callbacks."""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "tools/run_t185_profile.py"
spec = importlib.util.spec_from_file_location("t185_profile_t199", SOURCE)
assert spec is not None and spec.loader is not None
profile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile)


class TestCanvasDrawCadence(unittest.TestCase):
    @staticmethod
    def frame(end: int | None, callback: int | None = None, *,
              cpu: int = 1200, backlog: int = 0) -> dict[str, int]:
        phase = {"full_draw_cpu_us": cpu, "pending_input_count": backlog,
                 "oldest_pending_age_us": backlog * 1000}
        if end is not None:
            phase["frame_end_us"] = end
        if callback is not None:
            phase["frame_post_draw_callback_us"] = callback
        return phase

    def test_all_canvas_submissions_count_even_without_callbacks(self) -> None:
        row = {"frame_phases_us": [
            self.frame(100_000, 102_000), self.frame(116_000, None),
            self.frame(132_000, 134_000), self.frame(242_000, 244_000, cpu=3500, backlog=2)]}
        stats = profile.canvas_draw_cadence_diagnostics([row])
        self.assertEqual(stats["frame_end_pairs"], 3)
        self.assertEqual(stats["with_adjacent_callback_pair"], 1)
        self.assertEqual(stats["without_adjacent_callback_pair"], 2)
        self.assertEqual(stats["long_83ms"], 1)
        self.assertEqual(stats["frame_end_period_ms"]["p95"], 110)
        self.assertEqual(stats["long_events"][0]["canvas_draw_cpu_ms"], 3.5)
        self.assertEqual(stats["long_events"][0]["pending_input_count"], 2)
        self.assertTrue(stats["long_events"][0]["adjacent_callback_pair"])

    def test_does_not_join_gestures_or_fill_callback_gaps(self) -> None:
        rows = [{"frame_phases_us": [self.frame(100_000), self.frame(125_000)]},
                {"frame_phases_us": [self.frame(5_000_000), self.frame(5_014_000)]}]
        stats = profile.canvas_draw_cadence_diagnostics(rows)
        self.assertEqual(stats["frame_end_pairs"], 2)
        self.assertEqual(stats["long_83ms"], 0)
        self.assertEqual(stats["frame_end_period_ms"]["max"], 25)
        self.assertEqual(stats["without_adjacent_callback_pair"], 2)

    def test_bad_timestamps_are_never_clamped_or_interpolated(self) -> None:
        rows = [{"frame_phases_us": [
            self.frame(None), self.frame(10), self.frame(10), self.frame(9),
            self.frame(100), self.frame(None), self.frame(200)]}]
        stats = profile.canvas_draw_cadence_diagnostics(rows)
        self.assertEqual(stats["frame_end_pairs"], 1)
        self.assertEqual(stats["rejected_missing_end_pairs"], 3)
        self.assertEqual(stats["rejected_nonmonotonic_end_pairs"], 2)
        self.assertEqual(stats["frame_end_period_ms"]["max"], 0.091)

    def test_empty_or_singleton_frames_never_invent_a_period(self) -> None:
        stats = profile.canvas_draw_cadence_diagnostics([
            {"frame_phases_us": []}, {"frame_phases_us": [self.frame(100)]}])
        self.assertEqual(stats["frame_end_pairs"], 0)
        self.assertIsNone(stats["frame_end_period_ms"])
        self.assertEqual(stats["long_events"], [])

    def test_exact_long_counts_outlive_bounded_detail(self) -> None:
        rows = [{"frame_phases_us": [self.frame(i * 100_000 + 1) for i in range(100)]}]
        stats = profile.canvas_draw_cadence_diagnostics(rows)
        self.assertEqual(stats["long_83ms"], 99)
        self.assertEqual(stats["frame_end_pairs"], 99)
        self.assertEqual(stats["retained_long_events"], profile.MAX_RETAINED_SLOW_CALLBACK_EVENTS)
        self.assertEqual(stats["omitted_long_events"], 99 - profile.MAX_RETAINED_SLOW_CALLBACK_EVENTS)
        self.assertEqual(stats["long_events"][-1]["frame_index"], 99)

    def test_four_retained_native_workspace_processes(self) -> None:
        base = SOURCE.parent.parent / "docs/evidence/T-197-2026-11-18-native-display-raw"
        submissions, callback_pairs, absent_callback_pairs = 0, 0, 0
        hashes: list[list[str]] = []
        for index, mode in enumerate(("reference", "optimized", "optimized", "reference")):
            folder = base / f"exact-round-{index}-{mode}"
            self.assertRegex((folder / "workspace-0.time").read_text(),
                             r"(?m)^\s*Exit status: 0\s*$")
            runs = profile.extract((folder / "workspace-0.log").read_text())
            self.assertEqual(len(runs), 8)
            hashes.append([run["after_sha256"] for run in runs])
            stats = profile.canvas_draw_cadence_diagnostics(runs)
            self.assertEqual(stats["frame_end_pairs"], 198)
            self.assertEqual(stats["long_83ms"], 0)
            self.assertEqual(stats["rejected_missing_end_pairs"], 0)
            self.assertEqual(stats["rejected_nonmonotonic_end_pairs"], 0)
            submissions += stats["frame_end_pairs"]
            callback_pairs += stats["with_adjacent_callback_pair"]
            absent_callback_pairs += stats["without_adjacent_callback_pair"]
        self.assertTrue(all(source == hashes[0] for source in hashes))
        self.assertEqual((submissions, callback_pairs, absent_callback_pairs), (792, 541, 251))


if __name__ == "__main__":
    unittest.main()
