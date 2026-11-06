"""Proposed panel-docking roadmap must preserve the owner's group/flyout rules.

These are planning/document contract checks, not proof of working drag-and-drop
or of a completed native UX review.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
PLAN = (DOCS / "DRAWING_DOCKING_SPEC.md").read_text(encoding="utf-8")
INDEX = (DOCS / "Index.md").read_text(encoding="utf-8")
UI = (DOCS / "DRAW_MODULE_UI_SPEC.md").read_text(encoding="utf-8")
TICKETS = {
    number: (DOCS / f"Tickets/T-{number:03}.md").read_text(encoding="utf-8")
    for number in range(78, 84)
}


def frontmatter(source: str) -> str:
    match = re.match(r"\A---\n(.*?)\n---\n", source, re.S)
    if match is None:
        raise AssertionError("Missing ticket frontmatter")
    return match.group(1)


class GroupedPanelDockRoadmapTests(unittest.TestCase):
    def test_all_six_tickets_have_ordered_hard_dependencies(self) -> None:
        for ticket_id, contents in TICKETS.items():
            with self.subTest(ticket=ticket_id):
                fields = frontmatter(contents)
                self.assertIn(f"id: T-{ticket_id:03}", fields)
                preceding = ticket_id - 1 if ticket_id > 78 else 63
                self.assertIn(f'depends_on: ["[[T-{preceding:03}]]"]', fields)
                if ticket_id == 78:
                    self.assertIn("docking specification", contents.lower())

    def test_kanban_rows_match_ticket_frontmatter(self) -> None:
        allowed = {"Ready", "In Progress", "Blocked", "Manual Review", "Done", "Archived"}
        for ticket_id, contents in TICKETS.items():
            with self.subTest(ticket=ticket_id):
                status_match = re.search(r'^status: "([^"]+)"$', frontmatter(contents), re.M)
                self.assertIsNotNone(status_match)
                status = status_match.group(1)
                self.assertIn(status, allowed)
                row = next(
                    line for line in INDEX.splitlines()
                    if line.startswith(f"| [T-{ticket_id:03} ·")
                )
                self.assertIn(f" | {status} | ", row)
        self.assertIn("| 83 |", INDEX)

    def test_only_final_ticket_has_new_manual_review_gate(self) -> None:
        for ticket_id, contents in TICKETS.items():
            expected = "true" if ticket_id == 83 else "false"
            self.assertIn(f"manual_review: {expected}", frontmatter(contents))
            self.assertNotIn("manual_review_approved: true", contents)
        self.assertIn("**Owner**", next(
            line for line in INDEX.splitlines() if line.startswith("| [T-083 ·")
        ))
        for earlier in (56, 59):
            existing = (DOCS / f"Tickets/T-{earlier:03}.md").read_text()
            self.assertIn("manual_review: true", frontmatter(existing))

    def test_icon_rail_has_panel_icons_but_group_boundaries(self) -> None:
        for phrase in (
            "one icon per attached panel", "separator", "group boundary",
            "shared flyout", "clicked panel", "Color/Swatches/Gradients/Patterns",
        ):
            with self.subTest(phrase=phrase):
                self.assertIn(phrase.lower(), PLAN.lower())
        self.assertIn("group flyout", TICKETS[79])
        self.assertIn("each individual panel keeps its own icon", UI.lower())

    def test_floating_hosts_are_tabbed_and_non_os(self) -> None:
        for phrase in (
            "floating container", "same grouping", "in-app", "current relative order",
            "native OS window",
        ):
            self.assertIn(phrase.lower(), PLAN.lower())
        self.assertIn("Control-based", TICKETS[81])
        self.assertIn("two different tabs", TICKETS[81])
        self.assertIn("Whole-group redock", TICKETS[82])

    def test_drag_previews_and_cancel_are_explicit(self) -> None:
        for number in (78, 82):
            self.assertIn("transaction", TICKETS[number].lower())
        self.assertIn("roll back", TICKETS[80].lower())
        for phrase in ("cursor", "insertion", "invalid", "Esc"):
            self.assertIn(phrase.lower(), TICKETS[82].lower())
        self.assertIn("same ordered structure", TICKETS[80])

    def test_no_existing_feature_or_owner_gate_is_claimed_complete(self) -> None:
        self.assertIn("T-059", UI)
        self.assertIn("T-056", UI)
        self.assertIn("**not** approval", TICKETS[83])
        self.assertIn('status: "Done"', (DOCS / "Tickets/T-063.md").read_text())
        self.assertIn("T-065", (DOCS / "Tickets/T-063.md").read_text())

    def test_spec_and_index_cross_reference_all_six_tickets(self) -> None:
        for number in range(78, 84):
            ref = f"Tickets/T-{number:03}.md"
            self.assertIn(ref, PLAN)
            self.assertIn(ref, INDEX)
        self.assertIn("DRAWING_DOCKING_SPEC.md", UI)
        self.assertIn("DRAWING_DOCKING_SPEC.md", (DOCS / "Tickets/T-063.md").read_text())


if __name__ == "__main__":
    unittest.main()
