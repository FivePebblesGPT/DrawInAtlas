"""Pinned Godot Atlas polygon/mask stress parity and native ABI contracts."""
from __future__ import annotations

import base64
import copy
import ctypes
import hashlib
import importlib.util
import json
import math
import os
import platform
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/benchmarks/t068_quad_stress.py"
EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_quad_stress.json"
spec = importlib.util.spec_from_file_location("t068_quad_stress", SCRIPT)
assert spec is not None and spec.loader is not None
# The sibling native C ABI facade is shared with the pinned 48-case corpus.
import sys
sys.path.insert(0, str(SCRIPT.parent))
stress = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stress)


class QuadStressContracts(unittest.TestCase):
    def test_fixture_diversity_and_exact_replay(self) -> None:
        cases = stress.load_oracle()
        self.assertEqual(len(cases), 96)
        self.assertEqual({c["density"] for c in cases}, {0.5, 1.0, 1.5, 2.0})
        self.assertGreater(len({len(c["polygon"]) for c in cases}), 5)
        self.assertTrue(any(not c["enabled"] for c in cases))
        self.assertTrue(any(c["enabled"] and not c["polygon"] for c in cases))
        evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        stress.validate_evidence(evidence)
        self.assertEqual(evidence["summary"], {
            "profiles": 2, "runs_per_profile": 2, "cases_per_run": 96,
            "comparisons": 384, "nonparity_profile_cases": 0,
            "missing_pixels": 0, "extra_pixels": 0,
        })
        self.assertEqual(evidence["profiles"][0]["runs"][0], evidence["profiles"][0]["runs"][1])

    def test_tampered_evidence_fails_closed(self) -> None:
        evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        attacks = (
            lambda p: p["profiles"].pop(),
            lambda p: p["profiles"].reverse(),
            lambda p: p["profiles"][0]["runs"].pop(),
            lambda p: p["profiles"][0]["runs"][0].pop(),
            lambda p: p["profiles"][0]["runs"][0][1].update(id="stress_000"),
            lambda p: p["profiles"][1]["runs"][0][2].update(native_sha256="0" * 64),
            lambda p: p["profiles"][0]["runs"][0][0].update(missing_indices=[-1]),
            lambda p: p["profiles"][0]["runs"][0][0].update(extra_indices=[0, 0]),
            lambda p: p["profiles"][0]["runs"][1][0].update(extra_indices=[0]),
            lambda p: p["profiles"][0]["runs"][0][0].update(surplus=True),
            lambda p: p["summary"].update(comparisons=383),
            lambda p: p.update(godot_oracle_sha256="0" * 64),
            lambda p: p.update(native_source_sha256="0" * 64),
            lambda p: p.update(limitations=[]),
        )
        for attack in attacks:
            with self.subTest(attack=attack):
                forged = copy.deepcopy(evidence)
                attack(forged)
                with self.assertRaises(ValueError):
                    stress.validate_evidence(forged)

    def test_live_strict_compiler_profiles(self) -> None:
        fresh = stress.screen()
        stress.validate_evidence(fresh)
        self.assertEqual(fresh, json.loads(EVIDENCE.read_text(encoding="utf-8")))

    def test_strict_fp_with_fma_capable_target(self) -> None:
        """FMA-enabled CPUs still honor the Godot float32 convex oracle.

        Without -ffp-contract=off, a local GCC 14 -O3 -mfma reproducer
        rejected 70/96 legitimate convex cases as nonconvex (-3). This
        opt-in compiler target never enables fast-math in the ABI itself.
        """
        if (platform.machine() not in ("x86_64", "AMD64")
                or not Path("/proc/cpuinfo").is_file()
                or "fma" not in Path("/proc/cpuinfo").read_text().split()):
            self.skipTest("Host CPU does not report x86_64 FMA support")
        with tempfile.TemporaryDirectory(prefix="t094-quad-fma-") as directory:
            library = stress.NativeQuad(stress.build(
                "g++", "-O3", Path(directory), ("-mfma",)))
            for case in stress.load_oracle():
                with self.subTest(case=case["id"]):
                    expected = base64.b64decode(case["mask_base64"])
                    self.assertEqual(stress.native_mask(library, case), expected)

    def test_abi_rejects_bad_bounds_without_mutating_destination(self) -> None:
        with tempfile.TemporaryDirectory(prefix="t068-stress-abi-") as directory:
            library = stress.NativeQuad(stress.build("g++", "-O2", Path(directory)))
            case = stress.load_oracle()[2]
            self.assertEqual(len(stress.native_mask(library, case)), 24 * 24)
            transform = (ctypes.c_double * 6)(1, 0, 0, 1, 0, 0)
            polygon = (ctypes.c_double * 8)(4, 5, 19, 5, 19, 19, 4, 19)
            output = (ctypes.c_uint8 * 576)(*([0xA5] * 576))
            for kind in ("short_output", "nan_transform", "nan_density", "bad_polygon"):
                with self.subTest(kind=kind):
                    transform[0] = math.nan if kind == "nan_transform" else 1.0
                    density = math.nan if kind == "nan_density" else 1.0
                    returned = library.function(
                        output, 575 if kind == "short_output" else 576, 24,
                        transform, 48, density, polygon,
                        56 if kind == "bad_polygon" else 64, 4, 1)
                    self.assertLess(returned, 0)
                    self.assertEqual(bytes(output), b"\xa5" * 576)

    def test_optional_godot_fixture_regeneration(self) -> None:
        godot = os.environ.get("T068_QUAD_GODOT")
        if not godot:
            self.skipTest("Set T068_QUAD_GODOT to rederive all 96 scopes from AtlasFill")
        with tempfile.TemporaryDirectory(prefix="t068-stress-godot-") as directory:
            output = Path(directory) / "regenerated.json"
            result = subprocess.run([godot, "--headless", "--path", str(ROOT),
                "--script", "res://tests/drawing_t068_quad_stress_oracle.gd",
                "--", str(output)], text=True, capture_output=True, timeout=180,
                check=False, cwd=ROOT,
                env={**os.environ, "GODOT_SILENCE_ROOT_WARNING": "1"})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("T068_QUAD_STRESS_ORACLE_PASSED: 96 cases", result.stdout)
            self.assertNotIn("SCRIPT ERROR:", result.stdout + result.stderr)
            self.assertEqual(hashlib.sha256(output.read_bytes()).hexdigest(), stress.ORACLE_SHA256)


if __name__ == "__main__":
    unittest.main()
