"""Guard CI from running Godot script-class consumers before project import."""

import re
import unittest
from pathlib import Path

WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/godot-check.yml"


class GodotCIOrderTests(unittest.TestCase):
    def test_main_project_import_precedes_script_consumers(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        import_cmd = "godot --headless --path . --editor --import --quit"
        main_script = re.search(r"godot --headless --path \. --script res://", workflow)

        self.assertEqual(workflow.count(import_cmd), 1)
        self.assertIsNotNone(main_script, "Expected main-project Godot smoke tests")
        assert main_script is not None
        self.assertLess(
            workflow.index(import_cmd), main_script.start(),
            "Import the main project before running its GDScript class consumers",
        )
        self.assertLess(
            workflow.index("- name: Import resources and parse scripts"),
            workflow.index("- name: Verify T-054 Drawing/Atlas chronological history"),
        )
        self.assertIn(
            "if grep -E 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' /tmp/godot-import.log",
            workflow,
        )


if __name__ == "__main__":
    unittest.main()
