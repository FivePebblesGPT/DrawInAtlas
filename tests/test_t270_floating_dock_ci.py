"""T-270 required-native floating dock build and embedded cancellation contracts."""

from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/godot-native-t091-docking.yml"
MAKEFILE = ROOT / "Makefile"


class T270FloatingDockCIContracts(unittest.TestCase):
    def test_workflow_builds_required_native_before_any_ui_test(self) -> None:
        source = WORKFLOW.read_text(encoding="utf-8")
        for fragment in (
            "dtolnay/rust-toolchain@stable",
            "toolchain: 1.99.1",
            "make build TOOLCHAIN=system",
            "--path drawing",
            "--path .",
            "dock_single_group_native.gd",
            "dock_grip_redock_native.gd",
            "t257_atlas_floating_cancel_native.gd",
            "T257_ATLAS: 8 checks; 0 failed",
            "T257_ATLAS_PASSED",
            "check_native_t091_log.py",
            "check_godot_model_log.py",
            "actions/upload-artifact@v4",
        ):
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, source)
        self.assertLess(source.index("make build TOOLCHAIN=system"),
                        source.index("dock_single_group_native.gd"))
        self.assertLess(source.index("dock_single_group_native.gd"),
                        source.index("dock_grip_redock_native.gd"))
        self.assertLess(source.index("dock_grip_redock_native.gd"),
                        source.index("t257_atlas_floating_cancel_native.gd"))
        self.assertIn("set -euo pipefail", source)
        self.assertIn("/tmp/t091-atlas.log", source)

    def test_make_target_requires_build_and_fails_closed(self) -> None:
        source = MAKEFILE.read_text(encoding="utf-8")
        target = "test-floating-dock: import-drawing import-atlas"
        self.assertIn(target, source)
        block = source.split(target + "\n", 1)[1].split("\n# ", 1)[0]
        for fragment in (
            "set -euo pipefail",
            "dock_single_group_native.gd",
            "dock_grip_redock_native.gd",
            "t257_atlas_floating_cancel_native.gd",
            "check_native_t091_log.py",
            "--kind grip",
            "T257_ATLAS: 8 checks; 0 failed",
            "check_godot_model_log.py",
            "--marker T257_ATLAS_PASSED",
            'tee "$$log"',
            "timeout",
        ):
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, block)
        self.assertEqual(block.count("set -euo pipefail"), 3)

    def test_existing_log_oracles_fail_closed(self) -> None:
        from tools.check_native_t091_log import verify

        for kind, count, prefix in (
            ("single", 43, "T091_NATIVE"),
            ("grip", 53, "T091_GRIP_NATIVE"),
        ):
            good = f"{prefix}: {count} checks; 0 failed\n{prefix}_PASSED"
            with self.subTest(kind=kind):
                self.assertTrue(verify(good, kind=kind)[0])
                self.assertFalse(verify(good.replace(f"{count} checks", "1 checks"), kind=kind)[0])
                self.assertFalse(verify(good + f"\n{prefix}_PASSED", kind=kind)[0])
                self.assertFalse(verify("SCRIPT ERROR: missing extension\n" + good, kind=kind)[0])


if __name__ == "__main__":
    unittest.main()
