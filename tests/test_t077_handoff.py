"""T-077 source-only reviewer bundle and documentation evidence checks."""

from __future__ import annotations

import hashlib
import importlib.util
import re
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "build_t038_review_bundle", ROOT / "tools" / "build_t038_review_bundle.py"
)
assert SPEC is not None and SPEC.loader is not None
BUNDLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUNDLE)


class T077HandoffTests(unittest.TestCase):
    """Validate real referenced test paths and intentionally limited review scope."""

    def test_document_links_resolve(self) -> None:
        for name in (
            "DRAWING_TEST_PLAN.md", "DRAWING_PERFORMANCE.md", "CODE_READIBILITY.md",
            "ManualReview_2026-10-30.md", "Tickets/T-077.md",
        ):
            source = ROOT / "docs" / name
            text = source.read_text(encoding="utf-8")
            for target in re.findall(r"\]\(([^)]+)\)", text):
                if target.startswith(("https://", "http://", "mailto:")):
                    continue
                path_text = target.split("#", 1)[0]
                if not path_text:
                    continue
                resolved = (source.parent / path_text).resolve()
                self.assertTrue(resolved.is_file(), f"Broken {source}: {target}")

    def test_referenced_godot_scripts_exist(self) -> None:
        plan = (ROOT / "docs/DRAWING_TEST_PLAN.md").read_text(encoding="utf-8")
        # Distinguish actual scripts from generated project `res://` paths.
        for script in sorted(set(re.findall(r"res://tests/([a-z_0-9]+\.gd)", plan))):
            self.assertTrue((ROOT / "tests" / script).exists() or
                            (ROOT / "drawing" / "tests" / script).exists(), script)
        self.assertIn("DRAWING_THIRD_CONSUMER_PASSED", plan)
        self.assertIn("--headless --editor --path", plan)
        self.assertIn("xvfb-run", plan)
        self.assertIn("$LASTEXITCODE", plan)

    def test_source_only_review_bundle_excludes_documentation(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            first = Path(temp) / "first.zip"
            second = Path(temp) / "second.zip"
            count = BUNDLE.build_bundle(ROOT, first)
            self.assertGreater(count, 100)
            with ZipFile(first) as archive:
                names = archive.namelist()
                self.assertEqual(len(names), count)
                self.assertEqual(names, sorted(names))
                self.assertIn("scripts/editing/raster_brush.gd", names)
                self.assertIn("addons/drawing/document.gd", names)
                self.assertIn("tools/benchmarks/t068_raster_kernel.cpp", names)
                self.assertTrue(all(name.startswith(BUNDLE.SOURCE_PREFIXES) for name in names))
                self.assertTrue(all(Path(name).suffix in BUNDLE.SOURCE_SUFFIXES for name in names))
                self.assertFalse(any("/.git/" in name or "README" in name or
                                     name.startswith(("docs/", ".agents/", "drawing/addons/"))
                                     for name in names))
                self.assertIsNone(archive.testzip())
            self.assertEqual(BUNDLE.build_bundle(ROOT, second), count)
            self.assertEqual(
                hashlib.sha256(first.read_bytes()).digest(),
                hashlib.sha256(second.read_bytes()).digest(),
            )

    def test_handoff_preserves_review_gate_and_benchmark_boundaries(self) -> None:
        plan = (ROOT / "docs/DRAWING_TEST_PLAN.md").read_text(encoding="utf-8")
        performance = (ROOT / "docs/DRAWING_PERFORMANCE.md").read_text(encoding="utf-8")
        readability = (ROOT / "docs/CODE_READIBILITY.md").read_text(encoding="utf-8")
        ticket = (ROOT / "docs/Tickets/T-077.md").read_text(encoding="utf-8")
        for marker in ("T-038", "T-056", "T-057", "T-067", "T-068", "hidden RGB"):
            self.assertIn(marker, plan)
        self.assertIn("manual_review: false", ticket)
        self.assertIn("status: \"Done\"", ticket)
        self.assertIn("historical", performance.lower())
        self.assertIn("generation", readability.lower())
        self.assertIn("T-038", readability)
        self.assertIn("T-068", performance)


if __name__ == "__main__":
    unittest.main()
