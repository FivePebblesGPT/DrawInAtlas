"""T-198: diagnostic periods must compare only adjacent matched Canvas frames."""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "tools/run_t185_profile.py"
spec = importlib.util.spec_from_file_location("t185_profile_t198", SOURCE)
assert spec is not None and spec.loader is not None
profile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile)


class TestMatchedCallbackIntervals(unittest.TestCase):
    @staticmethod
    def frame(callback: int | None, *, draw: int = 1000, backlog: int = 0) -> dict[str, int]:
        frame = {"full_draw_cpu_us": draw, "pending_input_count": backlog,
                 "oldest_pending_age_us": 3000 if backlog else 0,
                 "frame_end_to_post_draw_us": 8000}
        if callback is not None:
            frame["frame_post_draw_callback_us"] = callback
        return frame

    def test_only_adjacent_matching_callbacks_have_intervals(self) -> None:
        phases = [self.frame(100_000), self.frame(116_000), self.frame(None),
                  self.frame(250_000), self.frame(350_000, draw=1500, backlog=4)]
        summary = profile.callback_gap_diagnostics([{"frame_phases_us": phases}])
        self.assertEqual(summary["matched_pairs"], 2)
        self.assertEqual(summary["unmatched_pairs"], 2)
        self.assertEqual(summary["long_83ms"], 1)
        self.assertEqual(summary["matched_period_ms"]["p95"], 100)
        self.assertEqual(summary["long_events"][0]["canvas_draw_ms"], 1.5)
        self.assertEqual(summary["long_events"][0]["pending_input_count"], 4)

    def test_no_cross_gesture_gap_and_no_false_samples(self) -> None:
        rows = [{"frame_phases_us": [self.frame(100_000), self.frame(117_000)]},
                {"frame_phases_us": [self.frame(300_000), self.frame(316_000)]}]
        summary = profile.callback_gap_diagnostics(rows)
        self.assertEqual(summary["matched_pairs"], 2)
        self.assertEqual(summary["long_83ms"], 0)
        self.assertEqual(summary["matched_period_ms"]["max"], 17)

    def test_duplicate_and_backwards_callbacks_never_count_as_period(self) -> None:
        row = {"frame_phases_us": [self.frame(100), self.frame(100),
                                   self.frame(90), self.frame(1000)]}
        summary = profile.callback_gap_diagnostics([row])
        self.assertEqual(summary["rejected_nonmonotonic_pairs"], 2)
        self.assertEqual(summary["matched_pairs"], 1)
        self.assertEqual(summary["matched_period_ms"]["max"], 0.91)

    def test_absent_callbacks_yield_no_invented_fps(self) -> None:
        row = {"frame_phases_us": [self.frame(None), self.frame(None)]}
        summary = profile.callback_gap_diagnostics([row])
        self.assertEqual(summary["matched_pairs"], 0)
        self.assertIsNone(summary["matched_period_ms"])
        self.assertEqual(summary["unmatched_pairs"], 1)

    def test_retained_four_process_native_profiles(self) -> None:
        # This is an integration oracle, not a freshly rerun FPS benchmark.
        root = SOURCE.parent.parent / "docs/evidence/T-197-2026-11-18-native-display-raw"
        matched, missing, global_long = 0, 0, 0
        source_digests: list[list[str]] = []
        for index, mode in enumerate(("reference", "optimized", "optimized", "reference")):
            directory = root / f"exact-round-{index}-{mode}"
            self.assertRegex((directory / "workspace-0.time").read_text(),
                             r"(?m)^\s*Exit status: 0\s*$")
            rows = profile.extract((directory / "workspace-0.log").read_text())
            self.assertEqual(len(rows), 8)
            source_digests.append([row["after_sha256"] for row in rows])
            stats = profile.callback_gap_diagnostics(rows)
            matched += stats["matched_pairs"]
            missing += stats["unmatched_pairs"]
            self.assertEqual(stats["long_83ms"], 0)
            global_long += sum(sum(interval >= 83_333 for interval in
                                   row["post_draw_intervals_us"]) for row in rows)
        self.assertTrue(all(hashes == source_digests[0] for hashes in source_digests))
        self.assertEqual((matched, missing, global_long), (541, 251, 19))

    def test_bounded_long_event_retention_with_exact_counts(self) -> None:
        phases = [self.frame((i + 1) * 100_000) for i in range(100)]
        summary = profile.callback_gap_diagnostics([{"frame_phases_us": phases}])
        self.assertEqual(summary["long_83ms"], 99)
        self.assertLessEqual(len(summary["long_events"]), profile.MAX_RETAINED_SLOW_CALLBACK_EVENTS)
        self.assertEqual(summary["omitted_long_events"], 99 - len(summary["long_events"]))
        self.assertEqual(summary["long_events"][-1]["frame_index"], 99)


if __name__ == "__main__":
    unittest.main()
