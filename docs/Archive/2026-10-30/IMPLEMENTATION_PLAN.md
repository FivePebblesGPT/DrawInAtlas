---
type: archive
archived: 2026-10-30
original_path: docs/IMPLEMENTATION_PLAN.md
---

> [!info] Superseded roadmap
> This preserves both the execution milestones and older 0–5 feature groupings. Active epic notes use execution milestones 1–8 plus the native-save gate. Review-driven acceptance and confirmed changes are tracked through [[Index]], [[E-002]] and [[E-006]].

<!-- Original report; relative links rebased only. -->
# Implementation Plan and Decision Log

**Status:** execution milestones **1–6** and the intervening native-save migration are verified locally on Godot **4.8-beta1**. Milestones **7–8** remain open. Native-save PR #4 was squash-merged as `eb877d7` after green checks. The older feature groupings below are historical reference. See [implementation notes](IMPLEMENTATION_NOTES.md) for verified behavior.

## 1. Principle: vertical slices before feature breadth

The main product is a **drawing board with optional grids and map links**, not a recursively subdivided battlemap. The imported scaffold proves several geometry/navigation ideas, but must not dictate feature priority. Normal zoom stays on the current map; automatic navigation is explicitly opt-in.

### Current execution milestones (1–8)

The integration checkpoint is complete. The following execution sequence supersedes the priority of the original feature groupings below. Work and verify **one milestone per turn**, with native checks and a local commit after verification. Keep Web export compatible; browser smoke is deferred per user direction.

| Milestone | Scope | State |
| --- | --- | --- |
| 1 | Document-space pen/eraser, stroke-level undo/redo, dirty/save checkpoints | Implemented and tested; see implementation notes |
| 2 | Blank board creation; independent grid overlay geometry and per-map native units | Implemented and tested; see implementation notes |
| 3 | Typed layers and reliable/versioned/recoverable persistence; lossless WebP raster artwork | Implemented and verified for the local client; Web smoke deferred |
| 4 | Drawing/selection tools, fill, move/resize, clipboard and assets | Implemented and verified for the local client |
| 5 | Floors and map organization/overview/previews | Implemented and verified for the local client |
| Native-save gate | One embedded `.scn`, adjacent backup, Resource isolation, codec benchmarks | Verified and squash-merged as `eb877d7`; see [native saves](NATIVE_SAVE_IMPLEMENTATION.md) and [AD-10](NATIVE_SAVE_BENCHMARKS.md) |
| 6 | Linked-map workflow refinement, placement/reference/navigation controls | Implemented and verified locally; [usage and limits](../../LINKED_MAPS.md) |
| 7 | Local table/projector mode, tokens/fog, privacy-filtered player output and Web fallback | Pending |
| 8 | Host-authoritative collaboration, permissions and reconnect | Pending |

The following milestone storage descriptions are historical. Native format v1 now replaces JSON user checkpoints; legacy JSON saves are left untouched, with no importer. In-memory compatibility dictionaries and clipboard formats remain separate APIs.

Milestone 1 stores editable vector strokes as JSON in schema v2 and reads legacy v1 campaigns. Raster artwork/chunks are not introduced in this slice; their canonical format remains lossless WebP. Undo covers pen/eraser gestures, while legacy terrain/metadata actions are marked dirty but await command conversion.

Milestone 2 upgrades the runtime schema to v3, reads v1/v2, and adds reversible board creation/grid configuration. Legacy terrain geometry is preserved separately from the editable overlay. Native/Web and live-session checks validate creation; framebuffer tests verify zero terrain pixels moved after an overlay change. Typed layers and recoverable saves are still milestone 3.

Milestone 3 upgrades to v4 ordered tile/ink/raster layers, native image import and lossless WebP chunks. Saves stage/verify assets and metadata, preserve a validated backup, and atomically replace the head. Native failure-injection, migration, layer/input and framebuffer checks are the gate. The user has prioritized the local client and postponed Web smoke tests; browser import/recovery validation is explicitly deferred rather than claimed complete.

Milestone 4 adds vector outlines, raster pen/eraser and bounded bucket fill, active-layer selection with proportional transforms, typed self-contained clipboard data and central selected-cell scope. Schema v5 persists raster placement transforms and reads v1–v4. Native service/input/framebuffer and live-session checks are the gate; no new Web smoke was run.

Milestone 5 adds reversible floor/metadata controls, per-workspace floor/camera/layer memory, bounded graph overview with four filters, tags and read-only cached previews. Visible-area results track pan/zoom/resize through coalesced notifications. Its historical runtime checkpoint v6 recorded tags and source/target floor identity. The subsequent native-save migration uses one binary `.scn` with embedded Resources: the workspace continues through the store API, and viewer state/private preview scenes remain outside canonical saved content. See [data model](../../DATA_MODEL.md) for the current storage contract.

Milestone 6 adds reversible, source-owned entrances/footprints and optional new
documents, a scene-owned linked-map form, native drag/numeric editing, explicit
overlap selection and floor/camera-aware navigation. All-layer parent references
and child previews share bounded, cancellable artwork captures; symbolic links
stay unregistered. Viewer choices/frozen images are not saved. Native v1 remains
unchanged; source/exported-pack interoperability, headless and framebuffer checks
are the gate. Browser smoke remains deferred.

### Original feature groupings (reference)

### Milestone 0 — Editor shell and document skeleton

**Deliverables**
- **Use GDScript only** (mandatory). Godot 4.8-beta1 standard, Compatibility renderer, Web export baseline. Optional GDExtensions require graceful GDScript fallback.
- Godot editor shell, central canvas with `Camera2D`, pan, geometric zoom, zoom limits, input routing.
- Domain types: `Campaign`, `MapDocument`, `GridDefinition`, `MapLink`, `MapFloor`, `MapLayer`.
- Open/save a minimal versioned campaign, stable IDs and schema roundtrip tests.
- Commands for create map, change grid, create layer, and undo/redo.

**Exit criteria:** create two blank maps, save/close/reopen, preserve grids and map IDs, and navigate between them by explicit link.

### Milestone 1 — Multi-grid editing

**Deliverables**
- Square and pointy/flat hex `GridAdapter` conversions and renderer.
- Sparse tile layer + terrain palette; brush, eraser, bucket, selection.
- One active editing grid with optional passive overlays; road/line strokes can cross cells.
- Optional selected-cell edit lock implemented through a central mutation validation/clipping service.
- Basic layer visibility, opacity, locking, and ordering.

**Exit criteria:** round-trip tests on rotated hex grids; roads cross hex borders unlocked and clip precisely when locked; save/load retains cell paint.

### Milestone 2 — Battlemaps and semantic navigation

**Deliverables**
- Drag-to-create rectangular battle grid on **any** map, arbitrary angle, quantized rows/columns.
- Spatial versus symbolic placement behavior, editable on parent only.
- Independent battlemap document/workspace; optional translucent parent underlay.
- Manual navigation via link and history.
- Zoom-boundary gate: exactly three additional logical wheel steps at both directions, correct resets and candidate selection.
- Crossfade or instant transition; preserve incoming and outgoing camera/floor states.

**Exit criteria:** create a rotated battlemap on a city and a symbolic battlemap in a world hex; no edit in either child changes its parent; three-step navigation behavior passes edge cases.

### Milestone 3 — Discoverability, richer art, floors

**Deliverables**
- Linked-map marker, thumbnail and spatial overlay preview modes.
- Map Overview with visible-area, selected-cell and whole-map filtering, name/tag search, safe recursive traversal.
- Cached previews with invalidation; nonaligned children shown as thumbnails, not falsely transformed overlays.
- Lossless WebP raster painting chunks, clipboard (cut/copy/paste), selection/move/resize, placed objects/assets.
- Multiple vertical floors per document and floor controls, including tower use case.
- Autosave/checkpoint, recoverable edits, import/export baseline.

**Exit criteria:** find an encounter through overview without entering any candidate hex; stacked previews work; two tower floors can have independent layers; reference cannot be selected or painted.

### Milestone 4 — Local table/play mode

**Deliverables**
- Separate GM and player viewport/window, fullscreen player output, camera and grid calibration.
- Fog-of-war authoring/reveal, role-filtered rendering, token placement/movement.
- Freeze/follow GM camera options and safe player previews.
- Temporary encounter battlemap workflow and persistent conversion (if priorities permit).

**Exit criteria:** a hidden GM note, secret room, hidden token and private preview never appear on projector; grid calibration works with common display/projector scaling.

### Milestone 5 — Hosted collaboration

**Deliverables**
- Host-authoritative session, client join, stable identities and access roles.
- Command serialization/replay and revision/conflict handling; allowed token movement.
- Role- and layer-based permission validation on host.
- Server-side filtering of map art, fog, thumbnails and metadata before client delivery.
- Network disconnection/rejoin behavior and authorized cache invalidation.

**Exit criteria:** unauthorized clients cannot request or infer secret content through preview endpoints; rejected edits do not mutate host state; two clients maintain consistent allowed views.

## 2. High-value automated tests

| Area | Scenario | Must hold |
| --- | --- | --- |
| Documents | Save/load map graph with two entrances to same child | References retain IDs and independent arrival positions |
| Geometry | Axial cube-roundtrip, pointy/flat orientation and rotation | Cell conversions remain stable |
| Placement | Battlemap 37-degree transform and inverse | Correct hit tests and no shearing |
| Placement | Symbolic battlemap anchored in six-mile hex | Discovery region visible but no claim of real-world scale |
| Editing | Selected-cell lock for brush/fill/paste/vector/object | No off-cell mutation data |
| Layers | Switch floors, toggle layer visibility | No accidental scale or map change |
| Zoom | Event arrives at zoom limit | Counter remains 0/3 |
| Zoom | Three additional inward detents | Navigate once, never earlier |
| Zoom | Three outward detents at minimum | Return to exact source camera |
| Zoom | Reverse, pause, pointer change, overlapping links | Counter resets or requests explicit selection |
| Previews | Multi-hex overview/search | Finds descendant maps without loading all artwork |
| References | Edit child while underlay visible | Parent content remains bitwise unchanged |
| Persistence | Crash during dirty-chunk save | Previous consistent project or recoverable journal exists |
| Privacy | Secret layer/thumbnail/fog on projected or remote view | Unauthorized output contains no secret data |

### Manual acceptance demo

1. Create six-mile-hex `Northern Marches`.
2. Paint a road crossing several hexes; enable cell lock to prevent the road leaving one hex.
3. Create `Greyhaven` as an abstract city linked from a hex.
4. On Greyhaven drag a 20×15 battle grid and rotate to 37 degrees.
5. Enter the battlemap after exactly three post-limit wheel steps; show the parent terrain at 35% opacity.
6. Paint encounter details in the battlemap and verify Greyhaven remains unchanged.
7. Zoom outward through the three-step buffer and confirm camera restoration.
8. Create several other battlemap links across adjacent hexes and locate them from Overview without entering each hex.

## 3. Quality gates

- Domain serialization unit tests run without the Godot graphical editor where practical.
- Geometry and edit-scope algorithms have deterministic pure tests.
- No tool directly mutates another map through a reference renderer.
- Every state-changing action has undo/redo and dirty-state policy before broad editor adoption.
- Schema migrations and missing-asset/link placeholders are tested.
- Performance checks measure memory and frame time on a deliberately large sparse hexcrawl.
- Projector privacy and (later) network authorization are tested against **serialized outputs**, not just screenshots.

## 4. Decision log

| Decision | Status | Rationale |
| --- | --- | --- |
| Map documents form a graph connected by links | Accepted design | Reuse locations, multiple entrances |
| Abstract child maps permitted | Accepted design | City/dungeon not necessarily to scale |
| Hybrid semantic zoom | Accepted design | Manual explicit entry plus optional auto |
| Three additional logical wheel steps at boundary | Accepted design | Avoid accidental scale changes |
| Rotated drag-created battlemap on any map | Accepted design | Fast encounter preparation |
| Battlemap has separate editable workspace | Accepted design | No cross-level painting ambiguity |
| Parent displayed in child as read-only translucent reference | Accepted design | Maintain geographic context |
| Child markers/thumbnails/overlays and map overview | Accepted design | Discover maps across hexes |
| Optional selected-cell edit lock (off by default) | Accepted design | Constrain changes while permitting roads across neighbors |
| Floors distinct from layers and map scale | Accepted design | Tower/basement support |
| Host-authoritative networking | Proposed | Simpler permission enforcement and session consistency |
| Canonical raster chunks | Decided / measured | 256-pixel RGBA8 chunks, embedded lossless WebP; see AD-10 benchmark report |
| Godot scripting language | **Decided** | GDScript mandatory; no C#/.NET dependency |
| Native campaign persistence | **Implemented / locally verified** | One binary `.scn` with embedded Resources, adjacent `.bak.scn`, store boundary retained |
| Drawing-board-first editing | Accepted clarification | Continuous artwork; grids are overlays, links are optional |
| Native measurement units per map | Accepted clarification | DM chooses distance/unit; no automatic conversion or harmonization |
| Automatic map navigation default | Off / opt-in | Ordinary drawing-board zoom must not change maps |
| Default reference refresh: live vs frozen | Implemented | Live by default, with explicit viewer-only freeze; see linked-map capture budgets |
| Trackpad normalization/timeouts | Open defaults | Test with actual devices; preserve 3-step semantics |
| Exact storage container | Decided | One binary `.scn` primary; no standalone Resource or artwork sidecars |
| Optional auto-exit on minimum zoom | Accepted design with condition | Only when a navigation-history return target exists |

## 5. Risk register

**Coordinate ambiguity:** mixing parent/document/grid/screen units will cause errors. Mitigation: named types or explicit transformation boundaries and geometry tests.

**Semantic zoom unpredictability:** ambiguous overlapping child links, trackpad high-resolution gestures, unexpected exits. Mitigation: choose explicit targets, three-step gate, logical-step normalization and no auto-return without history.

**Data growth:** full-resolution world canvases and previews can exceed GPU memory. Mitigation: sparse chunks, viewport-driven load, preview cache budgets, measured thresholds.

**Reference coupling:** parent edits might inadvertently alter child art. Mitigation: immutable/read-only reference rendering; edit commands target only active map.

**Permissions leak:** GM-only layers may appear in thumbnails, caches or sync payloads. Mitigation: per-authority projection filtering before rendering/serialization; role-separated cache keys.

**Scope creep:** full online VTT functionality may delay useful local editing. Mitigation: projector-first milestones; networking and automation deferred.

## 6. Suggested next engineering task

Proceed with execution milestone 7: local table/projector mode, tokens/fog and
privacy-filtered player output with a Web-compatible fallback. Preserve one
editable document per workspace, independent native units, source-owned commands
and native saves. Editor reference captures are not player-safe projections:
permission filtering must be designed and tested at the output boundary. Keep
browser smoke deferred unless the user changes that priority.
