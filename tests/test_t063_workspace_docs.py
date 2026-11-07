"""T-063 current workspace contract and postponed UX/Asset Browser gates."""

from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = (ROOT / "addons/drawing/workspace.gd").read_text(encoding="utf-8")
TOP_BAR = (ROOT / "addons/drawing/editor_top_bar.gd").read_text(encoding="utf-8")
UI = (ROOT / "docs/DRAW_MODULE_UI_SPEC.md").read_text(encoding="utf-8")
TICKET = (ROOT / "docs/Tickets/T-063.md").read_text(encoding="utf-8")
NATIVE = (ROOT / "drawing/tests/compact_workspace_smoke.gd").read_text(encoding="utf-8")


class CompactDrawingWorkspaceContractTests(unittest.TestCase):
    def test_can_be_used_without_atlas_code(self) -> None:
        for source in (WORKSPACE, TOP_BAR):
            self.assertNotIn('preload("res://scripts/', source)
            self.assertNotIn('load("res://scripts/', source)
        self.assertIn('const TOP_BAR_SCRIPT: Script = preload("res://addons/drawing/editor_top_bar.gd")', WORKSPACE)

    def test_menu_order_and_no_duplicate_action_toolbar(self) -> None:
        menu_positions = [WORKSPACE.index(f'top_bar.add_menu_spec("{name}"') for name in
                          ("File", "Edit", "View", "Image", "Layers", "Select", "Window", "Help")]
        self.assertEqual(menu_positions, sorted(menu_positions))
        self.assertIn('divider.name = "BarDivider"', TOP_BAR)
        self.assertIn('options_scroll.name = "ToolOptionsRegion"', TOP_BAR)
        self.assertNotIn('for action in ["New", "Open", "Save", "Undo"]', WORKSPACE)

    def test_commands_and_history_preference_are_real(self) -> None:
        self.assertIn('"Save As…  Ctrl+Shift+S"', WORKSPACE)
        self.assertIn('KEY_S:', WORKSPACE)
        self.assertIn('if key.shift_pressed:', WORKSPACE)
        self.assertIn('_ask_save()', WORKSPACE)
        self.assertIn('"Redo  Ctrl+Y"', WORKSPACE)
        self.assertIn('selection_history_toggle.toggled.connect(_selection_history_preference_changed)', WORKSPACE)
        self.assertIn('"Preferences…"', WORKSPACE)
        self.assertIn('func _load_preferences()', WORKSPACE)

    def test_context_options_and_scrolling(self) -> None:
        for term in ('if active_tool in ["Brush", "Eraser"]',
                     'if active_tool in ["Brush", "Eraser", "Select", "Move", "Text"]',
                     'top_bar.set_tool_controls(active_tool, controls)'):
            self.assertIn(term, WORKSPACE)
        for term in ('options_scroll.ensure_control_visible', 'options_scroll.scroll_horizontal = 0',
                     'source.accept_event()', 'left_cue.visible = overflow', 'right_cue.visible = overflow',
                     'more_menu.visible = not _more_actions.is_empty()'):
            self.assertIn(term, TOP_BAR)

    def test_dock_and_status(self) -> None:
        for term in ('dock_split = HSplitContainer.new()', 'inspector = ScrollContainer.new()',
                     '_add_dock_section("History")', 'func _toggle_dock()',
                     'func _reset_dock_width()', 'cursor %d,%d', 'zoom %.0f%%',
                     'inspector.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO',
                     'func _toggle_document_tabs()', 'func _cycle_tab(direction: int)'):
            self.assertIn(term, WORKSPACE)

    def test_user_refinements_are_packaged_and_tested(self) -> None:
        for name in ("brush", "eraser", "select", "move", "text", "pan"):
            asset = ROOT / f"addons/drawing/icons/{name}.svg"
            self.assertTrue(asset.is_file(), name)
            self.assertIn('<svg xmlns="http://www.w3.org/2000/svg"', asset.read_text())
        self.assertIn('button.icon = load(', WORKSPACE)
        self.assertIn('button.tooltip_text = "Drawing tool: " + name', WORKSPACE)
        self.assertIn('func _refresh_tool_buttons()', WORKSPACE)
        self.assertIn('top_bar.set_menu_checked("Window", 2, show_document_tabs)', WORKSPACE)
        self.assertIn('KEY_TAB: _cycle_tab(', WORKSPACE)
        self.assertIn('tab_identity', WORKSPACE)
        self.assertIn('icons = PACKAGE / "icons"',
                      (ROOT / "tools/build_drawing_app.py").read_text())
        self.assertIn('icons = PACKAGE / "icons"',
                      (ROOT / "tools/build_drawing_contract_consumer.py").read_text())
        for witness in ('six tools share the icon rail', 'Ctrl+Shift+Tab cycles backward',
                        'keyboard focus brings History events into scroll viewport',
                        'hidden tabs still enforce unsaved document close prompt'):
            self.assertIn(witness, NATIVE)

    def test_native_witness_is_live_and_touches_required_behaviors(self) -> None:
        for term in ('T063_WORKSPACE_PASSED', 'Ctrl+Shift+S', 'get_popup()',
                     'root.content_scale_factor = 1.5', 'root.size = Vector2i(420, 600)',
                     'top.consume_option_wheel', 'grab_focus()', '_request_close_current()'):
            self.assertIn(term, NATIVE)
        self.assertTrue((ROOT / "drawing/tests/workspace_keyboard_smoke.gd").is_file())

    def test_ticket_and_browser_dependencies_are_consistent(self) -> None:
        self.assertIn('status: "Done"', TICKET)
        self.assertIn('manual_review: false', TICKET)
        self.assertIn('depends_on: ["[[T-053]]"]', TICKET)
        browser_ticket = (ROOT / "docs/Tickets/T-065.md").read_text(encoding="utf-8")
        self.assertIn('status: "In Progress"', browser_ticket)
        self.assertIn('manual_review: true', browser_ticket)
        self.assertNotIn('status: "Done"', browser_ticket)
        self.assertIn('status: "Ready"', (ROOT / "docs/Tickets/T-059.md").read_text(encoding="utf-8"))
        self.assertIn('status: "Ready"', (ROOT / "docs/Tickets/T-056.md").read_text(encoding="utf-8"))

    def test_approved_feature_scope_is_not_ux_approval(self) -> None:
        self.assertIn('**Status:** Proposed design', UI)
        self.assertIn('owner', UI.lower())
        self.assertIn('T-059', UI)
        self.assertIn('T-065', UI)
        self.assertIn('not yet shipped', UI)
        self.assertIn('47 Essential / 34 Later / 18 Skip', UI)


if __name__ == "__main__":
    unittest.main()
