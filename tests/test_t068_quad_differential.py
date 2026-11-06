"""Deterministic T-068 Godot/C++ polygon boundary differential contracts."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/benchmarks/t068_quad_differential.py"
EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_quad_differential.json"
HISTORICAL = ROOT / "docs/benchmarks/T068_2026-11-04_quad_differential_strict_double.json"
HISTORICAL_SHA256 = "0e838efee61177c7c4276109e730e4d28bae0823ad0f82201f3424fbcd3a3072"
spec = importlib.util.spec_from_file_location("t068_quad_differential", SCRIPT)
assert spec is not None and spec.loader is not None
quad = importlib.util.module_from_spec(spec)
spec.loader.exec_module(quad)


class DifferentialContracts(unittest.TestCase):
    def test_pinned_godot_oracle_and_two_run_evidence(self) -> None:
        self.assertEqual(len(quad.load_oracle()), 48)
        data = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        quad.validate_evidence(data)
        self.assertEqual(data["summary"], {
            "runs": 2, "cases_per_run": 48, "nonparity_cases": 0,
            "missing_pixels_per_run": 0, "extra_pixels_per_run": 0,
        })
        self.assertEqual(data["runs"][0], data["runs"][1])
        self.assertEqual(sum(bool(row["missing_indices"] or row["extra_indices"])
                             for row in data["runs"][0]), 0)

    def test_original_strict_double_failure_is_preserved(self) -> None:
        # Historical source-pinned result must not be overwritten or passed
        # off as a run of the revised float32-compatible native kernel.
        raw = HISTORICAL.read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), HISTORICAL_SHA256)
        previous = json.loads(raw)
        self.assertEqual(previous["native_source_sha256"],
                         "7079e2390dfc4ef899ee6e8ca35507e94c692b4c5e622387677e4e17cbd7c3da")
        self.assertEqual(previous["summary"]["nonparity_cases"], 16)
        self.assertEqual(previous["summary"]["missing_pixels_per_run"], 247)
        self.assertNotEqual(previous["native_source_sha256"],
                            hashlib.sha256(quad.SOURCE.read_bytes()).hexdigest())

    def test_evidence_tampering_rejected(self) -> None:
        data = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        for tamper in (
            lambda p: p["runs"][0].pop(),
            lambda p: p["runs"][1].reverse(),
            lambda p: p["runs"][0][1].update(native_allowed=1),
            lambda p: p["runs"][0][1].update(native_sha256="0" * 64),
            lambda p: p["runs"][0][1].update(missing_indices=[-1]),
            lambda p: p["runs"][0][1].update(missing_indices=[0, 0]),
            lambda p: p["runs"][0][1].update(extra_indices=[0]),
            lambda p: p["runs"][0][1].update(id="seed_00"),
            lambda p: p["runs"][0][1].update(extra_field=7),
            lambda p: p["runs"][1][1].update(missing_indices=[0]),
            lambda p: p["summary"].update(nonparity_cases=16),
            lambda p: p.update(godot_oracle_sha256="0" * 64),
            lambda p: p.update(native_source_sha256="0" * 64),
            lambda p: p.update(limitations=[]),
        ):
            with self.subTest(tamper=tamper):
                forged = copy.deepcopy(data)
                tamper(forged)
                with self.assertRaises(ValueError):
                    quad.validate_evidence(forged)

    def test_live_detached_native_comparator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="t068-quad-diff-test-") as directory:
            fresh = quad.screen(quad.build(Path(directory)))
        quad.validate_evidence(fresh)
        self.assertEqual(fresh, json.loads(EVIDENCE.read_text(encoding="utf-8")))

    def test_optional_live_godot_regeneration(self) -> None:
        godot = os.environ.get("T068_QUAD_GODOT")
        if not godot:
            self.skipTest("Set T068_QUAD_GODOT to rederive 48 masks from AtlasFill")
        with tempfile.TemporaryDirectory(prefix="t068-quad-godot-") as directory:
            output = Path(directory) / "regenerated.json"
            result = subprocess.run([
                godot, "--headless", "--path", str(ROOT), "--script",
                "res://tests/drawing_t068_quad_differential_oracle.gd", "--", str(output),
            ], text=True, capture_output=True, timeout=120, check=False,
                env={**os.environ, "GODOT_SILENCE_ROOT_WARNING": "1"}, cwd=ROOT)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("T068_QUAD_DIFFERENTIAL_ORACLE_PASSED: 48 cases", result.stdout)
            self.assertNotIn("SCRIPT ERROR:", result.stdout + result.stderr)
            self.assertEqual(hashlib.sha256(output.read_bytes()).hexdigest(), quad.ORACLE_SHA256)

    def test_failure_atomicity_for_detached_kernel(self) -> None:
        with tempfile.TemporaryDirectory(prefix="t068-quad-kernel-guards-") as directory:
            library = quad.NativeQuad(quad.build(Path(directory)))
            case = quad.load_oracle()[0]
            self.assertEqual(len(library.mask(case)), 32 * 32)
            # A singular transform or NaN must be rejected without changing
            # an initialized destination. The raw ABI is intentionally tested
            # separately from the safe high-level facade.
            import ctypes
            t = (ctypes.c_double * 6)(0, 0, 0, 0, 0, 0)
            p = (ctypes.c_double * 8)(9, 9, 24, 9, 24, 24, 9, 24)
            output = (ctypes.c_uint8 * (32 * 32))(*([0xA5] * 1024))
            result = library.function(output, 1024, 32, t, 48, 1.0, p, 64, 4, 1)
            self.assertLess(result, 0)
            self.assertEqual(bytes(output), bytes([0xA5] * 1024))
            t = (ctypes.c_double * 6)(1, 0, 0, 1, 0, 0)
            result = library.function(output, 1023, 32, t, 48, 1.0, p, 64, 4, 1)
            self.assertLess(result, 0)
            self.assertEqual(bytes(output), bytes([0xA5] * 1024))


if __name__ == "__main__":
    unittest.main()
