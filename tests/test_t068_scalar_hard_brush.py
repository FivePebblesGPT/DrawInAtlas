"""T-068 detached scalar native hard-brush vs Godot geometry contracts."""

from __future__ import annotations

import copy
import ctypes
import json
import math
import random
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/benchmarks"))
import t068_scalar_hard_brush as SCALAR  # noqa: E402


class ScalarHardBrushTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="t068-scalar-test-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.native = SCALAR.ScalarBrush(SCALAR.compile_kernel(Path(cls.temporary.name)))

    def test_pinned_two_run_godot_parity_and_independent_pixels(self) -> None:
        saved = json.loads(SCALAR.EVIDENCE.read_text(encoding="utf-8"))
        SCALAR.validate_evidence(saved)
        self.assertEqual(saved["summary"], {"runs": 2, "cases_per_run": 28,
                                             "mismatched_cases": 0})
        # The 16 canonical Godot source-over/erase results are already checked
        # by load_oracle; ensure every native mask exactly matches their indices.
        fixtures = SCALAR.inputs()
        self.assertEqual(len(fixtures), 28)
        for identifier, side, path, width, selection, covered, rgba_sha in fixtures:
            with self.subTest(case=identifier):
                native = self.native.render(side, path, width, selection)
                self.assertEqual(native, SCALAR.expected_mask(side, covered))
                if identifier.startswith("small/"):
                    self.assertIsNotNone(rgba_sha)
                else:
                    self.assertIsNone(rgba_sha)

    def test_independent_seeded_distance_reference_away_from_ties(self) -> None:
        rng = random.Random(0x0685CA1A)
        side = 13
        for trial in range(96):
            points = [[rng.uniform(-4, 17), rng.uniform(-4, 17)]
                      for _ in range(rng.randrange(1, 6))]
            width = rng.uniform(0.1, 11)
            selection = bytes(rng.randrange(0, 2) for _ in range(side * side))
            actual = self.native.render(side, points, width, selection)
            for y in range(side):
                for x in range(side):
                    p = (x + 0.5, y + 0.5)
                    distances = []
                    for i, b in enumerate(points):
                        a = points[max(i - 1, 0)]
                        dx, dy = b[0] - a[0], b[1] - a[1]
                        length = dx * dx + dy * dy
                        projection = (max(0.0, min(1.0, ((p[0] - a[0]) * dx +
                                                            (p[1] - a[1]) * dy) / length))
                                      if length else 0.0)
                        distances.append(math.hypot(p[0] - a[0] - projection * dx,
                                                    p[1] - a[1] - projection * dy))
                    distance = min(distances)
                    # Float32 and double implementations can disagree exactly
                    # on a boundary, so use only points safely away from it.
                    if abs(distance - width / 2) > 1e-4:
                        expected = 255 if selection[y * side + x] and distance < width / 2 else 0
                        self.assertEqual(actual[y * side + x], expected, (trial, x, y))

    def test_native_failure_atomicity_and_input_alias_guards(self) -> None:
        function = self.native.function
        out = (ctypes.c_uint8 * 64)(*([0xA5] * 64))
        selected = (ctypes.c_uint8 * 64)(*([1] * 64))
        points = (ctypes.c_double * 4)(3.0, 3.0, 6.0, 6.0)
        invalid = (ctypes.c_uint8 * 64)(*([2] * 64))

        def call(**change: object) -> int:
            args = {"output": out, "output_bytes": 64,
                    "selection": selected, "selection_bytes": 64,
                    "side": 8, "points": points, "point_bytes": ctypes.sizeof(points),
                    "point_count": 2, "width": 2.0}
            args.update(change)
            return function(args["output"], args["output_bytes"],
                            args["selection"], args["selection_bytes"], args["side"],
                            args["points"], args["point_bytes"], args["point_count"],
                            args["width"])

        for change, status in (
            ({"output_bytes": 63}, -1), ({"selection_bytes": 63}, -1),
            ({"point_bytes": 16}, -1), ({"point_count": 0}, -1),
            ({"side": 4096}, -1), ({"width": float("nan")}, -1),
            ({"width": 0}, -1), ({"points": (ctypes.c_double * 4)(0, 0, math.inf, 0)}, -1),
            ({"output": selected}, -1), ({"selection": out}, -1),
            ({"selection": invalid}, -3),
            ({"points": out}, -1),
        ):
            out[:] = [0xA5] * 64
            with self.subTest(change=change):
                self.assertEqual(call(**change), status)
                self.assertEqual(bytes(out), bytes([0xA5] * 64))

    def test_corrupt_or_incomplete_evidence_is_rejected(self) -> None:
        saved = json.loads(SCALAR.EVIDENCE.read_text(encoding="utf-8"))
        for change in (
            lambda p: p["runs"].pop(),
            lambda p: p["runs"][0].pop(),
            lambda p: p["runs"][0][0].update(mask_sha256="0" * 64),
            lambda p: p["runs"][0][0].update(covered=1),
            lambda p: p["runs"][0][0].update(extra_indices=[100000]),
            lambda p: p["runs"][0][0].update(missing_indices=[1, 1]),
            lambda p: p["runs"][0][0].update(canonical_rgba8_sha256="0" * 64),
            lambda p: p["summary"].update(mismatched_cases=2),
            lambda p: p.update(large_oracle_sha256="0" * 64),
        ):
            with self.subTest(change=change):
                tampered = copy.deepcopy(saved)
                change(tampered)
                with self.assertRaises(ValueError):
                    SCALAR.validate_evidence(tampered)

    def test_runner_generates_replayable_evidence(self) -> None:
        with tempfile.TemporaryDirectory(prefix="t068-scalar-result-") as temporary:
            output = Path(temporary) / "result.json"
            completed = subprocess.run([sys.executable, str(SCALAR.ROOT /
                                     "tools/benchmarks/t068_scalar_hard_brush.py"),
                                     "--output", str(output)], capture_output=True, text=True,
                                     timeout=100, check=False)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertIn("T068_SCALAR_BRUSH_PASSED: 56 native/Godot comparisons; 0 mismatched cases",
                          completed.stdout)
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")),
                             json.loads(SCALAR.EVIDENCE.read_text(encoding="utf-8")))


if __name__ == "__main__":
    unittest.main()
