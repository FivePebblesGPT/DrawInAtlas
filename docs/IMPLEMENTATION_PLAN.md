# Implementation Plan and Decision Log

**Status:** proposal for future development, based on current minimal Godot 4.8 project. No milestone is claimed complete.

## 1. Principle: vertical slices before feature breadth

The risky part is **independent maps with different coordinate systems linked by semantic navigation**. Prove that before expanding into dozens of tools. Build in increments that can be demonstrated with a wilderness hex, a symbolic city, and a 37-degree battlemap.

### Milestone 0 — Editor shell and document skeleton

**Deliverables**
- **Use GDScript only** (mandatory). Godot 4.7.2 standard, Compatibility renderer, web export baseline. Optional GDExtensions require graceful GDScript fallback.
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
| Canonical chunk sizes and formats | Open | Benchmark first |
| Godot scripting language | **Decided** | GDScript mandatory; no C#/.NET dependency |
| Default reference refresh: live vs frozen | Open | UX/performance tradeoff |
| Trackpad normalization/timeouts | Open defaults | Test with actual devices; preserve 3-step semantics |
| Exact storage container (directory/package) | Open | Prefer first testing versioned directory |
| Optional auto-exit on minimum zoom | Accepted design with condition | Only when a navigation-history return target exists |

## 5. Risk register

**Coordinate ambiguity:** mixing parent/document/grid/screen units will cause errors. Mitigation: named types or explicit transformation boundaries and geometry tests.

**Semantic zoom unpredictability:** ambiguous overlapping child links, trackpad high-resolution gestures, unexpected exits. Mitigation: choose explicit targets, three-step gate, logical-step normalization and no auto-return without history.

**Data growth:** full-resolution world canvases and previews can exceed GPU memory. Mitigation: sparse chunks, viewport-driven load, preview cache budgets, measured thresholds.

**Reference coupling:** parent edits might inadvertently alter child art. Mitigation: immutable/read-only reference rendering; edit commands target only active map.

**Permissions leak:** GM-only layers may appear in thumbnails, caches or sync payloads. Mitigation: per-authority projection filtering before rendering/serialization; role-separated cache keys.

**Scope creep:** full online VTT functionality may delay useful local editing. Mitigation: projector-first milestones; networking and automation deferred.

## 6. Suggested next engineering task

Create a small Godot test scene that loads two independently serialized maps (world hex and city) and demonstrates:
- pointer-centered geometric zoom with explicit min/max bounds,
- one abstract link with manual entry,
- navigation-history camera restoration, and
- unit-tested three-step semantic boundary input handling.

Add the rotated battlemap placement immediately afterward. This will test the hardest design assumptions before building the full painting engine.
