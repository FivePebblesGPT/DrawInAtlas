"""T-268: required-native CI and fail-closed large selection/Move evidence."""

from __future__ import annotations

import unittest
from pathlib import Path

from tools.check_t096_logs import MODEL_METRICS, NATIVE_METRICS, verify_log

ROOT = Path(__file__).resolve().parents[1]

WORKFLOW = ROOT / ".github/workflows/godot-native-t096-selection.yml"
MAKEFILE = ROOT / "Makefile"


def model_log() -> str:
    fields = " ".join(f"{name}=1.200/2.300" for name in MODEL_METRICS)
    return "\n".join((f"T096_PROFILE: {fields}", "T096_MODEL: 13847 checks; 0 failed", "T096_MODEL_PASSED"))


def native_log() -> str:
    fields = " ".join(f"{name}=1.250" for name in NATIVE_METRICS)
    return "\n".join(
        (f"T096_NATIVE_TIMING: {fields}", "T096_NATIVE: 34 checks; 0 failed", "T096_NATIVE_PASSED")
    )


def atlas_log() -> str:
    return "T268_ATLAS: 22 checks; 0 failures\nT268_ATLAS_PASSED"


class T268RequiredNativeCiTests(unittest.TestCase):
    """A fresh runner must compile and import both canonical native consumers."""

    def test_workflow_compiles_native_before_any_godot_witness(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("toolchain: 1.99.1", workflow)
        self.assertIn("make build TOOLCHAIN=system", workflow)
        build = workflow.index("make build TOOLCHAIN=system")
        self.assertNotIn("tools/build_drawing_app.py --in-place", workflow)
        for script in ("selection_large_smoke.gd", "selection_large_native.gd", "t268_atlas_large_move.gd"):
            with self.subTest(script=script):
                self.assertGreater(workflow.index(script), build)
        self.assertIn("tools/check_t096_logs.py", workflow)

    def test_make_target_is_cold_native_and_fails_through_tee(self) -> None:
        make = MAKEFILE.read_text(encoding="utf-8")
        self.assertIn("SHELL := /bin/bash", make)
        self.assertIn("test-large-move: import-drawing import-atlas", make)
        body = make.split("test-large-move: import-drawing import-atlas", 1)[1]
        body = body.split("\n# ", 1)[0]
        self.assertEqual(body.count("set -euo pipefail"), 3)
        self.assertEqual(body.count("tools/check_t096_logs.py"), 3)
        for script in ("selection_large_smoke.gd", "selection_large_native.gd", "t268_atlas_large_move.gd"):
            self.assertIn(script, body)

    def test_workflow_publishes_every_log_even_on_failure(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("if: always()", workflow)
        for name in ("/tmp/t096-model.log", "/tmp/t096-native.log", "/tmp/t268-atlas.log"):
            self.assertIn(name, workflow)
        self.assertIn("set -euo pipefail", workflow)


class T268StrictLogTests(unittest.TestCase):
    """A PASS marker alone or old smoke test is never enough."""

    def test_complete_realistic_logs(self) -> None:
        for kind, content in (("model", model_log()), ("native", native_log()), ("atlas", atlas_log())):
            with self.subTest(kind=kind):
                self.assertEqual(verify_log(content, kind), [])

    def test_missing_or_reduced_checks_fail(self) -> None:
        cases = (
            ("model", model_log().replace("13847", "100")),
            ("native", native_log().replace("34 checks", "33 checks")),
            ("atlas", atlas_log().replace("22 checks", "21 checks")),
        )
        for kind, content in cases:
            with self.subTest(kind=kind):
                self.assertTrue(verify_log(content, kind))

    def test_missing_or_invalid_native_timing_fails(self) -> None:
        self.assertTrue(verify_log(native_log().replace("capture_ms=1.250", ""), "native"))
        self.assertTrue(verify_log(native_log().replace("capture_ms=1.250", "capture_ms=-1"), "native"))
        self.assertTrue(verify_log(native_log().replace("capture_ms=1.250", "capture_ms=NaN"), "native"))
        self.assertTrue(verify_log(model_log().replace("legacy_capture_p50/p95_ms=1.200/2.300", ""), "model"))

    def test_duplicate_or_early_markers_fail(self) -> None:
        for kind, content, marker in (
            ("model", model_log(), "T096_MODEL_PASSED"),
            ("native", native_log(), "T096_NATIVE_PASSED"),
            ("atlas", atlas_log(), "T268_ATLAS_PASSED"),
        ):
            self.assertTrue(verify_log(content + "\n" + marker, kind))
            self.assertTrue(verify_log(marker + "\n" + content, kind))

    def test_native_crash_and_godot_errors_fail(self) -> None:
        for line in (
            "SCRIPT ERROR: Move failed",
            "T096_NATIVE_FAILED: wrong mask",
            "ERROR: cannot load native extension",
            "Parse Error: broken GDScript",
            "Segmentation fault (core dumped)",
            "E 0:00:01:234 native error",
        ):
            with self.subTest(line=line):
                self.assertTrue(verify_log(native_log() + "\n" + line, "native"))

    def test_unknown_kind_rejected(self) -> None:
        with self.assertRaises(ValueError):
            verify_log(model_log(), "brush")


if __name__ == "__main__":
    unittest.main()
