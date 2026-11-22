"""T-261 on-demand native ColorPicker recovery coverage and review isolation."""

from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class T261ColorInterruptContracts(unittest.TestCase):
    def test_clean_native_ci_builds_both_consumers(self) -> None:
        ci = (ROOT / ".github/workflows/godot-native-t261-color-interruption.yml").read_text()
        for expected in (
            "workflow_dispatch", "toolchain: 1.99.1", "make build TOOLCHAIN=system",
            "--path drawing", "--path .", "t261_color_interruption_native.gd",
            "t261_atlas_color_interruption_native.gd", "T261_NATIVE_PASSED",
            "T261_ATLAS_PASSED", "check_godot_model_log.py", "upload-artifact@v4",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, ci)

    def test_make_target_reimports_native_before_both_x11_tests(self) -> None:
        makefile = (ROOT / "Makefile").read_text()
        target = makefile.split("test-color-interruption: import-drawing import-atlas", 1)[1]
        self.assertIn("xvfb-run", target)
        self.assertIn("t261_color_interruption_native.gd", target)
        self.assertIn("t261_atlas_color_interruption_native.gd", target)

    def test_pointer_and_keyboard_interruption_are_distinct(self) -> None:
        source = (ROOT / "addons/drawing/workspace.gd").read_text()
        self.assertIn("func _cancel_interrupted_color_pointer() -> void:", source)
        self.assertIn("not bool(motion.button_mask & MOUSE_BUTTON_MASK_LEFT)", source)
        self.assertIn("_color_edit_recover_on_press", source)
        self.assertIn("NOTIFICATION_APPLICATION_FOCUS_OUT", source)
        self.assertIn("_finish_color_edit()", source)
        self.assertIn("_cancel_color_edit()", source)

    def test_manual_owner_gate_remains_unapproved(self) -> None:
        gate = (ROOT / "docs/Tickets/T-250.md").read_text()
        self.assertIn('status: "Manual Review"', gate)
        self.assertIn("- [ ] Owner tests standalone Drawing", gate)


if __name__ == "__main__":
    unittest.main()
