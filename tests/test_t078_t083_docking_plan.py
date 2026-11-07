"""Proposed panel-docking roadmap must preserve the owner's group/flyout rules.

These are planning/document contract checks, not proof of working drag-and-drop
or of a completed native UX review.
"""

from __future__ import annotations

import re
import tempfile
import unittest
from pathlib import Path

from tools.validate_ticket_store import parse_ticket

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
        for ticket_id in TICKETS:
            with self.subTest(ticket=ticket_id):
                errors: list[str] = []
                record = parse_ticket(DOCS / f"Tickets/T-{ticket_id:03}.md", errors)
                self.assertFalse(errors, errors)
                self.assertIsNotNone(record)
                self.assertEqual(record.manual_review, ticket_id == 83)
                if ticket_id == 83 and record.status == "Done":
                    self.assertTrue(record.approved and record.evidence)
                if not record.manual_review:
                    self.assertFalse(record.approved)
        self.assertIn("**Owner**", next(
            line for line in INDEX.splitlines() if line.startswith("| [T-083 ·")
        ))
        for earlier in (56, 59):
            errors: list[str] = []
            record = parse_ticket(DOCS / f"Tickets/T-{earlier:03}.md", errors)
            self.assertFalse(errors, errors)
            self.assertIsNotNone(record)
            self.assertTrue(record.manual_review)

    def test_example_approval_text_in_body_does_not_set_owner_gate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "T-083.md"
            path.write_text(
                '---\nstatus: "In Progress"\nmanual_review: true\nid: T-083\n'
                'depends_on: []\n---\n'
                'Owner must set `manual_review_approved: true` with evidence; '
                'this is an instruction, not approval.\n',
                encoding="utf-8",
            )
            errors: list[str] = []
            record = parse_ticket(path, errors)
            self.assertFalse(errors, errors)
            self.assertIsNotNone(record)
            self.assertFalse(record.approved)
            self.assertEqual(record.evidence, "")

    def test_real_approval_metadata_requires_evidence_and_manual_gate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "T-083.md"
            for manual_review, evidence, expected_error in (
                ("true", "", "requires review_evidence"),
                ("false", "2026-11-07 owner accepted", "only a manual-review ticket"),
                ("true", "2026-11-07 owner accepted", None),
            ):
                with self.subTest(manual_review=manual_review, evidence=evidence):
                    path.write_text(
                        '---\nstatus: "Manual Review"\nid: T-083\n'
                        f'manual_review: {manual_review}\n'
                        'manual_review_approved: true\n'
                        f'review_evidence: "{evidence}"\n'
                        'depends_on: []\n---\n',
                        encoding="utf-8",
                    )
                    errors: list[str] = []
                    record = parse_ticket(path, errors)
                    self.assertIsNotNone(record)
                    self.assertTrue(record.approved)
                    if expected_error:
                        self.assertTrue(any(expected_error in error for error in errors), errors)
                    else:
                        self.assertFalse(errors, errors)
                        self.assertEqual(record.evidence, evidence)

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
