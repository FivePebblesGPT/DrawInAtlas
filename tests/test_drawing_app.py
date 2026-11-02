"""T-053: independent Drawing app/third consumer packaging and executable tests."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_drawing_contract import BUILDER, ROOT
from importlib.util import module_from_spec, spec_from_file_location

BUILDER_SPEC = spec_from_file_location("build_drawing_app", ROOT / "tools" / "build_drawing_app.py")
assert BUILDER_SPEC is not None and BUILDER_SPEC.loader is not None
APP_BUILDER = module_from_spec(BUILDER_SPEC)
BUILDER_SPEC.loader.exec_module(APP_BUILDER)

GODOT = shutil.which("godot")


def command(*args: str, timeout: int = 125) -> str:
    assert GODOT is not None
    result = subprocess.run([GODOT, *args], text=True, capture_output=True,
                            timeout=timeout, check=False,
                            env={**os.environ, "GODOT_SILENCE_ROOT_WARNING": "1"})
    output = result.stdout + result.stderr
    if result.returncode != 0 or "SCRIPT ERROR" in output or "Parse Error" in output:
        raise AssertionError(f"Godot exited {result.returncode}: {output}")
    return output


class StandaloneDrawingTests(unittest.TestCase):
    def test_safe_staging_with_one_canonical_package(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            app = APP_BUILDER.stage(folder / "app")
            package = ROOT / "addons" / "drawing"
            self.assertEqual({p.name for p in (app / "addons/drawing").glob("*.gd")},
                             {p.name for p in package.glob("*.gd")})
            for source in package.glob("*.gd"):
                self.assertEqual(source.read_bytes(), (app / "addons/drawing" / source.name).read_bytes())
            self.assertEqual({p.name for p in app.iterdir() if p.is_file()},
                             {"project.godot", "main.tscn", "export_presets.cfg"})
            self.assertFalse((app / "scripts").joinpath("../AtlasCanvas.gd").exists())
            self.assertNotIn("[autoload]", (app / "project.godot").read_text())
            sources = "\n".join(x.read_text() for x in (app / "scripts").glob("*.gd"))
            self.assertNotIn("res://scripts/artwork/", sources)
            self.assertNotIn("AtlasCanvas", sources)
            with self.assertRaises(ValueError):
                APP_BUILDER.stage(ROOT / "drawing" / "out")
            with self.assertRaises(ValueError):
                APP_BUILDER.stage(app)
            self.assertEqual(len(list(app.rglob("*.scn"))), 0)

    @unittest.skipUnless(GODOT, "Godot needed for real isolated app tests")
    def test_clean_standalone_project_and_witness(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = APP_BUILDER.stage(Path(directory) / "drawing")
            command("--headless", "--editor", "--path", str(app), "--import", "--quit")
            output = command("--headless", "--path", str(app),
                             "--script", "res://tests/standalone_smoke.gd")
            self.assertIn("DRAWING_STANDALONE_PASSED", output)
            self.assertIn("38 passed; 0 failed", output)

    @unittest.skipUnless(GODOT, "Godot needed for real third consumer tests")
    def test_third_project_uses_complete_package(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            consumer = BUILDER.stage(Path(directory) / "third", "drawing_package_consumer")
            command("--headless", "--editor", "--path", str(consumer), "--import", "--quit")
            result = command("--headless", "--path", str(consumer), "--quit-after", "120")
            self.assertIn("DRAWING_THIRD_CONSUMER_PASSED", result)


if __name__ == "__main__":
    unittest.main()
