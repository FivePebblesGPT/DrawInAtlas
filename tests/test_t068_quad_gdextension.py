"""T-068: native Godot four-corner scope masks and brush handoff contracts."""
from __future__ import annotations

import copy
import ctypes
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "tools/benchmarks/t068_bridge"
EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_quad_gdextension.json"
SOURCE = ROOT / "tools/benchmarks/t068_quad_scope_kernel.cpp"
SPEC = importlib.util.spec_from_file_location("t068_quad_runner", BRIDGE / "run_bridge.py")
assert SPEC is not None and SPEC.loader is not None
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class QuadGodotBridgeContracts(unittest.TestCase):
    def test_opt_in_bridge_contract(self) -> None:
        bridge = (BRIDGE / "t068_bridge.cpp").read_text(encoding="utf-8")
        runner_source = (BRIDGE / "run_bridge.py").read_text(encoding="utf-8")
        script = (BRIDGE / "t068_quad_scope_smoke.gd").read_text(encoding="utf-8")
        workflow = (ROOT / ".github/workflows/godot-native-t068-bridge.yml").read_text()
        for marker in ("build_quad_selection", "t068_quad_scope_mask", "process_quad(",
                       "ptrcall_quad(", "call_quad(", "byte_constructor(result, nullptr)"):
            self.assertIn(marker, bridge)
        for marker in ('"res://quad_scope.gd"', '"quad_oracle.json"',
                       "validate_quad_bridge(quad_cases)", '"quad_cases": quad_cases'):
            self.assertIn(marker, runner_source)
        for marker in ("build_quad_selection(", "Marshalls.base64_to_raw",
                       "mask == expected", "apply_scalar_brush_sparse(",
                       "mask[pixel] != 1", "source == original",
                       "T068_QUAD_BRIDGE_EVIDENCE", "T068_QUAD_BRIDGE_PASSED"):
            self.assertIn(marker, script)
        self.assertIn("workflow_dispatch", workflow)
        self.assertNotIn("push:", workflow)
        self.assertNotIn("pull_request:", workflow)
        self.assertFalse(list(ROOT.rglob("*.gdextension")))

    def test_two_pinned_runs_are_complete_and_deterministic(self) -> None:
        data = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        self.assertEqual(data["ticket"], "T-068")
        self.assertEqual(data["schema_version"], 1)
        self.assertEqual(data["godot_version"], runner.EXPECTED_VERSION)
        self.assertEqual(data["quad_source_sha256"], hashlib.sha256(SOURCE.read_bytes()).hexdigest())
        self.assertEqual(data["bridge_source_sha256"], hashlib.sha256(
            (BRIDGE / "t068_bridge.cpp").read_bytes()).hexdigest())
        self.assertEqual(data["profile_sha256"], hashlib.sha256(
            (BRIDGE / "t068_quad_scope_smoke.gd").read_bytes()).hexdigest())
        self.assertEqual(data["oracle_sha256"], hashlib.sha256(
            (ROOT / "tools/benchmarks/t068_quad_scope_oracle.json").read_bytes()).hexdigest())
        self.assertEqual(len(data["runs"]), 2)
        for run in data["runs"]:
            self.assertEqual(run["checks"], 55)
            runner.validate_quad_bridge(run["cases"])
        self.assertEqual(data["runs"][0]["cases"], data["runs"][1]["cases"])
        self.assertIn("physical GPU", " ".join(data["limitations"]))

    def test_tampered_wire_metadata_and_pixels_fail_closed(self) -> None:
        cases = json.loads(EVIDENCE.read_text(encoding="utf-8"))["runs"][0]["cases"]
        edits = (
            lambda rows: rows.pop(),
            lambda rows: rows.append(copy.deepcopy(rows[0])),
            lambda rows: rows[0].update(id="invented"),
            lambda rows: rows[0].update(allowed=1),
            lambda rows: rows[0].update(changed=1),
            lambda rows: rows[0].update(sparse_bytes=4),
            lambda rows: rows[0].update(mask_sha256="0" * 64),
            lambda rows: rows[0].update(pixels_sha256="0" * 64),
            lambda rows: rows[0].update(unexpected=True),
            lambda rows: rows[0].update(changed=True),
        )
        for change in edits:
            with self.subTest(change=change):
                modified = copy.deepcopy(cases)
                change(modified)
                with self.assertRaises(ValueError):
                    runner.validate_quad_bridge(modified)
        for invalid in (None, {}, "cases", []):
            with self.assertRaises(ValueError):
                runner.validate_quad_bridge(invalid)

    @unittest.skipUnless(shutil.which("g++"), "Native C++17 compiler required")
    def test_detached_abi_is_atomic_on_invalid_inputs(self) -> None:
        with tempfile.TemporaryDirectory(prefix="t068-quad-kernel-") as directory:
            binary = Path(directory) / "libquad.so"
            subprocess.run(["g++", "-std=c++17", "-O2", "-shared", "-fPIC",
                            "-Wall", "-Wextra", "-Werror", str(SOURCE), "-o", str(binary)],
                           check=True, capture_output=True, timeout=45)
            lib = ctypes.CDLL(str(binary))
            fn = lib.t068_quad_scope_mask
            fn.restype = ctypes.c_int32
            fn.argtypes = (ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int32,
                           ctypes.c_void_p, ctypes.c_uint64, ctypes.c_double,
                           ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int32, ctypes.c_int32)
            affine = (ctypes.c_double * 6)(1, 0, 0, 1, 0, 0)
            convex = (ctypes.c_double * 8)(12, 12, 52, 12, 52, 52, 12, 52)
            invalid_polygon = (ctypes.c_double * 8)(12, 12, 52, 52, 12, 52, 52, 12)
            output = (ctypes.c_uint8 * 4096)(*([0xA5] * 4096))
            attempts = (
                (output, 4095, 64, affine, 48, 1.0, convex, 64, 4, 1),
                (output, 4096, 2049, affine, 48, 1.0, convex, 64, 4, 1),
                (output, 4096, 64, affine, 48, 0.0, convex, 64, 4, 1),
                (output, 4096, 64, affine, 48, 1.0, invalid_polygon, 64, 4, 1),
                (output, 4096, 64, affine, 48, 1.0, convex, 63, 4, 1),
            )
            for args in attempts:
                with self.subTest(args=args[1:3]):
                    self.assertLess(fn(*args), 0)
                    self.assertEqual(bytes(output), b"\xa5" * 4096)
            self.assertEqual(fn(output, 4096, 64, affine, 48, 1.0,
                                convex, 64, 4, 1), 40 * 40)
            self.assertEqual(bytes(output).count(1), 40 * 40)


if __name__ == "__main__":
    unittest.main()
