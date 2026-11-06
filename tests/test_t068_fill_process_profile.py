"""Unit contracts for the Linux T-068 native process/memory sampler."""
from __future__ import annotations

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "benchmarks"))
from t068_fill_process_profile import (  # noqa: E402
    REQUIRED_SIZES,
    descendants,
    matches_witness,
    parse_linux_status,
    sample_pid,
    summarize,
    validate_witness,
)


class FillProfileTests(unittest.TestCase):
    def test_parse_rss_hwm_and_swap(self) -> None:
        sample = parse_linux_status(
            "Name:\tGodot\nVmHWM:\t123000 kB\nVmRSS:\t98765 kB\nVmSwap:\t56 kB\n"
        )
        self.assertIsNotNone(sample)
        assert sample is not None
        self.assertEqual((sample.rss_kib, sample.high_water_kib, sample.swap_kib),
                         (98765, 123000, 56))
        self.assertIsNone(parse_linux_status("VmRSS:\t12 MB\nVmHWM:\t13 kB"))
        self.assertIsNone(parse_linux_status("VmRSS:\t12 kB"))
        self.assertEqual(parse_linux_status("VmHWM:\t10 kB\nVmRSS:\t8 kB").swap_kib, 0)

    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux /proc required")
    def test_live_self_process(self) -> None:
        import os
        self.assertIn(os.getpid(), descendants(os.getpid()))
        self.assertIsNotNone(sample_pid(os.getpid()))

    @staticmethod
    def witness(trials: int = 21) -> dict:
        return {
            "schema": "t068-bucket-frame-v1", "failures": 0,
            "configured_trials_per_size": trials, "checks": trials * 15 + 20,
            "cases": [{"size": size, "trials": trials,
                       "cpu_dispatch": {"samples_ms": [1.0] * trials},
                       "event_to_frame_post_draw": {"samples_ms": [2.0] * trials}}
                      for size in REQUIRED_SIZES],
        }

    def test_witness_rejects_bad_counts_failures_and_missing_samples(self) -> None:
        raw = self.witness()
        validate_witness(raw, 21)
        for mutation in ("failures", "checks", "size", "trials", "samples"):
            broken = json.loads(json.dumps(raw))
            if mutation == "failures":
                broken["failures"] = 1
            elif mutation == "checks":
                broken["checks"] = 3
            elif mutation == "size":
                broken["cases"][1]["size"] = 512
            elif mutation == "trials":
                broken["cases"][0]["trials"] = 4
            else:
                broken["cases"][2]["event_to_frame_post_draw"]["samples_ms"].pop()
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                validate_witness(broken, 21)

    def test_reject_xvfb_wrapper_even_when_command_contains_script(self) -> None:
        godot = Path("/opt/godot")
        args = [b"--script", b"res://tests/drawing_fill_frame_native.gd"]
        self.assertFalse(matches_witness(Path("/bin/dash"), args, godot))
        self.assertTrue(matches_witness(godot, args, godot))
        self.assertFalse(matches_witness(godot, [b"--script", b"another.gd"], godot))

    def test_paired_run_medians_are_not_pooled(self) -> None:
        rows = [
            {"cases": [{"cpu_dispatch": {"median_ms": 2.0},
                        "event_to_frame_post_draw": {"median_ms": 10.0}}] * 3},
            {"cases": [{"cpu_dispatch": {"median_ms": 4.0},
                        "event_to_frame_post_draw": {"median_ms": 12.0}}] * 3},
        ]
        combined = summarize(rows)
        self.assertEqual(combined["cases"][0]["median_of_cpu_run_medians_ms"], 3.0)
        self.assertEqual(combined["cases"][0]["median_of_frame_run_medians_ms"], 11.0)
        self.assertEqual(combined["cases"][2]["run_median_cpu_ms"], [2.0, 4.0])


if __name__ == "__main__":
    unittest.main()
