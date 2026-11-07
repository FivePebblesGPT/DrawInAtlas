"""T-090 bounded responsive chrome, keyboard/wheel and MIT tool-icon contracts.

The native counterpart verifies actual resize pixels, tab-glyph pointer dispatch,
menu items and hovered SpinBox wheel behavior with pinned Godot/Xvfb.
"""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_native_t090_log import verify  # noqa: E402


class ResponsiveDrawingWorkspaceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.workspace = (ROOT / "addons/drawing/workspace.gd").read_text()
        self.topbar = (ROOT / "addons/drawing/editor_top_bar.gd").read_text()

    def test_desktop_resize_preserves_logical_ui_pixels(self) -> None:
        project = (ROOT / "drawing/project.godot").read_text()
        for property_ in (
            'window/stretch/mode="disabled"',
            'window/size/min_width=800',
            'window/size/min_height=600',
        ):
            self.assertIn(property_, project)
        self.assertNotIn('window/stretch/mode="canvas_items"', project)
        self.assertIn("Control.PRESET_FULL_RECT", self.workspace)
        self.assertIn("Control.SIZE_EXPAND_FILL", self.workspace)
        self.assertIn("editor_column.add_child(tabs_line)", self.workspace)
        self.assertIn("editor_column.add_child(canvas)", self.workspace)
        self.assertNotIn("root.add_child(tabs_line)", self.workspace)
        canvas = (ROOT / "addons/drawing/canvas.gd").read_text()
        self.assertIn("texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST", canvas)
        self.assertIn("_draw_pixel_grid_overlay()", canvas)
        self.assertIn("var show_pixel_grid: bool = true", canvas)
        self.assertIn("func _raster_screen_rect(area: Rect2i)", canvas)
        self.assertIn("_raster_screen_rect(area), false", canvas)
        self.assertIn("Pixel grid at high zoom", self.workspace)
        self.assertIn("func _toggle_pixel_grid()", self.workspace)

    def test_file_and_object_commands_are_outside_window(self) -> None:
        file_section = self.workspace.split('top_bar.add_menu_spec("File"', 1)[1].split(
            'top_bar.add_menu_spec("Edit"', 1)[0]
        window_section = self.workspace.split('top_bar.add_menu_spec("Window"', 1)[1].split(
            'top_bar.set_menu_checked("Window"', 1)[0]
        for label in ("Close tab  Ctrl+W", "Object › New source", "Object › Open source",
                      "Object › Rename source", "Object › Save source As"):
            self.assertIn(label, file_section)
            self.assertNotIn(label, window_section)
        for label in ("Reset workspace layout", "Show document tabs", "Asset Browser"):
            self.assertIn(label, window_section)
        self.assertIn("KEY_N: new_drawing()", self.workspace)

    def test_per_tab_close_keeps_unsaved_guard(self) -> None:
        self.assertIn("tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS", self.workspace)
        self.assertIn("tab_bar.tab_close_pressed.connect(_request_close_tab)", self.workspace)
        self.assertIn("_tab_close_hit(click.position)", self.workspace)
        self.assertNotIn('add_tab.text = "+"', self.workspace)
        self.assertNotIn('close_tab.text = "×"', self.workspace)
        self.assertIn("close_dialog.popup_centered()", self.workspace)
        self.assertIn("_request_close_tab(active_tab)", self.workspace)

    def test_brush_wheel_and_keys_are_field_actions(self) -> None:
        self.assertIn("if mouse.shift_pressed", self.topbar)
        self.assertIn("elif source is SpinBox:", self.topbar)
        self.assertIn("spin.value = clampf", self.topbar)
        self.assertIn("source.accept_event()", self.topbar)
        self.assertIn("KEY_BRACKETLEFT, KEY_BRACKETRIGHT", self.workspace)
        self.assertIn('active_tool not in ["Brush", "Eraser"]', self.workspace)
        self.assertIn("focused is LineEdit", self.workspace)

    def test_at_icons_license_and_standalone_staging(self) -> None:
        license_file = ROOT / "addons/drawing/icons/LICENSE.at-icons.txt"
        self.assertEqual(license_file.read_bytes(), (ROOT / "addons/at-icons/LICENSE.txt").read_bytes())
        self.assertIn("MIT License", license_file.read_text())
        for target, source in {
            "brush": "brush", "eraser": "eraser", "select": "selection_square",
            "move": "move", "text": "text", "pan": "hand",
        }.items():
            actual = (ROOT / f"addons/drawing/icons/{target}.svg").read_bytes()
            original = (ROOT / f"addons/at-icons/control/{source}.svg").read_bytes()
            with self.subTest(icon=target):
                self.assertEqual(actual, original)
                self.assertIn(b"<svg", actual)
        for builder in ("build_drawing_app.py", "build_drawing_contract_consumer.py"):
            staged = (ROOT / "tools" / builder).read_text()
            self.assertIn('license_file = icons / "LICENSE.at-icons.txt"', staged)
            self.assertIn('shutil.copy2(license_file', staged)

    def test_compact_rail_and_centered_tool_glyphs(self) -> None:
        self.assertIn('rail.custom_minimum_size.x = 42', self.workspace)
        self.assertIn('button.custom_minimum_size = Vector2(34, 34)', self.workspace)
        self.assertIn('button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER', self.workspace)
        native = (ROOT / "drawing/tests/responsive_workspace_native.gd").read_text()
        self.assertIn('func check_tool_glyph_centers', native)
        self.assertIn('image.get_pixel(x, y)', native)
        self.assertIn('await click_at(button.get_global_rect().get_center())', native)

    def test_native_witness_covers_pointer_framebuffer_and_scaling(self) -> None:
        source = (ROOT / "drawing/tests/responsive_workspace_native.gd").read_text()
        for term in ("T090_NATIVE_PASSED", "root.push_input", "get_texture().get_image()",
                     "Vector2i(800, 600)", "Vector2i(1920, 1080)", "1.5, 2.0",
                     "click_at(close_point)", "wheel_at(hover, 1)", "KEY_BRACKETRIGHT"):
            self.assertIn(term, source)

    def test_native_log_verifier_fails_closed(self) -> None:
        good = "T090_NATIVE: 72 checks; 0 failed\nT090_NATIVE_PASSED: 72 checks\n"
        self.assertTrue(verify(good)[0])
        self.assertTrue(verify(good + "ERROR: Texture with GL ID of 24: leaked 1364 bytes.\n")[0])
        for bad in (
            good.replace("72 checks", "71 checks"),
            good.replace("0 failed", "1 failed"),
            good + "SCRIPT ERROR: broken\n",
            "ERROR: runtime fail\n" + good,
            good + "ERROR: unknown fatal\n",
            "T090_NATIVE_PASSED: 72 checks\n",
        ):
            with self.subTest(bad=bad[:40]):
                self.assertFalse(verify(bad)[0])


if __name__ == "__main__":
    unittest.main()
