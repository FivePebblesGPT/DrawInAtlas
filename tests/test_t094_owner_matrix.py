"""T-094: preserve every owner finding and pending manual review as evidence, not a claim."""
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
REVIEW = (DOCS / "DRAWING_USABILITY_REVIEW_2026-11-05.md").read_text(encoding="utf-8")
MATRIX = (DOCS / "DRAWING_OWNER_ACCEPTANCE_MATRIX.md").read_text(encoding="utf-8")


def _rows(markdown: str) -> dict[int, list[str]]:
    """Extract only numbered findings, not milestone/checklist tables."""
    result: dict[int, list[str]] = {}
    for line in markdown.splitlines():
        match = re.match(r"^\|\s*(\d{1,2})\s*\|", line)
        if match:
            number = int(match.group(1))
            if number in result:
                raise ValueError(f"Duplicate finding {number}")
            result[number] = [cell.strip() for cell in line.strip().strip("|").split("|")]
    return result


class OwnerAcceptanceMatrixContracts(unittest.TestCase):
    def test_every_owner_finding_is_actionable_and_mapped_to_same_tickets(self) -> None:
        owners = _rows(REVIEW)
        actions = _rows(MATRIX)
        self.assertEqual(set(owners), set(range(1, 24)))
        self.assertEqual(set(actions), set(owners))
        for number, row in actions.items():
            with self.subTest(finding=number):
                self.assertEqual(len(row), 6, row)
                self.assertGreater(len(row[2]), 40, "Missing physical action/setup")
                self.assertGreater(len(row[3]), 40, "Missing observable pass condition")
                self.assertGreater(len(row[4]), 12, "Missing evidence boundary")
                owner_tickets = set(re.findall(r"T-\d{3}", owners[number][2]))
                mapped_tickets = set(re.findall(r"T-\d{3}", row[1]))
                self.assertEqual(owner_tickets, mapped_tickets)
                for ticket in mapped_tickets:
                    self.assertTrue((DOCS / f"Tickets/{ticket}.md").is_file())
                if number == 22:
                    self.assertEqual(row[5], "OWNER PASS / REGRESSION")
                elif number == 23:
                    self.assertEqual(row[5], "MODEL EXPECTED / UI PENDING")
                else:
                    self.assertEqual(row[5], "PENDING")

    def test_physical_evidence_cannot_be_replaced_by_headless_or_software_gpu(self) -> None:
        for required in ("physical Linux and Windows", "software-only", "100%, 50%, 25%",
                         "1280×720", "150%", "median/p95", "before-release framebuffer",
                         "SHA-256", "NOT RUN", "input-to-photon latency", "T-085", "T-093"):
            with self.subTest(required=required):
                self.assertIn(required, MATRIX)
        for ticket in ("T-056", "T-059", "T-065", "T-083"):
            with self.subTest(gate=ticket):
                self.assertIn("manual_review: true", (DOCS / f"Tickets/{ticket}.md").read_text())
                self.assertIn(ticket, MATRIX)
        self.assertIn("owner explicitly accepts", MATRIX)

    def test_positive_roundtrip_is_a_real_regression_not_an_invented_bug(self) -> None:
        smoke = (ROOT / "drawing/tests/standalone_smoke.gd").read_text(encoding="utf-8")
        for contract in ("_save_file(file_path)", "_open_file(file_path)",
                         "0x00332211", "reopened.id == document.id", "CORRUPT_TILE",
                         "DRAWING_STANDALONE_PASSED"):
            self.assertIn(contract, smoke)
        self.assertIn("monotonic", MATRIX)


if __name__ == "__main__":
    unittest.main()
