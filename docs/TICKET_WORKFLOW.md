# Ticket Kanban and review gates

**Authority:** `docs/Tickets/T-*.md` YAML frontmatter is canonical. `docs/Index.md` is the human-readable table generated/validated against it. Historic checkbox lists and status prose in ticket bodies record earlier work and may describe an older phase; they do not override frontmatter.

## Kanban statuses
| Status | Meaning | Agent action |
| --- | --- | --- |
| **Ready** | Work can be started using approved scope; no outstanding hard prerequisite | Implement/document/test autonomously |
| **In Progress** | Active implementation with evidence not yet complete | Continue autonomously; record current findings |
| **Blocked** | Hard dependencies remain unfinished, including future manual-review gates | Do independent preparatory work, but **do not mark Done** |
| **Manual Review** | The specific owner or independent-review decision is ready to be made | Provide evidence and focused question; **do not self-approve** |
| **Done** | Its own acceptance and all hard prerequisite/review gates are complete | Include evidence and maintain accurate status |
| **Archived** | Paused/retired, not an active delivery gate | Preserve history; revive deliberately |

A ticket that **requires later owner acceptance** may be `Blocked` or `In Progress` with `manual_review: true`; it enters `Manual Review` only when user action is the current remaining step. This prevents tickets from idling during preliminary engineering.

## Completion gate (mandatory)
1. `manual_review: true` means **this ticket cannot become Done** until the user explicitly intervenes and approves the relevant result. Write `manual_review_approved: true` **only** after that approval, together with `review_evidence:` citing the concrete owner decision/review (a link, comment, dated interaction). Silence, prior general scope approval, an agent's own testing or a suggested design are **not** approval.
2. For **every ticket that transitively depends** on a manual-review ticket through `depends_on: ["[[T-NNN]]"]`, do not mark the dependent Done while *any* manual gate in its dependency ancestry remains unapproved. Once the ancestor is approved, descendants may finish automatically if they don't themselves require manual review.
3. No ticket may be Done while a direct **ticket** dependency is not Done. Epic dependencies signal whole-epic milestones and require an explicit applicable ticket edge for enforceable manual review; do not rely on hidden implications. For example, T-045 explicitly names T-039's privacy policy gate.
4. Do not create a manual gate for routine refactoring, documentation sync, benchmark choice, code tests, cosmetic UI adjustments or reversible engineering defaults. Escalate **actual product decisions, safety/privacy authorization, unavailable independent review, and final owner-facing UX acceptance**.
5. Owner-approved **feature inventory** under T-059 resolves the feature-scope choice, but not standalone Drawing's actual hands-on UX signoff. The existing 28 Done entries refer to the **historical pre-split ticket scope**, not a claim the new Drawing/Atlas architecture is implemented.

**Current direct gates (2026-11-02):** T-009 (Search/Find product purpose), T-017 (floor-link usability), T-038 (independent code review), T-039 (player publication/privacy rules), T-043 (native player privacy acceptance), T-048 (live collaboration acceptance), T-056 (standalone + Atlas hands-on integration), T-059 (full approved inventory's actual UX validation). Only T-009, T-038 and T-039 are at `Manual Review` today; the rest require more engineering first.

## Updating tickets
- Keep the ID stable; add `status`, `manual_review`, and a real `depends_on` list for hard prerequisites. Use `related` for informational links **without** an artificial execution block.
- Implement ordinary work without asking the owner. Attach relevant evidence in the ticket. For scope/UX acceptance, show a short concrete demonstration or focused alternative when genuinely needed.
- After each batch, update `docs/Index.md` status/dependency table and run `python3 tools/validate_ticket_store.py`. The script checks status synchronization, dependency existence and review gate closure.
- Before marking Done, ensure dependencies and all direct/transitive manual gates are satisfied. Mark a direct review approved only with owner's explicit recorded response.
- Web-only T-044 is archived at `docs/Archive/Web/T-044.md`; the active ticket path remains as a compatibility pointer, with status Archived.

## Scope snapshot
The explicit [Drawing feature inventory](DRAWING_FEATURE_INVENTORY.md) is **approved**: 47 Essential, 34 Later, 18 Skip. This does not make the complete baseline Done. `T-053` still first proves the standalone minimum witness; `T-059` later gates manual UX acceptance.
