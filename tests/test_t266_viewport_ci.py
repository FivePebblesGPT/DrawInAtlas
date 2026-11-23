"""Required-native T-086 workflow and fail-closed cold-renderer CI contracts."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

spec = importlib.util.spec_from_file_location("t086_log_verifier", TOOLS / "check_t086_logs.py")
if spec is None or spec.loader is None:
    raise RuntimeError("Missing T-086 log verifier")
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)

WORKFLOW = ROOT / ".github/workflows/godot-native-t086-viewport.yml"
MAKEFILE = ROOT / "Makefile"


class ViewportNativeCiContracts(unittest.TestCase):
    """Ensure a cold runner builds native Brush before any X11 framebuffer check."""

    def test_build_before_both_imports_and_all_native_workloads(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("toolchain: 1.99.1", workflow)
        self.assertIn("make build TOOLCHAIN=system", workflow)
        build = workflow.index("make build TOOLCHAIN=system")
        for marker in ("--script res://tests/viewport_cache_native.gd",
                       "--script res://tests/t102_cold_dense_viewport_native.gd",
                       "--script res://tests/t103_overbudget_viewport_native.gd",
                       "--script res://tests/t137_preview_cold_population_native.gd",
                       "--script res://tests/renderer_cold_benchmark.gd"):
            with self.subTest(marker=marker):
                self.assertGreater(workflow.index(marker), build)
        self.assertNotIn("tools/build_drawing_app.py --in-place", workflow)
        self.assertIn("tools/check_t086_logs.py viewport", workflow)
        self.assertIn("tools/check_t086_logs.py cold", workflow)
        self.assertIn("T137_NATIVE_PASSED checks=19 failures=0", workflow)

    def test_archived_comparator_not_misrepresented_as_current_native(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("t086_compare_viewport.py", workflow)
        self.assertIn("--marker T086_COMPARISON_PASSED", workflow)
        self.assertNotIn("t086_compare_cold_composite.py", workflow)
        self.assertIn("tests.test_t086_benchmark_fixtures", workflow)
        self.assertIn("/tmp/t086-current-cold.log", workflow)
        self.assertIn("/tmp/t086-cold-fixtures.log", workflow)
        self.assertIn("if: always()", workflow)

    def test_local_make_gate_has_pipeline_error_propagation(self) -> None:
        make = MAKEFILE.read_text(encoding="utf-8")
        self.assertIn("SHELL := /bin/bash", make)
        section = make.split("test-viewport-cache: import-drawing import-atlas", 1)[1]
        section = section.split("\n\n", 1)[0]
        self.assertEqual(section.count("set -euo pipefail"), 3)
        self.assertIn("check_t086_logs.py viewport", section)
        self.assertIn("check_t086_logs.py cold", section)
        self.assertIn("T137_NATIVE_PASSED checks=19 failures=0", section)
        self.assertIn("tests.test_t086_benchmark_fixtures", section)

    def test_viewport_summary_and_engine_diagnostics_are_required(self) -> None:
        valid = "T086_NATIVE: 153 checks; 0 failed\nT086_NATIVE_PASSED\n"
        self.assertEqual(verifier.verify_viewport(valid), [])
        for altered in (valid.replace("153", "152"),
                        valid.replace("0 failed", "1 failed"),
                        valid + "T086_NATIVE_PASSED\n",
                        valid + "SCRIPT ERROR: unexpected null texture\n",
                        valid + "ERROR: unload failed\n"):
            with self.subTest(altered=altered):
                self.assertTrue(verifier.verify_viewport(altered))

    def test_current_cold_exact_pixel_hashes_and_workload(self) -> None:
        cases = {name: {"sha256": digest, "median_ms": 1.5, "p95_ms": 1.8}
                 for name, digest in verifier.COLD_SHA256.items()}
        report = {"engine": "4.8-beta3 (official)", "samples_per_case": 9,
                  "viewport_source": [256, 256], "storage_stride": 128,
                  "layer_count": 2, "cases": cases}
        valid = f"T086_COLD_BENCH_JSON {json.dumps(report)}\nT086_COLD_BENCH_PASSED\n"
        self.assertEqual(verifier.verify_cold(valid), [])
        changed = json.loads(json.dumps(report))
        changed["cases"]["alpha"]["sha256"] = "0" * 64
        self.assertTrue(verifier.verify_cold(
            f"T086_COLD_BENCH_JSON {json.dumps(changed)}\nT086_COLD_BENCH_PASSED\n"))
        missing = json.loads(json.dumps(report))
        missing["cases"].pop("opaque")
        self.assertTrue(verifier.verify_cold(
            f"T086_COLD_BENCH_JSON {json.dumps(missing)}\nT086_COLD_BENCH_PASSED\n"))
        for changed_body in (valid.replace("samples_per_case\": 9", "samples_per_case\": 8"),
                             valid.replace("1.5", "NaN"),
                             valid + "T086_COLD_BENCH_PASSED\n",
                             valid.replace("T086_COLD_BENCH_PASSED", "T086_COLD_BENCH_FAILED")):
            self.assertTrue(verifier.verify_cold(changed_body))

    def test_log_verifier_cli_fails_closed_on_bad_success(self) -> None:
        with tempfile.TemporaryDirectory() as path:
            log = Path(path) / "native.log"
            log.write_text("T086_NATIVE: 152 checks; 0 failed\nT086_NATIVE_PASSED\n")
            bad = subprocess.run([sys.executable, str(TOOLS / "check_t086_logs.py"),
                                  "viewport", str(log)], capture_output=True, text=True)
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn("T086_LOG_REJECTED", bad.stdout)
            log.write_text("T086_NATIVE: 153 checks; 0 failed\nT086_NATIVE_PASSED\n")
            good = subprocess.run([sys.executable, str(TOOLS / "check_t086_logs.py"),
                                   "viewport", str(log)], capture_output=True, text=True)
            self.assertEqual(good.returncode, 0, good.stdout + good.stderr)


if __name__ == "__main__":
    unittest.main()
