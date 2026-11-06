"""T-093: source-root consent, packaging, native evidence and fail-closed log contracts."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_native_t093_log import verify  # noqa: E402


class T093DiscoveryContracts(unittest.TestCase):
    def test_fast_model_and_native_ui_paths(self) -> None:
        fast = (ROOT / ".github/workflows/godot-check.yml").read_text()
        native = (ROOT / ".github/workflows/godot-native-t093-object-sources.yml").read_text()
        for expected in ("object_discovery_smoke.gd", "T093_MODEL_PASSED", "ci_finish"):
            self.assertIn(expected, fast)
        for expected in ("workflow_dispatch", "--import --quit", "xvfb-run",
                         "object_discovery_native.gd", "T093_SCREENSHOTS",
                         "check_native_t093_log.py", "upload-artifact@v4"):
            self.assertIn(expected, native)

    def test_portable_root_is_opt_in_and_app_local(self) -> None:
        shell = (ROOT / "addons/drawing/workspace.gd").read_text()
        history = (ROOT / "addons/drawing/object_root_history.gd").read_text()
        browser = (ROOT / "addons/drawing/asset_browser_panel.gd").read_text()
        self.assertIn("drawing-recent-objects-root-v1.json", shell)
        self.assertIn("_use_recent_objects_root", shell)
        self.assertIn("_chosen_objects_root", shell)
        self.assertIn("root_display", browser)
        self.assertIn("Choose Objects/ folder", browser)
        self.assertIn("File → Object › New source", browser)
        self.assertIn('path.get_file() == "Objects"', history)
        self.assertNotIn("DrawingFileIO.save", history)
        self.assertIn("DrawingRasterImport.import_image", shell)
        self.assertIn("Open Drawing", shell)
        self.assertIn("Open in Object Editor", browser)
        self.assertIn("Place at view center", browser)

    def test_native_log_rejects_runtime_errors_and_spoofed_markers(self) -> None:
        clean = "T093_NATIVE: 27 checks; 0 failed\nT093_NATIVE_PASSED"
        self.assertEqual(verify(clean), (True, [], 0))
        self.assertEqual(verify(clean + "\nERROR: Texture with GL ID of 12: leaked 512 bytes."),
                         (True, [], 1))
        for bad in ("", "T093_NATIVE_PASSED", clean + "\nT093_NATIVE_PASSED",
                    "T093_NATIVE: 26 checks; 0 failed\nT093_NATIVE_PASSED",
                    "T093_NATIVE: 27 checks; 1 failed\nT093_NATIVE_PASSED",
                    clean + "\nSCRIPT ERROR: bad script", clean + "\nERROR: invalid path",
                    "ERROR: Texture with GL ID of 12: leaked 512 bytes.\n" + clean):
            with self.subTest(bad=bad):
                self.assertFalse(verify(bad)[0])


if __name__ == "__main__":
    unittest.main()
