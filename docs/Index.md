# Ticket Kanban Index

**As of 2026-11-03 · `aidev`**. This index includes the historical work and the Draw/Atlas separation documentation tasks introduced since [a9a3bc2](https://github.com/FivePebblesGPT/DrawInAtlas/commit/a9a3bc23d4c03b577d00526e1993f93cac1b121c).

**Canonical state:** ticket frontmatter (`status`, `manual_review`, `depends_on`). See [ticket workflow and closure gates](TICKET_WORKFLOW.md). The [fast desktop GDScript CI policy](CI_TESTING.md) runs required Drawing/core checks before reporting failures; legacy Atlas/native/Web suites are retained but non-gating; this changes verification only, not ticket status or manual approvals. **Done** on a pre-split ticket means its original acceptance was completed, *not* that the new Drawing application/Atlas integration exists. Web ticket T-044 is archived ([full historical ticket](Archive/Web/T-044.md)).

## Kanban summary

| Ready | In Progress | Blocked | Manual Review | Done | Archived | Total |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 14 | 1 | 10 | 3 | 54 | 1 | 83 |

**T-078–T-083 agreed docking sequence (2026-11-03):** The right icon rail remains panel-level, with separators only between tabbed groups. **T-078 Done** (82 model assertions) supplies unique stable-ID ownership, **T-079 Done** (40 native assertions) supplies collapsible groups, icon rail and in-app flyouts, and **T-080 Done** (60 model and 68 native assertions) adds transactional tab/group drag, visible insertion/merge hints, exact Esc/focus-loss/invalid-drop rollback, scrollable tab strips and keyboard arrangement controls. **T-081 Done** (64 model, 55 native checks) supplies real Control-based movable/resizable floating hosts, tab/group reordering, ownership transfer, hide/Window recovery and viewport clamping. **T-082 Done** (62 model and 56 native checks) delivers cross-container panel/group pointer docking, ordered redock, empty-canvas detach, robust invalid/focus-loss cancellations and accessible transfer commands. **T-083 Ready** for persistence engineering, with final **T-083 owner UX review mandatory**. Docking persistence is not yet implemented, and earlier T-059/T-056 UX gates remain open. See [docking specification](DRAWING_DOCKING_SPEC.md), [T-080](Tickets/T-080.md) and [T-083](Tickets/T-083.md).

**T-063 owner-requested refinement (historical T-063 baseline, 2026-11-02):** The shared Drawing and Object Editor tool rail now uses six packaged, keyboard-focusable SVG icons with tooltips and pressed-state feedback. **Window → Show document tabs** hides/reopens the `Untitled` document strip for the current session; hidden tabs retain Ctrl/Cmd+Tab navigation, unsaved-close protection and document/dirty status. Colors/Layers/History now **stack vertically in one scrollable right dock**, with a bounded layer tree and focus-to-History support. The native witness has **75 required checks**; clean staging includes icons. T-063 remains Done while T-059 and T-056 **manual UX gates stay open**. See [T-063](Tickets/T-063.md) and [standalone usage](../drawing/README.md).

**T-063 completed (2026-11-02):** the [shared compact Drawing top bar](../addons/drawing/editor_top_bar.gd) now provides the eight-menu File/Edit/View/Image/Layers/Select/Window/Help layout with `BarDivider`, real tool-specific options and keyboard-reachable More/chevron overflow. The resizable right dock has Colors/Layers/History tabs, show/hide controls and a History preference, while `Ctrl+Shift+S` invokes actual Save As and Ctrl+Y is the primary redo. A 52-check native X11/Mesa witness tests 1280/560 widths, 1.5x scaling, scrolling, close safety and menu actions; the independent editor and Object Editor remain intact. **T-065 Asset Browser is now Ready; T-059 owner UX approval remains outstanding.** The BarDivider layout remains an owner-*proposed* design even though this engineering prototype is implemented; no manual gate was closed.

**T-074 completed (2026-11-02):** [reusable Object Asset authoring, Save As and NULL lifecycle](OBJECT_ASSETS_WORKFLOW.md) now traces distinct internal `Drawings/` documents, portable `Objects/` sources and per-map instance IDs through private edits, source publication, bound Variant B Save As, asymmetric undo/redo, deletion and missing-source repair. [The historical raster/Objects workflow](RASTER_OBJECTS_WORKFLOW.md) is explicitly labeled pre-split. Ten code-aware documentation checks run in CI, while actual Object Asset, Object Editor, composition and campaign storage suites were rerun. **T-064 nested cycles, T-065 Asset Browser/repair and T-059 owner UX review remain unfinished**; no manual gate was closed.

**T-073 completed (2026-11-02):** the [owner-approved 99-row Drawing feature inventory](DRAWING_FEATURE_INVENTORY.md) retains **47 Essential / 34 Later / 18 Skip** without claiming all are shipped. Its minimum T-053 witness is distinguished from the still-open complete Essential baseline, and pointer/keyboard acceptance flows cite real tests versus pending T-059 owner UX. The [one-row BarDivider workspace specification](DRAW_MODULE_UI_SPEC.md) remains an owner-*proposed* layout, now implemented as a tested T-063 prototype; the Object Editor tab is implemented (T-062), while Asset Browser dock parity awaits T-065. Ten source-aware documentation checks and an eight-check **native keyboard/pointer** witness run in CI. The formerly mismapped `Ctrl+Shift+S` Save As shortcut and missing menu shortcut labels have since been corrected by T-063; no owner gate was closed.

**T-072 completed (2026-11-02):** the nine [tool and interaction workflow pages](BRUSH_WORKFLOW.md) now lead with current Drawing-owned gesture/pixel/edit behavior, Atlas-owned map/selection/global history, the available six-tool standalone palette, and an explicit historical section for legacy Atlas-era prototypes. Bucket/Line/Polygon/Wall Path/T-027 UX remain **Ready** despite their generic engine primitives or old smoke fixtures. Editable text's single-element/explicit rasterization and portable licensed fonts are documented; T-068's native edit-region interface is not mistaken for a selected library. Ten documentation checks run in CI. Some old `.scn` and candidate tool smoke tests still fail and are recorded in [T-072](Tickets/T-072.md); this ticket changes **documentation and tests only**.

**T-071 completed (2026-11-02):** the [storage format and recovery contract](DRAWING_STORAGE_CONTRACT.md), [dictionary adapter audit](DICTIONARY_CONVERSION_AUDIT.md), and [raster importer analysis](RASTER_CHUNK_IMPORT.md) distinguish today's T-066 root-pointer/immutable-generation/individual `.zst` save from historical one-file native WebP/.scn code. Explicit, executable acceptance examples cover relocating a whole project, partial-copy/missing-file rejection, corrupted and interrupted generations, stale writers, precise signed tiles, and blank detail. [[T-067]]'s future 512-stride and segmented-pack recommendations remain **not deployed**. Eight documentation checks and actual missing-chunk failure coverage were added to CI; no save-format change or owner approval is implied.

**T-070 completed (2026-11-02):** the seven [world/detail/navigation pages](MAPS_AND_GRIDS.md) now lead with the actual Option B signed-world/explicit-density contract and distinguish blank D-levels, Atlas-only overlays, grid edit masks, derived previews and independent-map floor links from retired per-hex/battlemat designs. [Search/world discovery](SEARCH_AND_WORLD_DISCOVERY.md) separates today's safe legacy Search actions from the unapproved **Find/Locate** proposal; **T-009 Manual Review and T-017 owner usability gates remain open**. Eight automated documentation checks were added to CI; targeted runtime regressions passed except the older `snapping_smoke.gd` nil-layer case, recorded in [T-070](Tickets/T-070.md). No runtime or save-format change is implied.

**T-069 completed (2026-11-02):** the seven [architecture/data-model pages](ARCHITECTURE.md) now distinguish the shipped two-project Drawing/Atlas core, Option B internal `(map,floor,detail)` registry, Object Assets/instances and T-066 sparse generations from historical `.scn`/battlemat proposals. A six-check documentation suite and CI step guard source links, approved authority, and unresolved review/performance boundaries. No migration or UX approval was implied.

**T-077 completed (2026-11-02):** [platform-specific test matrix and reviewer handoff](DRAWING_TEST_PLAN.md) distinguishes the historical milestone-6 review and latency probes from T-067 storage, T-068 CPU raster/submitted-frame and still-ready T-057 GPU/LOD work. The generator `tools/build_t038_review_bundle.py` makes a deterministic code-only reviewer ZIP. T-038/T-056 still require **actual independent/owner review**, not automatically generated evidence; no manual-review gate was closed.

**T-068 in progress (2026-11-02):** [controlled CPU and native-frame benchmark](DRAWING_CPU_RASTER_BENCHMARK.md) includes 691 Godot checks on the latest rerun, **10 native kernel unit tests**, 128 Godot/C++ alpha-parity vectors, a 24-pixel signed-world fixture, 15 sparse-delta-only C++ timings, and **68 native X11 software-frame checks** across 21 input events. A new ABI-versioned delta-only prototype avoids copying unchanged edit buffers but remains unintegrated. Tile-run compositing provides ~16× lower CPU-frame time on the bounded fixture. Actual Blend2D/Skia performance, GDExtension integration, physical presentation and Windows hardware remain unverified; **no native dependency was adopted and T-068 is not Done**.

**T-067 completed (2026-11-02):** [controlled 256/512/1024/2048 Zstd tile and 3-layout packing benchmark](DRAWING_CHUNK_GEOMETRY_BENCHMARK.md) includes 48 physical-layout cases, 386 Godot native checks, software framebuffer upload measurements and explicit retiling/versioning rules. **512** is recommended for a *future new-document default* and immutable shared **segmented** packs are the physical-layout target; **neither change has been deployed**. Existing versioned 256-stride documents and T-066’s verified individual-blob writer remain authoritative until separate adoption and atomic-recovery tests. No manual review gate was bypassed.

**T-066 completed (2026-11-02):** [portable generation-based sparse campaign saving](DRAWING_STORAGE_CONTRACT.md) now durably publishes the single Atlas root pointer after verifying checked manifests, compressed tiles, Object Assets, licensed fonts and recovery roots. The real editor saves and reopens Drawing documents. T-067 subsequently completed its geometry/packing benchmark; adoption of its recommended default/pack layout is separate work. T-056/T-059 owner UX gates remain open.

**T-055 completed (2026-11-02):** [Atlas canvas composition, linked Objects, input precedence and read-only previews](DRAWING_ATLAS_COMPOSITION.md) use the one canonical Drawing package with 89 headless and 13 native display checks. T-056 is now **Ready** for separate engineering/release/owner verification; its manual-review approval remains pending. T-066 subsequently implemented the versioned multi-file save.

**T-061 completed (2026-11-02):** [Atlas floor/detail Drawing registry and shared signed world mapping](DRAWING_WORLD_MAPPING.md) now prove per-detail stable IDs, sparse blank D-levels, explicit pixel densities, 64-bit viewport anchors, Object Instance detail scoping and grid/entrance overlay continuity. **T-055 subsequently completed** main-canvas composition. T-061 does not claim that composition or T-066’s multi-file atomic save.

**T-062 completed (2026-11-02):** the [shared dedicated Object Editor](Tickets/T-062.md) now uses the same Drawing workspace in standalone Drawing and an Atlas-hosted window, with private drafts, Save/Save As, captured instance identity, signed local frames, unsaved-close protection and real UI/registry/history tests. **T-064 is now Ready**; Atlas main-canvas launch/composition (T-055) subsequently completed; the Asset Browser (T-065) and owner UX review remain outstanding.

**Owner review is intentionally narrow.** `Owner` in the table marks a direct completion gate; `Via T-039` indicates inherited privacy-policy approval. Agents can research, implement and test pending dependencies, but **must not mark Done** until the relevant direct and transitive manual approvals are recorded. Approved Drawing feature scope does not mean the final UX is accepted.

**T-051 completed (2026-11-02):** [testable Drawing document/package ADR](ADR_DRAWING_DOCUMENT_CONTRACT.md) and signed-tile consumer. **T-052 completed (2026-11-02):** the [independent generic Drawing core](../addons/drawing/README.md) and an isolated Godot consumer with 150+ runtime checks. T-053 is now Done with an [independently runnable desktop Drawing project](../drawing/README.md), a portable standalone document witness, native framebuffer tests, a third generic consumer and Linux release export. T-058 is now Done with editable one-element text layers, a shared glyph compositor and explicit undoable rasterization; T-062 is now Done with a shared Object Editor and Atlas-bound Save As workflow. T-063 is now Done; T-065 is Ready. T-054 now provides tested Drawing-local and Atlas-global contextual history, one-step cross-document transfers and the Save As binding-history contract; subsequent Object Editor and Atlas canvas composition were delivered in T-062/T-055. T-060 now provides [versioned Object Assets, linked per-map instances, private Save drafts and atomic component-level Save As rebinding](../scripts/objects/README.md), including NULL placeholders and real portable-file tests. Its per-campaign object index is now captured by T-066’s portable generation snapshots. T-055 completes live Atlas composition; T-066 completes the versioned sparse campaign save. Polished UI, performance benchmarks and owner UX gates remain incomplete.

**T-075 completed (2026-11-02):** the nine [player projection and collaboration pages](PLAYER_PROJECTION_CONTRACT.md) now distinguish the currently implemented DrawingDocument/Asset/T-066 source graph from isolated legacy raster-sanitization, X11 player-window and in-process session proofs. Windows/Linux native desktop is the active target; [Web T-044](Archive/Web/T-044.md) is **Archived** without deleting its historic tests. Ten source-backed documentation tests and 375 headless plus 124 native visual checks passed. **T-039 Manual Review, T-043/T-048 blocked independent owner gates remain unchanged**; no real player-authorized projector or authenticated multiplayer is claimed.

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
| [T-055 · Compose Drawing in Atlas, input and previews](Tickets/T-055.md) | Done | — | [T-053](Tickets/T-053.md), [T-054](Tickets/T-054.md), [T-060](Tickets/T-060.md), [T-061](Tickets/T-061.md), [T-062](Tickets/T-062.md) |
| [T-056 · Validate isolation, shared assets, LOD and saves](Tickets/T-056.md) | Ready | **Owner** | [T-055](Tickets/T-055.md), [T-058](Tickets/T-058.md) |
| [T-057 · Native map rendering/LOD feasibility spike](Tickets/T-057.md) | Ready | — | [T-051](Tickets/T-051.md) |
| [T-058 · One text object per editable layer and rasterization](Tickets/T-058.md) | Done | — | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md) |
| [T-059 · Approved Drawing feature scope; implement and validate UX](Tickets/T-059.md) | Ready | **Owner** | [T-051](Tickets/T-051.md) |
| [T-060 · Reusable Object Assets and linked instances](Tickets/T-060.md) | Done | — | [T-052](Tickets/T-052.md) |
| [T-061 · Floor layer groups, world coordinates and blank LOD](Tickets/T-061.md) | Done | — | [T-052](Tickets/T-052.md) |
| [T-062 · Object Editor, Save and Save As](Tickets/T-062.md) | Done | — | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-058](Tickets/T-058.md) |
| [T-063 · Compact Drawing UI and BarDivider overflow](Tickets/T-063.md) | Done | — | [T-053](Tickets/T-053.md) |
| [T-064 · Nested Object Assets with cycle-safe references](Tickets/T-064.md) | Ready | — | [T-060](Tickets/T-060.md), [T-062](Tickets/T-062.md) |
| [T-065 · Asset Browser and NULL-placeholder workflow](Tickets/T-065.md) | Ready | — | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-063](Tickets/T-063.md) |
| [T-066 · Sparse multi-file floor/detail DrawingDocument persistence](Tickets/T-066.md) | Done | — | [T-051](Tickets/T-051.md), [T-052](Tickets/T-052.md) |
| [T-067 · Benchmark larger chunk geometry and packed storage](Tickets/T-067.md) | Done | — | [T-051](Tickets/T-051.md) |
| [T-068 · Evaluate native drawing rasterization and compositing](Tickets/T-068.md) | In Progress | — | [T-052](Tickets/T-052.md) |
| [T-069 · Reconcile architecture and typed model docs](Tickets/T-069.md) | Done | — | — |
| [T-070 · Reconcile world, authored detail and navigation docs](Tickets/T-070.md) | Done | — | — |
| [T-071 · Sparse multi-file Drawing storage and recovery docs](Tickets/T-071.md) | Done | — | — |
| [T-072 · Drawing tools and interaction workflows](Tickets/T-072.md) | Done | — | — |
| [T-073 · Approved feature inventory and proposed UX](Tickets/T-073.md) | Done | — | — |
| [T-074 · Object Asset authoring and NULL placeholders](Tickets/T-074.md) | Done | — | — |
| [T-075 · Native projector, privacy and collaboration docs](Tickets/T-075.md) | Done | — | — |
| [T-076 · Kanban index and manual-review closure validation](Tickets/T-076.md) | Done | — | — |
| [T-077 · Performance, code review and validation handoff docs](Tickets/T-077.md) | Done | — | — |
| [T-078 · Panel architecture and state](Tickets/T-078.md) | Done | — | [T-063](Tickets/T-063.md) |
| [T-079 · Collapsible dock and grouped icon rail](Tickets/T-079.md) | Done | — | [T-078](Tickets/T-078.md) |
| [T-080 · Tab and group reordering](Tickets/T-080.md) | Done | — | [T-079](Tickets/T-079.md) |
| [T-081 · Floating tabbed panel containers](Tickets/T-081.md) | Done | — | [T-080](Tickets/T-080.md) |
| [T-082 · Cross-container panel and group docking](Tickets/T-082.md) | Done | — | [T-081](Tickets/T-081.md) |
| [T-083 · Docking layout persistence and owner UX validation](Tickets/T-083.md) | Ready | **Owner** | [T-082](Tickets/T-082.md) |

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
