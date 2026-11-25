# Drawing owner UX review — 2026-11-25

**Source:** owner hands-on feedback in the PR #23 review conversation, 2026-11-25. The owner reports that everything seems good so far, apart from the listed issues, and describes the remaining work as mostly light polishing/new features. The owner asks to commit the queue to PR #23 and will squash onto main for continued work in a new PR. No explicit full T-250/T-059 approval was given; no device, exact tested build or screenshot was supplied for this round.

**Remote checkpoint inspected:** [PR #23](https://github.com/FivePebblesGPT/DrawInAtlas/pull/23), head `da308376c8cd99cc9b66f02140fc606b444a522b`. Latest hosted [fast desktop PR](https://github.com/FivePebblesGPT/DrawInAtlas/actions/runs/45296339589), [fast desktop push](https://github.com/FivePebblesGPT/DrawInAtlas/actions/runs/45296330033), [offline toolkit](https://github.com/FivePebblesGPT/DrawInAtlas/actions/runs/45296339581) and [ticket validation](https://github.com/FivePebblesGPT/DrawInAtlas/actions/runs/45296339756) all passed on that head. This is not post-consolidation hardware/Windows/owner acceptance.

## Owner findings and ordered corrective queue

| Ticket | Priority | Owner finding |
| --- | --- | --- |
| [T-302](Tickets/T-302.md) | P1 | No Bucket tool in the standalone toolbar. |
| [T-303](Tickets/T-303.md) | P1 | No shape tool in standalone Drawing. |
| [T-304](Tickets/T-304.md) | P1 | Rectangle selection and Move selected pixels duplicate toolbar tools in Selection; selection modes need Selection > Selection mode; shortcut labels need distinct color; Snap (8 px) toggle should be removed. |
| [T-305](Tickets/T-305.md) | P1 | No ability to export common image formats with respective export options. |
| [T-306](Tickets/T-306.md) | P1 | Ensure the application uses sRGB color space. |
| [T-307](Tickets/T-307.md) | P1 | Need a Text Options panel with real-time text preview and common text options accessible from the menu bar. |
| [T-308](Tickets/T-308.md) | P1 | Asset Browser lists contents, but Object Editor lacks a background and objects cannot be dragged onto the canvas. |
| [T-309](Tickets/T-309.md) | P1 | Closing a floating window hides its panels; only Show hidden floating panels restores them all. Window > Float selected dock group is unwanted convenience chrome. |
| [T-310](Tickets/T-310.md) | P1 | Binary .drawing file format and space usage optimizations requested. |
| [T-311](Tickets/T-311.md) | P1 | Layers panel uses text-based group markers and whitespace indentation instead of clickable expand/collapse buttons and actual button indentation. |
| [T-312](Tickets/T-312.md) | P2 | Popup panel icons use nearest-neighbor while other states use bilinear filtering; owner notes nearest-neighbor looks stylish. |

## Scope and coordination

- The eleven tickets consolidate all fifteen findings; they are standalone/shared Drawing engineering milestones, not new Atlas delivery gates. Their hard dependencies are completed foundational tickets; existing related umbrellas and historical Done records remain intact.
- T-023–T-027 and T-065/T-064/T-108 have existing Atlas/product acceptance scope. Do not duplicate their raster engines or wait for those Atlas gates to implement the standalone fixes; share the canonical APIs and record integration evidence.
- Prioritize owner-facing corrections alongside T-148–T-152 native consolidation. The suggested queue order is the table order, with P2 icon consistency last; independent ready tickets may be reordered to respect actual dependencies and avoid conflicts. Finish one bounded ticket at a time, update documentation/evidence, and use actual rendered screenshots for visual review (AGENTS.md).
- New scope: JPEG export required, previously Later. Remove only the visible 8px snapping toggle; retain generic candidate infrastructure. Binary .drawing optimization is standalone, not a change to Atlas's multi-file save contract. Nearest-neighbor icons are a proposed reversible default pending visual comparison, not a mandate to change canvas filtering. Format/codec defaults and specific menu command details are engineering proposals, not additional owner mandates.
- [T-250](Tickets/T-250.md) moves back to Blocked on T-302–T-312; return to Manual Review after engineering corrections. [T-059](Tickets/T-059.md) remains the broader unapproved UX gate. No code implementation, app run or new visual evidence is claimed by this documentation checkpoint.

## Handoff after squash

Read AGENTS.md, Index.md and TICKET_WORKFLOW.md, verify actual main/sprint SHA and CI, then implement one Ready ticket at a time. Keep current native Rust ownership and exact RGBA8/history guarantees. Reuse existing native tests and introduce fail-first state/transition/performance tests as needed; personally open actual UI screenshots before declaring visual work complete. Do not mark T-250 Done until explicit owner approval. Native T-148 through T-152, physical performance, Windows packaging and independent review remain open.
