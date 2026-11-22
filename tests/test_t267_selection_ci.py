"""T-267: native selection CI must build both consumers before X11 tests."""

from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/godot-native-t088-selection.yml"
MAKEFILE = ROOT / "Makefile"


class RequiredNativeSelectionCiTests(unittest.TestCase):
    """Keep the on-demand selection witness runnable from a clean checkout."""

    def test_rust_and_native_import_precede_selection_and_contours(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("toolchain: 1.99.1", workflow)
        self.assertIn("make build TOOLCHAIN=system", workflow)
        build = workflow.index("make build TOOLCHAIN=system")
        self.assertNotIn("tools/build_drawing_app.py --in-place", workflow)
        for script in (
            "selection_clipboard_native.gd",
            "t139_sparse_selection_outline_native.gd",
            "t140_focal_mask_overflow_native.gd",
            "t141_sparse_mask_overflow_native.gd",
            "t142_outline_cache_native.gd",
            "t143_contour_clip_native.gd",
            "t144_outline_plan_native.gd",
            "t145_outline_window_native.gd",
            "t253_selection_delete_native.gd",
        ):
            with self.subTest(script=script):
                self.assertGreater(workflow.index(script), build)
        self.assertIn("tools/check_native_t088_log.py", workflow)
        self.assertIn("tools/check_godot_model_log.py", workflow)

    def test_clean_make_target_builds_before_all_regressions(self) -> None:
        make = MAKEFILE.read_text(encoding="utf-8")
        self.assertIn("SHELL := /bin/bash", make)
        self.assertIn("test-selection-native: import-drawing import-atlas", make)
        body = make.split("test-selection-native: import-drawing import-atlas", 1)[1]
        body = body.split("\n# ", 1)[0]
        self.assertIn("set -euo pipefail", body)
        self.assertIn("check_native_t088_log.py", body)
        for script in ("selection_clipboard_native.gd", "t139_sparse_selection_outline_native.gd",
                       "t145_outline_window_native.gd", "t253_selection_delete_native.gd",
                       "t253_atlas_dense_delete.gd"):
            with self.subTest(script=script):
                self.assertIn(script, body)
        self.assertIn("T253_ATLAS_PASSED", body)

    def test_workflow_records_all_selection_diagnostics(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("if: always()", workflow)
        for name in ("/tmp/t088-native.log", "/tmp/t139-outline-native.log",
                     "/tmp/t145-outline-native.log", "/tmp/t253-native.log"):
            self.assertIn(name, workflow)


if __name__ == "__main__":
    unittest.main()
