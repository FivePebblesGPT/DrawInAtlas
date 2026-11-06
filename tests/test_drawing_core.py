"""T-052: exercise real generic Drawing source in a clean Atlas-free Godot project."""

from __future__ import annotations

import re
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_drawing_contract import BUILDER, ROOT

PACKAGE = ROOT / "addons" / "drawing"


class DrawingCoreIsolationTests(unittest.TestCase):
    def test_no_atlas_dependencies_in_canonical_sources(self) -> None:
        files = sorted(PACKAGE.glob("*.gd"))
        self.assertGreaterEqual(len(files), 10)
        for source in files:
            content = source.read_text()
            self.assertNotRegex(content, r"\bAtlas[A-Z]\w*\b")
            self.assertNotIn("res://scripts/", content)
            self.assertNotIn("res://drawing/package/", content)
            for match in re.findall(r'res://addons/drawing/([a-z_]+\.gd)', content):
                self.assertTrue((PACKAGE / match).is_file(), f"{source.name} references missing {match}")

    def test_clean_independent_core_consumer(self) -> None:
        godot = shutil.which("godot")
        if godot is None:
            self.skipTest("Godot is required for package integration verification")
        with tempfile.TemporaryDirectory() as temporary:
            project = BUILDER.stage(Path(temporary) / "consumer", "drawing_core_consumer")
            root_files = {path.name for path in project.iterdir() if path.is_file()}
            self.assertEqual(root_files, {"project.godot", "main.gd", "main.tscn"})
            self.assertEqual(
                {path.name for path in (project / "addons" / "drawing").glob("*.gd")},
                {path.name for path in PACKAGE.glob("*.gd")},
            )
            for source in PACKAGE.iterdir():
                if source.name.endswith((".gd", ".gd.uid")):
                    self.assertEqual(source.read_bytes(), (project / "addons" / "drawing" / source.name).read_bytes())
            for arguments, marker in ((["--headless", "--editor", "--path", str(project), "--import", "--quit"], None),
                                      (["--headless", "--path", str(project), "--quit-after", "120"],
                                       "DRAWING_CORE_PASSED")):
                completed = subprocess.run(
                    [godot, *arguments], capture_output=True, text=True, timeout=120,
                    check=False, env={**os.environ, "GODOT_SILENCE_ROOT_WARNING": "1"},
                )
                output = completed.stdout + completed.stderr
                self.assertEqual(completed.returncode, 0, output)
                self.assertNotIn("SCRIPT ERROR", output)
                self.assertNotIn("Parse Error", output)
                if marker:
                    self.assertIn(marker, output)


if __name__ == "__main__":
    unittest.main()
