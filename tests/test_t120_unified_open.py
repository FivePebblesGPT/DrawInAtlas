"""T-120 conventional File/Object/Open routing and fail-closed evidence contracts."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_native_t120_log import verify  # noqa: E402


class T120UnifiedOpenContracts(unittest.TestCase):
    def setUp(self) -> None:
        self.workspace = (ROOT / "addons/drawing/workspace.gd").read_text()
        self.top_bar = (ROOT / "addons/drawing/editor_top_bar.gd").read_text()

    def test_conventional_file_menu_is_separate_from_object_source_commands(self) -> None:
        file_spec = self.workspace.split('top_bar.add_menu_spec("File"', 1)[1].split(
            'top_bar.add_menu_spec("Object"', 1)[0]
        object_spec = self.workspace.split('top_bar.add_menu_spec("Object"', 1)[1].split(
            'top_bar.add_menu_spec("Edit"', 1)[0]
        for label in ("New  Ctrl+N", "Open…  Ctrl+O", "Save  Ctrl+S",
                      "Save As…  Ctrl+Shift+S", "Close Tab  Ctrl+W"):
            self.assertIn(label, file_spec)
        for label in ("New Source", "Open Source…", "Rename Source…",
                      "Save Source As…", "Browse Sources…"):
            self.assertIn(label, object_spec)
            self.assertNotIn(label, file_spec)
        self.assertNotIn('"Import Image as Drawing…"', self.workspace)
        self.assertNotIn("image_import_dialog", self.workspace)

    def test_one_open_chooser_dispatches_original_drawing_or_bounded_raster(self) -> None:
        for ext in ("*.drawing", "*.png", "*.webp", "*.jpg", "*.jpeg"):
            self.assertIn(ext, self.workspace)
        self.assertIn('open_dialog.file_selected.connect(_open_file)', self.workspace)
        self.assertIn('func _open_file(path: String)', self.workspace)
        self.assertIn('"png", "webp", "jpg", "jpeg":', self.workspace)
        self.assertIn('DrawingFileIO.open_with_frame(path)', self.workspace)
        self.assertIn('DrawingRasterImport.import_image(document, raster,', self.workspace)
        self.assertIn('"path": "", "title": "Imported: " + path.get_file()', self.workspace)
        self.assertIn('"frame": image_bounds', self.workspace)
        self.assertIn('"saved": -1', self.workspace)
        self.assertIn('64 * 1024 * 1024', self.workspace)
        self.assertIn('16777216', self.workspace)
        self.assertIn('func _raster_header_matches(', self.workspace)
        self.assertIn('current_object() != null', self.workspace)
        self.assertIn('if not path.to_lower().ends_with(".drawing"):', self.workspace)

    def test_real_overflow_maps_original_commands_with_checkmark_parity(self) -> None:
        for contract in ('more.add_item("%s › %s"', '_more_actions.append(handlers[command])',
                         'more.set_item_checked(item_id, original.is_item_checked(command))',
                         'var available_width: float = size.x',
                         'available_width = minf(available_width, (ancestor as Control).size.x)'):
            self.assertIn(contract, self.top_bar)

    def test_headless_native_and_neighboring_ci_have_exact_oracles(self) -> None:
        fast = (ROOT / ".github/workflows/godot-check.yml").read_text()
        native = (ROOT / ".github/workflows/godot-native-t093-object-sources.yml").read_text()
        for term in ('res://tests/t120_unified_open_smoke.gd', '--marker T120_MODEL_PASSED',
                     'test_t120_unified_open.py'):
            self.assertIn(term, fast)
        for term in ('res://tests/t120_file_object_native.gd', 'T120_SCREENSHOTS',
                     'check_native_t120_log.py', 'xvfb-run', 'upload-artifact@v4'):
            self.assertIn(term, native)
        self.assertIn('T120_MODEL_PASSED',
                      (ROOT / 'drawing/tests/t120_unified_open_smoke.gd').read_text())
        self.assertIn('T120_NATIVE_PASSED',
                      (ROOT / 'drawing/tests/t120_file_object_native.gd').read_text())

    def test_native_log_accepts_only_explicit_post_success_teardown_leaks(self) -> None:
        good = 'T120_NATIVE: 20 checks; 0 failed\nT120_NATIVE_PASSED\n'
        self.assertEqual(verify(good), (True, [], 0))
        leak = "ERROR: Texture with GL ID of 73: leaked 131072 bytes.\n"
        self.assertEqual(verify(good + leak), (True, [], 1))
        for invalid in ('', 'T120_NATIVE_PASSED\n',
                        'T120_NATIVE: 19 checks; 0 failed\nT120_NATIVE_PASSED\n',
                        'T120_NATIVE: 20 checks; 1 failed\nT120_NATIVE_PASSED\n',
                        good + 'T120_NATIVE_PASSED\n',
                        good + 'T120_NATIVE: 20 checks; 0 failed\n',
                        good + 'SCRIPT ERROR: failed import\n',
                        good + 'T120_NATIVE_FAILED: bad pixel\n',
                        good + 'ERROR: unknown runtime error\n',
                        leak + good, good + 'Segmentation fault\n'):
            with self.subTest(invalid=invalid[:60]):
                self.assertFalse(verify(invalid)[0])


if __name__ == '__main__':
    unittest.main()
