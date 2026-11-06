"""T-073: owner-approved scope is distinct from an unapproved UX prototype.

These contracts pin claims to repository sources, not to model intuition or
successful visual review. Godot pointer/keyboard behavior has separate tests.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
INVENTORY = (DOCS / "DRAWING_FEATURE_INVENTORY.md").read_text(encoding="utf-8")
UI = (DOCS / "DRAW_MODULE_UI_SPEC.md").read_text(encoding="utf-8")
WORKSPACE = (ROOT / "addons/drawing/workspace.gd").read_text(encoding="utf-8")


class ApprovedScopeAndProposedUXTests(unittest.TestCase):
    def test_all_99_scope_rows_preserved_with_authoritative_priorities(self) -> None:
        # Restrict to the original comparative matrix; Atlas boundary/checklist
        # rows are NOT additional feature-scope votes.
        matrix = INVENTORY.split("## Comparative feature matrix", 1)[1].split(
            "## Atlas-specific features", 1
        )[0]
        counts = {"Essential": 0, "Later": 0, "Skip": 0}
        for line in matrix.splitlines():
            if not line.startswith("|") or line.startswith("|---"):
                continue
            columns = [v.strip() for v in line.strip().strip("|").split("|")]
            if len(columns) != 4 or columns[2] == "Choice":
                continue
            category = columns[2].split(" ", 1)[0]
            self.assertIn(category, counts, line)
            counts[category] += 1
        self.assertEqual(counts, {"Essential": 47, "Later": 34, "Skip": 18})
        self.assertIn("OWNER-APPROVED FEATURE INVENTORY", INVENTORY)
        self.assertIn("Owner sign-off (2026-11-02)", INVENTORY)

    def test_scope_approval_not_ux_approval(self) -> None:
        for content in (INVENTORY, UI):
            for phrase in ("47 Essential / 34 Later / 18 Skip", "T-059", "T-063", "T-073"):
                with self.subTest(phrase=phrase):
                    self.assertIn(phrase, content)
        self.assertIn("**Status:** Proposed design", UI)
        self.assertIn("not signed off", UI)
        self.assertIn("manual_review: true", (DOCS / "Tickets/T-059.md").read_text())
        self.assertIn('status: "Done"', (DOCS / "Tickets/T-063.md").read_text())
        self.assertIn('status: "In Progress"', (DOCS / "Tickets/T-065.md").read_text())
        self.assertIn('manual_review: true', (DOCS / "Tickets/T-065.md").read_text())

    def test_accepted_tab_and_browser_requirements_are_not_conflated(self) -> None:
        for doc in (INVENTORY, UI):
            for phrase in ("dedicated Object Editor", "Asset Browser", "dock", "T-062", "T-065"):
                with self.subTest(phrase=phrase):
                    self.assertIn(phrase, doc)
        self.assertIn("Asset Browser as a normal dock peer", INVENTORY)
        self.assertIn("not yet shipped", UI)
        self.assertIn('status: "Done"', (DOCS / "Tickets/T-062.md").read_text())
        self.assertIn("T-063", (DOCS / "Tickets/T-065.md").read_text())
        self.assertIn("func attach_object_session(", WORKSPACE)

    def test_actual_palette_and_menu_claims_match_source(self) -> None:
        self.assertIn('for name: String in ["Brush", "Eraser", "Select", "Move", "Text", "Pan"]', WORKSPACE)
        for name in ("Brush", "Eraser", "Select", "Move", "Text", "Pan"):
            self.assertIn(name, INVENTORY.split("## T-073 implementation ledger", 1)[1])
        for menu in ("File", "Edit", "View", "Image", "Layers", "Select", "Window", "Help"):
            self.assertIn(f'top_bar.add_menu_spec("{menu}"', WORKSPACE)
            self.assertIn(menu, UI.split("**Current UI audit", 1)[1].split("### Concrete", 1)[0])
        self.assertIn("native automation", UI)
        self.assertIn("selection-history", UI)
        self.assertIn("OFF", UI)

    def test_actual_keyboard_routing_and_known_save_as_gap(self) -> None:
        routing = WORKSPACE.split("func _unhandled_key_input(", 1)[1]
        for constant in ("KEY_N", "KEY_O", "KEY_S", "KEY_Z", "KEY_Y", "KEY_W"):
            self.assertIn(constant, routing)
        self.assertIn("if key.shift_pressed:", routing)
        self.assertIn("KEY_S:", routing)
        self.assertIn("_ask_save()", routing)
        for doc in (INVENTORY, UI):
            self.assertIn("Ctrl+Shift+S", doc)
            self.assertIn("Save As", doc)
            self.assertIn("Ctrl+Y", doc)
            self.assertIn("Ctrl+Shift+Z", doc)
            self.assertIn("not", doc.lower())
        self.assertIn("Visible shortcut labels", UI)

    def test_bounded_first_slice_and_future_baseline_not_all_done(self) -> None:
        for doc in (INVENTORY, UI):
            self.assertIn("[x]", doc)
            self.assertIn("[ ]", doc)
            self.assertIn("T-053", doc)
            self.assertIn("T-059", doc)
        self.assertIn("Do not expand the minimum witness retroactively", INVENTORY)
        for ticket in ("T-023", "T-024", "T-025", "T-026", "T-027", "T-064"):
            self.assertIn('status: "Ready"', (DOCS / f"Tickets/{ticket}.md").read_text())
        self.assertIn("Pending native UX", INVENTORY)

    def test_pointer_keyboard_cases_have_observable_results_and_witness_paths(self) -> None:
        for case in ("UX-01", "UX-02", "UX-03", "UX-04", "UX-05", "UX-06", "UX-07", "UX-08"):
            self.assertIn(case, INVENTORY)
        for case in ("UI-01", "UI-02", "UI-03", "UI-04", "UI-05"):
            self.assertIn(case, UI)
        for path in (
            "drawing/tests/standalone_smoke.gd", "drawing/tests/native_pointer.gd",
            "drawing/tests/workspace_keyboard_smoke.gd",
            "drawing/tests/object_editor_ui_smoke.gd", "drawing/tests/text_editor_smoke.gd",
            "tests/object_editor_smoke.gd", "tests/drawing_composition_smoke.gd",
            "tests/drawing_world_mapping_smoke.gd", "tests/drawing_history_smoke.gd",
        ):
            with self.subTest(path=path):
                self.assertTrue((ROOT / path).is_file())
                self.assertIn(path, INVENTORY + UI)
        self.assertIn("100%/150–200%", UI)
        self.assertIn("Shift+wheel", UI)
        self.assertIn("Tab", UI)

    def test_ui_spec_preserves_original_proposal_hierarchy(self) -> None:
        for section in (
            "## 1. Design objective", "## 2. Revised workspace layout",
            "## 3. Compact top bar", "## 4. `BarDivider` design",
            "## 5. Other workspace elements", "## 6. Architectural boundaries",
            "## 7. Implementation phases", "## 8. UX acceptance criteria",
        ):
            self.assertIn(section, UI)
        self.assertLess(UI.index("## Authority, delivered subset"), UI.index("## 1. Design objective"))
        self.assertIn("options container responsible for scrolling", UI)
        self.assertIn("proposal only", UI)

    def test_markdown_local_links_in_scoped_docs_resolve(self) -> None:
        for name, content in (
            ("DRAWING_FEATURE_INVENTORY.md", INVENTORY),
            ("DRAW_MODULE_UI_SPEC.md", UI),
        ):
            for dest in re.findall(r"\]\(([^)]+)\)", content):
                if dest.startswith(("https://", "http://", "mailto:")):
                    continue
                target = dest.split("#", 1)[0]
                if target:
                    with self.subTest(page=name, link=dest):
                        self.assertTrue((DOCS / target).is_file())

    def test_review_gates_and_dependencies_unchanged(self) -> None:
        t073 = (DOCS / "Tickets/T-073.md").read_text()
        self.assertIn('manual_review: false', t073)
        self.assertIn('depends_on: []', t073)
        self.assertIn('status: "Done"', t073)
        for ticket, expected in (("T-059", 'status: "Ready"'), ("T-063", 'status: "Done"'),
                                 ("T-065", 'status: "In Progress"'), ("T-068", 'status: "In Progress"')):
            self.assertIn(expected, (DOCS / f"Tickets/{ticket}.md").read_text())


if __name__ == "__main__":
    unittest.main()
