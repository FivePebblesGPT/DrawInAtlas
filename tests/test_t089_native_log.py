"""Fail-closed CI parsing for the T-089 native framebuffer witness."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from check_native_t089_log import SUCCESS, verify  # noqa: E402


class T089NativeLogTests(unittest.TestCase):
    def test_only_known_shutdown_diagnostics_are_nonfatal(self) -> None:
        sample = "\n".join((
            "Godot Engine v4.8.beta2",
            SUCCESS,
            "ERROR: Texture with GL ID of 42: leaked 120 bytes.",
            "ERROR: 3 RID allocations of type 'N5GLES37TextureE' were leaked at exit.",
        ))
        self.assertEqual(verify(sample), (True, [], 2))

    def test_runtime_errors_before_marker_fail(self) -> None:
        ok, problems, leaks = verify("\n".join((
            "ERROR: Texture with GL ID of 42: leaked 120 bytes.", SUCCESS)))
        self.assertFalse(ok)
        self.assertEqual(len(problems), 1)
        self.assertEqual(leaks, 0)

    def test_script_and_unknown_teardown_errors_fail(self) -> None:
        for message in (
            "SCRIPT ERROR: Invalid call.\n" + SUCCESS,
            SUCCESS + "\nSCRIPT ERROR: failure after marker",
            SUCCESS + "\nERROR: Texture upload failed.",
            SUCCESS + "\nT089_NATIVE_FAILED: wrong pixel",
        ):
            with self.subTest(message=message):
                self.assertFalse(verify(message)[0])

    def test_previous_stale_witness_is_not_accepted(self) -> None:
        self.assertFalse(verify("T089_NATIVE_PASSED: 32 checks")[0])
        self.assertFalse(verify("T089_NATIVE_PASSED: 35 checks")[0])

    def test_missing_and_duplicate_markers_fail(self) -> None:
        self.assertFalse(verify("some other output")[0])
        self.assertFalse(verify(SUCCESS + "\n" + SUCCESS)[0])


if __name__ == "__main__":
    unittest.main()
