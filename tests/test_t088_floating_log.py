"""Fail-closed T-088 native Move witness CI log contracts."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from check_native_t088_log import verify_log


class NativeFloatingSelectionLogTests(unittest.TestCase):
    """Reject an early/incomplete success marker or hidden script error."""

    SUMMARY = ("T088_NATIVE: 51 checks; 0 failed "
               "(Godot 4.8-beta2 (official), display X11, 1010x740, zoom 50/100/200/400%)")

    def test_valid_complete_witness(self) -> None:
        problems, leaks = verify_log("\n".join((self.SUMMARY, "T088_NATIVE_PASSED")))
        self.assertEqual(problems, [])
        self.assertEqual(leaks, 0)

    def test_known_post_exit_leak_is_explicit(self) -> None:
        text = "\n".join((self.SUMMARY, "T088_NATIVE_PASSED",
                          "ERROR: 1 RID allocations of type 'Canvas' were leaked at exit."))
        self.assertEqual(verify_log(text), ([], 1))

    def test_under_count_and_failures(self) -> None:
        self.assertTrue(verify_log(self.SUMMARY.replace("51 checks", "50 checks")
                                   + "\nT088_NATIVE_PASSED")[0])
        self.assertTrue(verify_log(self.SUMMARY.replace("0 failed", "1 failed")
                                   + "\nT088_NATIVE_PASSED")[0])

    def test_duplicate_or_early_marker(self) -> None:
        self.assertTrue(verify_log("T088_NATIVE_PASSED\n" + self.SUMMARY)[0])
        self.assertTrue(verify_log(self.SUMMARY + "\nT088_NATIVE_PASSED\nT088_NATIVE_PASSED")[0])

    def test_script_and_runtime_errors_never_allowed(self) -> None:
        for error in ["SCRIPT ERROR: moved pixels lost",
                      "T088_NATIVE_FAILED: invalid stage",
                      "ERROR: cannot load resource",
                      "Parse Error: wrong statement"]:
            with self.subTest(error=error):
                self.assertTrue(verify_log(self.SUMMARY + "\nT088_NATIVE_PASSED\n" + error)[0])

    def test_leak_before_success_is_fatal(self) -> None:
        text = "\n".join(("ERROR: 1 RID allocations of type 'Canvas' were leaked at exit.",
                          self.SUMMARY, "T088_NATIVE_PASSED"))
        self.assertTrue(verify_log(text)[0])


if __name__ == "__main__":
    unittest.main()
