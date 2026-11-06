#!/usr/bin/env python3
"""Validate ticket status metadata, the Kanban index, and owner-review closure gates."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TICKETS = ROOT / "docs" / "Tickets"
INDEX = ROOT / "docs" / "Index.md"
STATUSES = {"Ready", "In Progress", "Blocked", "Manual Review", "Done", "Archived"}
FIELD = re.compile(r"(?m)^([A-Za-z_]+):\s*(.*)$")
DEP = re.compile(r"\[\[T-(\d{3})\]\]")
ROW = re.compile(
    r"^\|\s*\[T-(\d{3})\s*[·—][^\]]*\]\(Tickets/T-(\d{3})\.md\)"
    r"\s*\|\s*([^|]+)\|"
)


@dataclass(frozen=True)
class Ticket:
    number: str
    status: str
    manual_review: bool
    approved: bool
    evidence: str
    dependencies: tuple[str, ...]


def parse_ticket(path: Path, errors: list[str]) -> Ticket | None:
    content = path.read_text(encoding="utf-8")
    fm = re.match(r"\A---\n(.*?)\n---\n", content, flags=re.S)
    if fm is None:
        errors.append(f"{path}: missing YAML frontmatter")
        return None
    fields = {key: value.strip().strip('"') for key, value in FIELD.findall(fm.group(1))}
    number = path.stem
    if fields.get("id") != number:
        errors.append(f"{path}: id does not match filename")
    status = fields.get("status", "")
    if status not in STATUSES:
        errors.append(f"{path}: unknown status {status!r}")
    review_value = fields.get("manual_review")
    if review_value not in {"true", "false"}:
        errors.append(f"{path}: manual_review must be true/false")
    approved = fields.get("manual_review_approved", "false") == "true"
    evidence = fields.get("review_evidence", "")
    if approved and not evidence:
        errors.append(f"{path}: manual_review_approved requires review_evidence")
    if approved and review_value != "true":
        errors.append(f"{path}: only a manual-review ticket may carry approval")
    return Ticket(
        number=number,
        status=status,
        manual_review=review_value == "true",
        approved=approved,
        evidence=evidence,
        dependencies=tuple(f"T-{s}" for s in DEP.findall(fields.get("depends_on", ""))),
    )


def main() -> int:
    errors: list[str] = []
    tickets: dict[str, Ticket] = {}
    for path in sorted(TICKETS.glob("T-*.md")):
        ticket = parse_ticket(path, errors)
        if ticket is None:
            continue
        if ticket.number in tickets:
            errors.append(f"Duplicate ticket {ticket.number}")
        tickets[ticket.number] = ticket

    for ticket in tickets.values():
        for dep in ticket.dependencies:
            if dep not in tickets:
                errors.append(f"{ticket.number}: missing dependency {dep}")

    state: dict[str, int] = {}
    def ancestors(number: str) -> set[str]:
        if state.get(number) == 1:
            errors.append(f"Cycle in ticket dependencies involving {number}")
            return set()
        if state.get(number) == 2:
            return cache[number]
        state[number] = 1
        found: set[str] = set()
        for dep in tickets[number].dependencies:
            if dep in tickets:
                found.add(dep)
                found.update(ancestors(dep))
        state[number] = 2
        cache[number] = found
        return found

    cache: dict[str, set[str]] = {}
    for ticket in tickets.values():
        upstream = ancestors(ticket.number)
        if ticket.status != "Done":
            continue
        for dep in ticket.dependencies:
            if dep in tickets and tickets[dep].status != "Done":
                errors.append(f"{ticket.number}: Done but prerequisite {dep} is not Done")
        for dep in upstream | {ticket.number}:
            required = tickets[dep]
            if required.manual_review and not (required.approved and required.evidence):
                errors.append(
                    f"{ticket.number}: Done without owner approval for {dep}"
                )

    rows: dict[str, str] = {}
    for line in INDEX.read_text(encoding="utf-8").splitlines():
        match = ROW.match(line)
        if match is None:
            continue
        left_id, path_id, status = match.groups()
        number = f"T-{left_id}"
        if left_id != path_id:
            errors.append(f"Index link mismatch: {number} -> T-{path_id}")
        if number in rows:
            errors.append(f"Duplicate Index row for {number}")
        rows[number] = status.strip()

    for number, ticket in tickets.items():
        if number not in rows:
            errors.append(f"Index missing {number}")
        elif rows[number] != ticket.status:
            errors.append(
                f"{number}: Index says {rows[number]!r}, frontmatter says {ticket.status!r}"
            )
    for number in rows.keys() - tickets.keys():
        errors.append(f"Index contains missing ticket {number}")

    if errors:
        for error in errors:
            print("ERROR:", error, file=sys.stderr)
        print(f"Ticket validation failed ({len(errors)} problems).", file=sys.stderr)
        return 1
    print(f"Validated {len(tickets)} tickets and manual-review dependency gates.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
