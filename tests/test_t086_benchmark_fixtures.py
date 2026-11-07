"""Pinned cold-composite A/B fixture contracts for T-086.

The on-demand native benchmark is deliberately excluded from fast CI, but
fast CI must still detect an accidental historical fixture or oracle drift.
"""

from __future__ import annotations

import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
BENCHMARK = ROOT / "tools/benchmarks/t086_compare_cold_composite.py"


class ColdRendererFixtureContracts(unittest.TestCase):
    """Validate immutable baselines and pre-launch failure behavior."""

    @classmethod
    def setUpClass(cls) -> None:
        spec = importlib.util.spec_from_file_location("t086_cold_compare", BENCHMARK)
        if spec is None or spec.loader is None:
            raise RuntimeError("Cannot load pinned T-086 benchmark")
        cls.benchmark = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.benchmark)

    def test_both_fixtures_match_exact_sha256(self) -> None:
        self.assertEqual(set(self.benchmark.BASELINES), {"pre-fast-path", "pre-indexed-read"})
        for path, digest in self.benchmark.BASELINES.values():
            with self.subTest(path=path.name):
                self.assertTrue(path.is_file())
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), digest)

    def test_controls_precede_direct_sparse_map_access(self) -> None:
        original = self.benchmark.BASELINES["pre-fast-path"][0].read_text()
        previous = self.benchmark.BASELINES["pre-indexed-read"][0].read_text()
        current = (ROOT / "addons/drawing/renderer.gd").read_text()
        self.assertIn("tile.get_rgba(", original)
        self.assertIn("tile.get_rgba(", previous)
        self.assertNotIn("source_pixels.get(pixel_index, 0)", previous)
        self.assertIn("source_pixels.get(pixel_index, 0)", current)
        self.assertNotEqual(current, previous)

    def test_mutated_fixture_rejected_before_spawning_godot(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            altered = Path(directory) / "altered.gd"
            altered.write_text("# tampered baseline\n")
            with patch.dict(self.benchmark.BASELINES, {
                "pre-indexed-read": (altered, "0" * 64)
            }), patch.object(self.benchmark, "stage_project") as stage:
                with self.assertRaisesRegex(RuntimeError, "fixture digest mismatch"):
                    self.benchmark.compare("godot", "pre-indexed-read")
                stage.assert_not_called()


if __name__ == "__main__":
    unittest.main()
