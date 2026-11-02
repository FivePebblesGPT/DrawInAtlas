# Ticket Kanban Index

**As of 2026-11-02 · `aidev`**. This index includes the historical work and the Draw/Atlas separation documentation tasks introduced since [a9a3bc2](https://github.com/FivePebblesGPT/DrawInAtlas/commit/a9a3bc23d4c03b577d00526e1993f93cac1b121c).

**Canonical state:** ticket frontmatter (`status`, `manual_review`, `depends_on`). See [ticket workflow and closure gates](TICKET_WORKFLOW.md). **Done** on a pre-split ticket means its original acceptance was completed, *not* that the new Drawing application/Atlas integration exists. Web ticket T-044 is archived ([full historical ticket](Archive/Web/T-044.md)).

## Kanban summary

| Ready | Blocked | Manual Review | Done | Archived | Total |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 25 | 15 | 3 | 33 | 1 | 77 |

**Owner review is intentionally narrow.** `Owner` in the table marks a direct completion gate; `Via T-039` indicates inherited privacy-policy approval. Agents can research, implement and test pending dependencies, but **must not mark Done** until the relevant direct and transitive manual approvals are recorded. Approved Drawing feature scope does not mean the final UX is accepted.

**T-051 completed (2026-11-02):** [testable Drawing document/package ADR](ADR_DRAWING_DOCUMENT_CONTRACT.md) and signed-tile consumer. **T-052 completed (2026-11-02):** the [independent generic Drawing core](../addons/drawing/README.md) and an isolated Godot consumer with 150+ runtime checks. T-053 is now Done with an [independently runnable desktop Drawing project](../drawing/README.md), a portable standalone document witness, native framebuffer tests, a third generic consumer and Linux release export. T-058 and T-063 are Ready. T-054 now provides tested Drawing-local and Atlas-global contextual history, one-step cross-document transfers and the Save As binding-history contract; actual Object Asset/editor composition remains with T-060/T-062/T-055. Atlas integration, sparse campaign persistence, polished UI and owner UX gates remain incomplete.

## Tickets

| Ticket | Status | Review gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-001 · Explicit types and corrected skill guidance](Tickets/T-001.md) | Done | — | — |
| [T-002 · Continuous chunked-canvas model](Tickets/T-002.md) | Done | — | — |
| [T-003 · Aligned transparent detail previews](Tickets/T-003.md) | Done | — | [T-002](Tickets/T-002.md), [T-004](Tickets/T-004.md) |
| [T-004 · Viewport-appropriate zoom and artwork LOD](Tickets/T-004.md) | Done | — | [T-002](Tickets/T-002.md) |
| [T-005 · Automatic artwork LOD on by default](Tickets/T-005.md) | Done | — | [T-004](Tickets/T-004.md) |
| [T-006 · Categorized sidebar drawing palette](Tickets/T-006.md) | Done | — | — |
| [T-007 · Compact recognizable icon controls](Tickets/T-007.md) | Done | — | — |
| [T-008 · Toolbar-opened grid settings popup](Tickets/T-008.md) | Done | — | — |
| [T-009 · Search and world discovery purpose](Tickets/T-009.md) | Manual Review | **Owner** | — |
| [T-010 · Smooth pen turns](Tickets/T-010.md) | Done | — | — |
| [T-011 · Mouse-wheel pen width](Tickets/T-011.md) | Done | — | — |
| [T-012 · Replace battlemats with authored local detail](Tickets/T-012.md) | Done | — | [T-002](Tickets/T-002.md), [T-004](Tickets/T-004.md) |
| [T-013 · Projector framing object](Tickets/T-013.md) | Blocked | Via T-039 | [T-039](Tickets/T-039.md), [T-022](Tickets/T-022.md) |
| [T-014 · Retire battlemat creation controls](Tickets/T-014.md) | Done | — | [T-012](Tickets/T-012.md), [T-006](Tickets/T-006.md) |
| [T-015 · Remove obsolete model code (save migration waived)](Tickets/T-015.md) | Ready | — | [T-012](Tickets/T-012.md) |
| [T-016 · Coherent detail-editing snapping](Tickets/T-016.md) | Done | — | [T-012](Tickets/T-012.md), [T-019](Tickets/T-019.md) |
| [T-017 · Revisit floor-link authoring/testing](Tickets/T-017.md) | Blocked | **Owner** | [T-003](Tickets/T-003.md), [T-004](Tickets/T-004.md), [T-012](Tickets/T-012.md), [T-018](Tickets/T-018.md), [E-TOOLS](Epics/E-TOOLS.md) |
| [T-018 · Compact layer/object/link hierarchy](Tickets/T-018.md) | Ready | — | [T-006](Tickets/T-006.md), [T-012](Tickets/T-012.md) |
| [T-019 · Selection and selection masks](Tickets/T-019.md) | Done | — | [T-002](Tickets/T-002.md) |
| [T-020 · Brush](Tickets/T-020.md) | Done | — | — |
| [T-021 · Eraser](Tickets/T-021.md) | Done | — | — |
| [T-022 · Move](Tickets/T-022.md) | Done | — | [T-019](Tickets/T-019.md), [T-012](Tickets/T-012.md) |
| [T-023 · Bucket](Tickets/T-023.md) | Ready | — | — |
| [T-024 · Line](Tickets/T-024.md) | Ready | — | — |
| [T-025 · Polygon](Tickets/T-025.md) | Ready | — | — |
| [T-026 · Editable open/closed wall paths](Tickets/T-026.md) | Ready | — | — |
| [T-027 · Editable text and small-text culling](Tickets/T-027.md) | Ready | — | — |
| [T-028 · Ink representation decision](Tickets/T-028.md) | Done | — | — |
| [T-029 · Dictionary conversion audit and cleanup](Tickets/T-029.md) | Done | — | — |
| [T-030 · Raster import/chunk conversion clarity](Tickets/T-030.md) | Done | — | — |
| [T-031 · Tile-layer naming and type authority](Tickets/T-031.md) | Done | — | — |
| [T-032 · Field encodings and invariants](Tickets/T-032.md) | Done | — | — |
| [T-033 · Fill readability](Tickets/T-033.md) | Done | — | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-034 · Raster brush readability](Tickets/T-034.md) | Done | — | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-035 · Selection geometry readability](Tickets/T-035.md) | Done | — | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-036 · Stroke eraser readability](Tickets/T-036.md) | Done | — | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-037 · Commented function-step convention](Tickets/T-037.md) | Done | — | [T-001](Tickets/T-001.md) |
| [T-038 · Broader code-only review](Tickets/T-038.md) | Manual Review | **Owner** | [T-033](Tickets/T-033.md), [T-034](Tickets/T-034.md), [T-035](Tickets/T-035.md), [T-036](Tickets/T-036.md) |
| [T-039 · Player projection and privacy contract](Tickets/T-039.md) | Manual Review | **Owner** | [E-003](Epics/E-003.md), [E-004](Epics/E-004.md), [E-006](Epics/E-006.md), [E-SAVE](Epics/E-SAVE.md) |
| [T-040 · GM/player views and calibration](Tickets/T-040.md) | Blocked | Via T-039 | [T-039](Tickets/T-039.md), [T-013](Tickets/T-013.md) |
| [T-041 · Tokens](Tickets/T-041.md) | Blocked | Via T-039 | [T-039](Tickets/T-039.md) |
| [T-042 · Fog and reveal](Tickets/T-042.md) | Blocked | Via T-039 | [T-039](Tickets/T-039.md), [T-019](Tickets/T-019.md) |
| [T-043 · Player-output privacy acceptance](Tickets/T-043.md) | Blocked | **Owner** | [T-040](Tickets/T-040.md), [T-041](Tickets/T-041.md), [T-042](Tickets/T-042.md) |
| [T-044 · Web-compatible player fallback — archived](Tickets/T-044.md) | Archived | — | — |
| [T-045 · Authoritative sessions and commands](Tickets/T-045.md) | Blocked | Via T-039 | [E-007](Epics/E-007.md), [T-039](Tickets/T-039.md) |
| [T-046 · Roles and filtered replication](Tickets/T-046.md) | Blocked | Via T-039 | [T-045](Tickets/T-045.md), [T-039](Tickets/T-039.md) |
| [T-047 · Reconnect and resynchronization](Tickets/T-047.md) | Blocked | Via T-039 | [T-045](Tickets/T-045.md), [T-046](Tickets/T-046.md) |
| [T-048 · Collaboration acceptance](Tickets/T-048.md) | Blocked | **Owner** | [T-046](Tickets/T-046.md), [T-047](Tickets/T-047.md), [T-043](Tickets/T-043.md) |
| [T-049 · Raster-first authoring defaults and semantic-vector tools](Tickets/T-049.md) | Ready | — | [T-028](Tickets/T-028.md), [T-050](Tickets/T-050.md) |
| [T-050 · Retire palette-cell TerrainLayer artwork](Tickets/T-050.md) | Done | — | [T-028](Tickets/T-028.md), [T-031](Tickets/T-031.md) |
| [T-051 · Finalize shared/copy, coordinates and project contracts](Tickets/T-051.md) | Done | — | — |
| [T-052 · Independent Drawing core and generic layer groups](Tickets/T-052.md) | Done | — | [T-051](Tickets/T-051.md) |
| [T-053 · Independent Drawing Godot project in monorepo](Tickets/T-053.md) | Done | — | [T-052](Tickets/T-052.md) |
| [T-054 · Global history navigates to edit origin](Tickets/T-054.md) | Done | — | [T-052](Tickets/T-052.md) |
| [T-055 · Compose Drawing in Atlas, input and previews](Tickets/T-055.md) | Blocked | — | [T-053](Tickets/T-053.md), [T-054](Tickets/T-054.md), [T-060](Tickets/T-060.md), [T-061](Tickets/T-061.md), [T-062](Tickets/T-062.md) |
| [T-056 · Validate isolation, shared assets, LOD and saves](Tickets/T-056.md) | Blocked | **Owner** | [T-055](Tickets/T-055.md), [T-058](Tickets/T-058.md) |
| [T-057 · Native map rendering/LOD feasibility spike](Tickets/T-057.md) | Ready | — | [T-051](Tickets/T-051.md) |
| [T-058 · One text object per editable layer and rasterization](Tickets/T-058.md) | Ready | — | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md) |
| [T-059 · Approved Drawing feature scope; implement and validate UX](Tickets/T-059.md) | Ready | **Owner** | [T-051](Tickets/T-051.md) |
| [T-060 · Reusable Object Assets and linked instances](Tickets/T-060.md) | Ready | — | [T-052](Tickets/T-052.md) |
| [T-061 · Floor layer groups, world coordinates and blank LOD](Tickets/T-061.md) | Ready | — | [T-052](Tickets/T-052.md) |
| [T-062 · Object Editor, Save and Save As](Tickets/T-062.md) | Blocked | — | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-058](Tickets/T-058.md) |
| [T-063 · Compact Drawing UI and BarDivider overflow](Tickets/T-063.md) | Ready | — | [T-053](Tickets/T-053.md) |
| [T-064 · Nested Object Assets with cycle-safe references](Tickets/T-064.md) | Blocked | — | [T-060](Tickets/T-060.md), [T-062](Tickets/T-062.md) |
| [T-065 · Asset Browser and NULL-placeholder workflow](Tickets/T-065.md) | Blocked | — | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-063](Tickets/T-063.md) |
| [T-066 · Sparse multi-file floor/detail DrawingDocument persistence](Tickets/T-066.md) | Ready | — | [T-051](Tickets/T-051.md), [T-052](Tickets/T-052.md) |
| [T-067 · Benchmark larger chunk geometry and packed storage](Tickets/T-067.md) | Ready | — | [T-051](Tickets/T-051.md) |
| [T-068 · Evaluate native drawing rasterization and compositing](Tickets/T-068.md) | Ready | — | [T-052](Tickets/T-052.md) |
| [T-069 · Reconcile architecture and typed model docs](Tickets/T-069.md) | Ready | — | — |
| [T-070 · Reconcile world, authored detail and navigation docs](Tickets/T-070.md) | Ready | — | — |
| [T-071 · Sparse multi-file Drawing storage and recovery docs](Tickets/T-071.md) | Ready | — | — |
| [T-072 · Drawing tools and interaction workflows](Tickets/T-072.md) | Ready | — | — |
| [T-073 · Approved feature inventory and proposed UX](Tickets/T-073.md) | Ready | — | — |
| [T-074 · Object Asset authoring and NULL placeholders](Tickets/T-074.md) | Ready | — | — |
| [T-075 · Native projector, privacy and collaboration docs](Tickets/T-075.md) | Ready | — | — |
| [T-076 · Kanban index and manual-review closure validation](Tickets/T-076.md) | Done | — | — |
| [T-077 · Performance, code review and validation handoff docs](Tickets/T-077.md) | Ready | — | — |

## Epics

- [ ] [[E-009|E-009 · Drawing / Atlas capability separation]]
- [ ] [[E-001|E-001 · Drawing, erasing and edit history]]
- [ ] [[E-002|E-002 · Continuous chunked board and grid masks]]
- [ ] [[E-003|E-003 · Typed artwork model and persistence]]
- [ ] [[E-004|E-004 · Usable drawing and manipulation]]
- [ ] [[E-TOOLS|E-TOOLS · Familiar drawing-tool suite]]
- [ ] [[E-005|E-005 · Discovery, previews and floors]]
- [ ] [[E-006|E-006 · Authored artwork LOD and detail editing]]
- [ ] [[E-SAVE|E-SAVE · Portable multi-file save integrity]]
- [ ] [[E-007|E-007 · Local table and projector output]]
- [ ] [[E-008|E-008 · Host-authoritative collaboration]]

## Archived platform work

The Web-only [T-044 historical ticket](Archive/Web/T-044.md) is paused; native projector/privacy and collaboration tickets remain active. See [Web archive policy](Archive/Web/README.md).

## Maintaining this index

When adding or changing a ticket, keep its frontmatter and this table synchronized. Run `python3 tools/validate_ticket_store.py`; CI also checks these on repository updates. Never turn a manually gated ticket or any dependent ticket Done without the owner's explicit recorded approval.
