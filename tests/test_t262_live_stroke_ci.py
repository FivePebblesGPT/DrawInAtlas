"""T-262: required-native T-085 live-stroke workflow and fail-closed evidence."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))


class LiveStrokeCIContracts(unittest.TestCase):
    def setUp(self) -> None:
        self.workflow = (ROOT / ".github/workflows/godot-native-t085-stroke.yml").read_text()

    def test_native_extension_built_before_either_consumer_import(self) -> None:
        self.assertIn("toolchain: 1.99.1", self.workflow)
        self.assertIn("make build TOOLCHAIN=system", self.workflow)
        self.assertNotIn("python3 tools/build_drawing_app.py --in-place", self.workflow)
        self.assertLess(
            self.workflow.index("make build TOOLCHAIN=system"),
            self.workflow.index("res://tests/live_stroke_smoke.gd"),
        )
        self.assertLess(
            self.workflow.index("make build TOOLCHAIN=system"),
            self.workflow.index("res://tests/live_stroke_native.gd"),
        )

    def test_standalone_both_witnesses_are_strict_and_archived(self) -> None:
        for term in (
            "--audio-driver Dummy",
            "--display-driver x11",
            "--rendering-method gl_compatibility",
            "res://tests/live_stroke_smoke.gd",
            "--marker T085_MODEL_PASSED",
            "res://tests/live_stroke_native.gd",
            "tools/check_native_t085_log.py",
            "/tmp/t085-model.log",
            "/tmp/t085-native.log",
            "if: always()",
        ):
            with self.subTest(term=term):
                self.assertIn(term, self.workflow)
        self.assertNotIn("grep -q 'T085_NATIVE_PASSED'", self.workflow)
        self.assertLess(
            self.workflow.index("res://tests/live_stroke_smoke.gd"),
            self.workflow.index("res://tests/live_stroke_native.gd"),
        )

    def test_make_target_replays_both_clean_consumers(self) -> None:
        makefile = (ROOT / "Makefile").read_text()
        recipe = makefile.split("test-live-stroke: import-drawing import-atlas", 1)[1].split("\n\n", 1)[0]
        self.assertIn("test-live-stroke", makefile.split(".PHONY:", 1)[1])
        self.assertIn("tools/check_godot_model_log.py", recipe)
        self.assertIn("tools/check_native_t085_log.py", recipe)
        self.assertIn("res://tests/live_stroke_smoke.gd", recipe)
        self.assertIn("res://tests/live_stroke_native.gd", recipe)
        self.assertIn("xvfb-run -a", recipe)

    def test_native_witness_preserves_held_preview_and_all_long_strokes(self) -> None:
        native = (ROOT / "drawing/tests/live_stroke_native.gd").read_text()
        for term in (
            "get_texture().get_image()",
            "MOUSE_BUTTON_MASK_LEFT",
            "T085_NATIVE_LONG_SUMMARY",
            "for trial: int in range(3)",
            "var delivered: int = 840",
            "[1.0, 0.5, 0.25]",
            "T085_NATIVE_PASSED",
        ):
            with self.subTest(term=term):
                self.assertIn(term, native)

    def test_minimum_count_and_diagnostic_parser_reject_stale_success(self) -> None:
        from tools.check_native_t085_log import verify

        zooms = ("1.00", "0.50", "0.25")
        lines = ["Godot Engine v4.8.beta3.official"]
        for zoom in zooms:
            lines.append(
                f"T085_NATIVE_ZOOM zoom={zoom} samples=31 max_queued=29 down_to_stage_ms=0.1 down_to_frame_ms=3.0 release_to_commit_ms=2.0"
            )
        for zoom in zooms:
            for _ in range(3):
                lines.append(
                    f"T085_NATIVE_LONG zoom={zoom} delivered=840 segments=844 drain_calls=5 drain_frames=1 max_drain_cpu_ms=4.0 stage_cpu_ms=11.0 release_to_commit_ms=12.0 wall_ms=30.0"
                )
            lines.append(
                f"T085_NATIVE_LONG_SUMMARY zoom={zoom} trials=3 release_to_commit_p50_ms=12.0 release_to_commit_p95_ms=14.0"
            )
        lines.extend(
            [
                "T085_NATIVE_METRICS ms: preview_frame_p50=3.0 preview_frame_p95=9.0 sample_to_stage_p50=0.5 sample_to_stage_p95=1.0 stage_cpu_p50=1.0 stage_cpu_p95=2.0",
                "T085_NATIVE: 144 checks; 0 failed",
                "T085_NATIVE_PASSED",
            ]
        )
        good = "\n".join(lines) + "\n"
        self.assertTrue(verify(good)[0])
        self.assertTrue(verify(good + "ERROR: Texture with GL ID of 24: leaked 1364 bytes.\n")[0])
        for bad in (
            good.replace("144 checks", "55 checks"),
            good.replace("0 failed", "1 failed"),
            good.replace("delivered=840", "delivered=839", 1),
            good.replace("trials=3", "trials=2", 1),
            good.replace("zoom=0.25 samples=31", "zoom=0.50 samples=31"),
            good.replace("T085_NATIVE_METRICS ms:", "T085_NATIVE_METRICS missing:"),
            good.replace("T085_NATIVE_PASSED", "T085_NATIVE_FAILED"),
            good + "T085_NATIVE_PASSED\n",
            good + "ERROR: unexpected runtime failure\n",
            good + "SCRIPT ERROR: unexpected call\n",
            "ERROR: invalid engine startup\n" + good,
            good + "Segmentation fault (core dumped)\n",
        ):
            with self.subTest(bad=bad[-100:]):
                self.assertFalse(verify(bad)[0])


if __name__ == "__main__":
    unittest.main()
