"""T-269: T-089 native layer workflow must work from a clean checkout."""

from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/godot-native-t089-layers.yml"
MAKEFILE = ROOT / "Makefile"


class T269LayerCiTests(unittest.TestCase):
    def test_workflow_builds_native_before_any_test(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("toolchain: 1.99.1", workflow)
        self.assertIn("make build TOOLCHAIN=system", workflow)
        native = workflow.index("make build TOOLCHAIN=system")
        self.assertNotIn("tools/build_drawing_app.py --in-place", workflow)
        for script in ("layer_structure_smoke.gd", "layer_structure_native.gd", "t269_atlas_layers_native.gd"):
            with self.subTest(script=script):
                self.assertGreater(workflow.index(script), native)
        self.assertIn("tools/check_native_t089_log.py", workflow)
        self.assertIn("T089_MODEL_PASSED: 63 checks", workflow)
        self.assertIn("T269_ATLAS: 27 checks; 0 failures", workflow)
        self.assertIn("tools/check_godot_model_log.py", workflow)

    def test_local_make_uses_native_imports_and_pipefail(self) -> None:
        make = MAKEFILE.read_text(encoding="utf-8")
        self.assertIn("test-layer-hierarchy: import-drawing import-atlas", make)
        recipe = make.split("test-layer-hierarchy: import-drawing import-atlas", 1)[1].split("\n# ", 1)[0]
        self.assertIn("SHELL := /bin/bash", make)
        self.assertEqual(recipe.count("set -euo pipefail"), 3)
        for script in ("layer_structure_smoke.gd", "layer_structure_native.gd", "t269_atlas_layers_native.gd"):
            self.assertIn(script, recipe)

    def test_all_logs_and_negative_paths_preserved(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("if: always()", workflow)
        for path in ("/tmp/t089-model.log", "/tmp/t089-native.log", "/tmp/t269-atlas.log"):
            self.assertIn(path, workflow)


if __name__ == "__main__":
    unittest.main()
