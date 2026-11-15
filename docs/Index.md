# Ticket Kanban Index

**Current as of 2026-11-15.** This is the **authoritative active navigation**, synchronized with `docs/Tickets/T-*.md` frontmatter. The old chronological 3,119-line engineering journal is preserved at [Index-History-2026-11-15.md](Index-History-2026-11-15.md). Past narrative status or performance recommendations are source-pinned history, not present acceptance. Review [ticket workflow, prerequisites and manual gates](TICKET_WORKFLOW.md) before implementation.

## Current alpha architecture — Rust-owned raster

**Owner decision:** benchmark existing Hokusai **96px hard-round** first (real mouse events/full 512×512 coverage), consolidate NativeHard/Hokusai **inside their existing Rust GDExtension**, move canonical raster tiles, blending, masks, staging, rollback and undo data **out of GDScript**, connect Godot through **batched stroke commands → native-owned dirty tile/byte buffers**, and **delete Legacy** (no compatibility, native-free fallback or migration required in alpha). Godot retains workspace, tools/input reception, layer/metadata UI and GPU texture submission; Rust owns painting. Hokusai is **not required to match Legacy pixel geometry**. Only after retiring Legacy should the new pipeline be reprofiled and its measured dominant bottleneck optimized.

**Do not close the integration/acceptance parents** T-095 (physical 60/96px Brush responsiveness and explicit owner approval), T-068 (native portability and measured full-editor throughput), T-086 (hardware viewport performance), T-088/T-096 (selection/Move acceptance), or T-094 (hosted CI and owner matrix) solely from a passing refactor. Completion of T-104 or the historic 46-step tests never restores GDScript as the target backend.

**Current next ticket:** [T-146 — Hokusai 96px hard-round benchmark](Tickets/T-146.md). The rest of the native migration is sequenced by hard dependencies. See [architecture and ticket audit](NATIVE_RASTER_TICKET_AUDIT_2026-11-15.md) for which previous recommendations were superseded.

## 1. Native raster execution (critical path)

Statuses: T-146 **Ready**; subsequent implementation slices **Blocked** by the previous ticket. No manual-review gate is imposed on engineering refactors; owner physical UX review stays with T-095.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-146 · 96px Hokusai hard-round full-canvas pointer benchmark](Tickets/T-146.md) | Ready | Completed scope; see ticket evidence | [T-097](Tickets/T-097.md), [T-101](Tickets/T-101.md) |
| [T-147 · Unify NativeHard and Hokusai behind one native stroke engine](Tickets/T-147.md) | Blocked | Completed scope; see ticket evidence | [T-146](Tickets/T-146.md) |
| [T-148 · Native-owned tiled raster editing and atomic undo transactions](Tickets/T-148.md) | Blocked | Completed scope; see ticket evidence | [T-147](Tickets/T-147.md) |
| [T-149 · Godot native dirty-tile preview, display and persistence seams](Tickets/T-149.md) | Blocked | Completed scope; see ticket evidence | [T-148](Tickets/T-148.md) |
| [T-150 · Remove Legacy Brush backend and compatibility paths](Tickets/T-150.md) | Blocked | Completed scope; see ticket evidence | [T-149](Tickets/T-149.md) |
| [T-151 · Profile post-consolidation native Brush critical path](Tickets/T-151.md) | Blocked | Completed scope; see ticket evidence | [T-150](Tickets/T-150.md) |
| [T-152 · Optimize the highest measured native Brush bottleneck](Tickets/T-152.md) | Blocked | Completed scope; see ticket evidence | [T-151](Tickets/T-151.md) |

## 2. Active performance, application and CI work

These tracks may progress independently where possible, but their final acceptance must exercise the new native tile/store seam.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-064 · Nested Object Assets with cycle-safe references](Tickets/T-064.md) | In Progress | Completed scope; see ticket evidence | [T-060](Tickets/T-060.md), [T-062](Tickets/T-062.md), [T-108](Tickets/T-108.md) |
| [T-065 · Asset Browser and NULL-placeholder workflow](Tickets/T-065.md) | In Progress | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-063](Tickets/T-063.md), [T-109](Tickets/T-109.md) |
| [T-068 · Evaluate native drawing rasterization and compositing](Tickets/T-068.md) | In Progress | Rust-first direction; T-105 portability and post-consolidation profiling | [T-052](Tickets/T-052.md), [T-104](Tickets/T-104.md), [T-105](Tickets/T-105.md), [T-151](Tickets/T-151.md) |
| [T-083 · Docking layout persistence and owner UX validation](Tickets/T-083.md) | In Progress | Completed scope; see ticket evidence | [T-082](Tickets/T-082.md) |
| [T-085 · Real-time strokes and smooth input](Tickets/T-085.md) | In Progress | Retest batched native input, held preview and cancellation | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md), [T-149](Tickets/T-149.md) |
| [T-086 · Incremental viewport cache and zoom](Tickets/T-086.md) | In Progress | Native dirty-tile display + physical dense zoom acceptance | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md), [T-102](Tickets/T-102.md), [T-103](Tickets/T-103.md), [T-149](Tickets/T-149.md) |
| [T-087 · Visible image edge, transparency and grid](Tickets/T-087.md) | In Progress | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md) |
| [T-088 · Selection masks, clipboard and Move](Tickets/T-088.md) | In Progress | Native selection/mask seam; clipboard and Move remain | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md), [T-149](Tickets/T-149.md) |
| [T-090 · Responsive UI, menu, tabs and brush wheel](Tickets/T-090.md) | In Progress | Completed scope; see ticket evidence | [T-063](Tickets/T-063.md) |
| [T-091 · Single-group floating dock and width recovery](Tickets/T-091.md) | In Progress | Completed scope; see ticket evidence | [T-082](Tickets/T-082.md) |
| [T-092 · Compact Colors and History preferences](Tickets/T-092.md) | In Progress | Completed scope; see ticket evidence | [T-063](Tickets/T-063.md) |
| [T-094 · Restore CI and owner acceptance evidence](Tickets/T-094.md) | In Progress | Required-native hosted CI and independent owner evidence | [T-053](Tickets/T-053.md), [T-055](Tickets/T-055.md), [T-063](Tickets/T-063.md), [T-106](Tickets/T-106.md), [T-107](Tickets/T-107.md), [T-150](Tickets/T-150.md) |
| [T-095 · Eliminate 60px Brush latency](Tickets/T-095.md) | In Progress | After T-152: reference-device 60/96px responsiveness and owner signoff | [T-053](Tickets/T-053.md), [T-098](Tickets/T-098.md), [T-099](Tickets/T-099.md), [T-100](Tickets/T-100.md), [T-152](Tickets/T-152.md) |
| [T-105 · Portable native candidate builds and process-memory evidence](Tickets/T-105.md) | In Progress | Required-native Linux/Windows builds, exports and process/VRAM evidence | [T-052](Tickets/T-052.md), [T-150](Tickets/T-150.md) |
| [T-106 · Restore green required fast-desktop GitHub CI](Tickets/T-106.md) | In Progress | Fresh post-Legacy required-native CI inventory + hosted green | [T-053](Tickets/T-053.md), [T-150](Tickets/T-150.md) |
| [T-107 · Hosted CI replay and 23-finding owner-evidence matrix](Tickets/T-107.md) | In Progress | New hosted replay and 23-finding owner matrix; preserve historic 46 | [T-053](Tickets/T-053.md), [T-150](Tickets/T-150.md) |
| [T-108 · Nested Object Save As link-vs-copy policy and safe export](Tickets/T-108.md) | In Progress | Completed scope; see ticket evidence | [T-060](Tickets/T-060.md), [T-062](Tickets/T-062.md) |

## 3. Owner decisions and independent manual review

Do **not** infer signoff from software tests or prior product scope. T-096 was moved to Blocked until T-149 native-tile revalidation restores review readiness.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-009 · Search and world discovery purpose](Tickets/T-009.md) | Manual Review | Completed scope; see ticket evidence | — |
| [T-038 · Broader code-only review](Tickets/T-038.md) | Manual Review | Completed scope; see ticket evidence | [T-033](Tickets/T-033.md), [T-034](Tickets/T-034.md), [T-035](Tickets/T-035.md), [T-036](Tickets/T-036.md) |
| [T-039 · Player projection and privacy contract](Tickets/T-039.md) | Manual Review | Completed scope; see ticket evidence | [E-003](Epics/E-003.md), [E-004](Epics/E-004.md), [E-006](Epics/E-006.md), [E-SAVE](Epics/E-SAVE.md) |

## 4. Other ready backlog

Other feature/product tickets remain valid; no unrelated approval is assumed.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-018 · Compact layer/object/link hierarchy](Tickets/T-018.md) | Ready | Completed scope; see ticket evidence | [T-006](Tickets/T-006.md), [T-012](Tickets/T-012.md) |
| [T-023 · Bucket](Tickets/T-023.md) | Ready | Completed scope; see ticket evidence | — |
| [T-024 · Line](Tickets/T-024.md) | Ready | Completed scope; see ticket evidence | — |
| [T-025 · Polygon](Tickets/T-025.md) | Ready | Completed scope; see ticket evidence | — |
| [T-026 · Editable open/closed wall paths](Tickets/T-026.md) | Ready | Completed scope; see ticket evidence | — |
| [T-027 · Editable text and small-text culling](Tickets/T-027.md) | Ready | Completed scope; see ticket evidence | — |
| [T-049 · Raster-first authoring defaults and semantic-vector tools](Tickets/T-049.md) | Ready | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md), [T-050](Tickets/T-050.md) |
| [T-056 · Validate isolation, shared assets, LOD and saves](Tickets/T-056.md) | Ready | Completed scope; see ticket evidence | [T-055](Tickets/T-055.md), [T-058](Tickets/T-058.md) |
| [T-059 · Approved Drawing feature scope; implement and validate UX](Tickets/T-059.md) | Ready | Completed scope; see ticket evidence | [T-051](Tickets/T-051.md) |

## 5. Blocked by dependencies or future owner review

T-096 is blocked on T-149 because the pending native source/preview path would invalidate review evidence from the previous implementation.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-013 · Projector framing object](Tickets/T-013.md) | Blocked | Completed scope; see ticket evidence | [T-039](Tickets/T-039.md), [T-022](Tickets/T-022.md) |
| [T-017 · Revisit floor-link authoring/testing](Tickets/T-017.md) | Blocked | Completed scope; see ticket evidence | [T-003](Tickets/T-003.md), [T-004](Tickets/T-004.md), [T-012](Tickets/T-012.md), [T-018](Tickets/T-018.md), [E-TOOLS](Epics/E-TOOLS.md) |
| [T-040 · GM/player views and calibration](Tickets/T-040.md) | Blocked | Completed scope; see ticket evidence | [T-039](Tickets/T-039.md), [T-013](Tickets/T-013.md) |
| [T-041 · Tokens](Tickets/T-041.md) | Blocked | Completed scope; see ticket evidence | [T-039](Tickets/T-039.md) |
| [T-042 · Fog and reveal](Tickets/T-042.md) | Blocked | Completed scope; see ticket evidence | [T-039](Tickets/T-039.md), [T-019](Tickets/T-019.md) |
| [T-043 · Player-output privacy acceptance](Tickets/T-043.md) | Blocked | Completed scope; see ticket evidence | [T-040](Tickets/T-040.md), [T-041](Tickets/T-041.md), [T-042](Tickets/T-042.md) |
| [T-045 · Authoritative sessions and commands](Tickets/T-045.md) | Blocked | Completed scope; see ticket evidence | [E-007](Epics/E-007.md), [T-039](Tickets/T-039.md) |
| [T-046 · Roles and filtered replication](Tickets/T-046.md) | Blocked | Completed scope; see ticket evidence | [T-045](Tickets/T-045.md), [T-039](Tickets/T-039.md) |
| [T-047 · Reconnect and resynchronization](Tickets/T-047.md) | Blocked | Completed scope; see ticket evidence | [T-045](Tickets/T-045.md), [T-046](Tickets/T-046.md) |
| [T-048 · Collaboration acceptance](Tickets/T-048.md) | Blocked | Completed scope; see ticket evidence | [T-046](Tickets/T-046.md), [T-047](Tickets/T-047.md), [T-043](Tickets/T-043.md) |
| [T-096 · Accurate selection contours and responsive Move](Tickets/T-096.md) | Blocked | Native source/Move revalidation before physical owner review | [T-053](Tickets/T-053.md), [T-149](Tickets/T-149.md) |

## 6. Previously completed, retained as historical evidence

**Done is historical delivery, not an endorsement of the old architecture.** T-084, T-097–T-101 and T-104 are valid completed research/implementation records but their optional-native/GDScript-default and Legacy pixel-parity recommendations are superseded. T-102/T-103 and T-124–T-145 retain useful tests and user-facing behavior; T-149/T-150 must adapt relevant tests rather than ship obsolete fallback code.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-001 · Explicit types and corrected skill guidance](Tickets/T-001.md) | Done | Completed scope; see ticket evidence | — |
| [T-002 · Continuous chunked-canvas model](Tickets/T-002.md) | Done | Completed scope; see ticket evidence | — |
| [T-003 · Aligned transparent detail previews](Tickets/T-003.md) | Done | Completed scope; see ticket evidence | [T-002](Tickets/T-002.md), [T-004](Tickets/T-004.md) |
| [T-004 · Viewport-appropriate zoom and artwork LOD](Tickets/T-004.md) | Done | Completed scope; see ticket evidence | [T-002](Tickets/T-002.md) |
| [T-005 · Automatic artwork LOD on by default](Tickets/T-005.md) | Done | Completed scope; see ticket evidence | [T-004](Tickets/T-004.md) |
| [T-006 · Categorized sidebar drawing palette](Tickets/T-006.md) | Done | Completed scope; see ticket evidence | — |
| [T-007 · Compact recognizable icon controls](Tickets/T-007.md) | Done | Completed scope; see ticket evidence | — |
| [T-008 · Toolbar-opened grid settings popup](Tickets/T-008.md) | Done | Completed scope; see ticket evidence | — |
| [T-010 · Smooth pen turns](Tickets/T-010.md) | Done | Completed scope; see ticket evidence | — |
| [T-011 · Mouse-wheel pen width](Tickets/T-011.md) | Done | Completed scope; see ticket evidence | — |
| [T-012 · Replace battlemats with authored local detail](Tickets/T-012.md) | Done | Completed scope; see ticket evidence | [T-002](Tickets/T-002.md), [T-004](Tickets/T-004.md) |
| [T-014 · Retire battlemat creation controls](Tickets/T-014.md) | Done | Completed scope; see ticket evidence | [T-012](Tickets/T-012.md), [T-006](Tickets/T-006.md) |
| [T-015 · Remove obsolete model code (save migration waived)](Tickets/T-015.md) | Done | Completed scope; see ticket evidence | [T-012](Tickets/T-012.md) |
| [T-016 · Coherent detail-editing snapping](Tickets/T-016.md) | Done | Completed scope; see ticket evidence | [T-012](Tickets/T-012.md), [T-019](Tickets/T-019.md) |
| [T-019 · Selection and selection masks](Tickets/T-019.md) | Done | Completed scope; see ticket evidence | [T-002](Tickets/T-002.md) |
| [T-020 · Brush](Tickets/T-020.md) | Done | Completed scope; see ticket evidence | — |
| [T-021 · Eraser](Tickets/T-021.md) | Done | Completed scope; see ticket evidence | — |
| [T-022 · Move](Tickets/T-022.md) | Done | Completed scope; see ticket evidence | [T-019](Tickets/T-019.md), [T-012](Tickets/T-012.md) |
| [T-028 · Ink representation decision](Tickets/T-028.md) | Done | Completed scope; see ticket evidence | — |
| [T-029 · Dictionary conversion audit and cleanup](Tickets/T-029.md) | Done | Completed scope; see ticket evidence | — |
| [T-030 · Raster import/chunk conversion clarity](Tickets/T-030.md) | Done | Completed scope; see ticket evidence | — |
| [T-031 · Tile-layer naming and type authority](Tickets/T-031.md) | Done | Completed scope; see ticket evidence | — |
| [T-032 · Field encodings and invariants](Tickets/T-032.md) | Done | Completed scope; see ticket evidence | — |
| [T-033 · Fill readability](Tickets/T-033.md) | Done | Completed scope; see ticket evidence | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-034 · Raster brush readability](Tickets/T-034.md) | Done | Completed scope; see ticket evidence | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-035 · Selection geometry readability](Tickets/T-035.md) | Done | Completed scope; see ticket evidence | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-036 · Stroke eraser readability](Tickets/T-036.md) | Done | Completed scope; see ticket evidence | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-037 · Commented function-step convention](Tickets/T-037.md) | Done | Completed scope; see ticket evidence | [T-001](Tickets/T-001.md) |
| [T-050 · Retire palette-cell TerrainLayer artwork](Tickets/T-050.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md), [T-031](Tickets/T-031.md) |
| [T-051 · Finalize shared/copy, coordinates and project contracts](Tickets/T-051.md) | Done | Completed scope; see ticket evidence | — |
| [T-052 · Independent Drawing core and generic layer groups](Tickets/T-052.md) | Done | Completed scope; see ticket evidence | [T-051](Tickets/T-051.md) |
| [T-053 · Independent Drawing Godot project in monorepo](Tickets/T-053.md) | Done | Completed scope; see ticket evidence | [T-052](Tickets/T-052.md) |
| [T-054 · Global history navigates to edit origin](Tickets/T-054.md) | Done | Completed scope; see ticket evidence | [T-052](Tickets/T-052.md) |
| [T-055 · Compose Drawing in Atlas, input and previews](Tickets/T-055.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-054](Tickets/T-054.md), [T-060](Tickets/T-060.md), [T-061](Tickets/T-061.md), [T-062](Tickets/T-062.md) |
| [T-057 · Native map rendering/LOD feasibility spike](Tickets/T-057.md) | Done | Completed scope; see ticket evidence | [T-051](Tickets/T-051.md) |
| [T-058 · One text object per editable layer and rasterization](Tickets/T-058.md) | Done | Completed scope; see ticket evidence | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md) |
| [T-060 · Reusable Object Assets and linked instances](Tickets/T-060.md) | Done | Completed scope; see ticket evidence | [T-052](Tickets/T-052.md) |
| [T-061 · Floor layer groups, world coordinates and blank LOD](Tickets/T-061.md) | Done | Completed scope; see ticket evidence | [T-052](Tickets/T-052.md) |
| [T-062 · Object Editor, Save and Save As](Tickets/T-062.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-058](Tickets/T-058.md) |
| [T-063 · Compact Drawing UI and BarDivider overflow](Tickets/T-063.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md) |
| [T-066 · Sparse multi-file floor/detail DrawingDocument persistence](Tickets/T-066.md) | Done | Completed scope; see ticket evidence | [T-051](Tickets/T-051.md), [T-052](Tickets/T-052.md) |
| [T-067 · Benchmark larger chunk geometry and packed storage](Tickets/T-067.md) | Done | Completed scope; see ticket evidence | [T-051](Tickets/T-051.md) |
| [T-069 · Reconcile architecture and typed model docs](Tickets/T-069.md) | Done | Completed scope; see ticket evidence | — |
| [T-070 · Reconcile world, authored detail and navigation docs](Tickets/T-070.md) | Done | Completed scope; see ticket evidence | — |
| [T-071 · Sparse multi-file Drawing storage and recovery docs](Tickets/T-071.md) | Done | Completed scope; see ticket evidence | — |
| [T-072 · Drawing tools and interaction workflows](Tickets/T-072.md) | Done | Completed scope; see ticket evidence | — |
| [T-073 · Approved feature inventory and proposed UX](Tickets/T-073.md) | Done | Completed scope; see ticket evidence | — |
| [T-074 · Object Asset authoring and NULL placeholders](Tickets/T-074.md) | Done | Completed scope; see ticket evidence | — |
| [T-075 · Native projector, privacy and collaboration docs](Tickets/T-075.md) | Done | Completed scope; see ticket evidence | — |
| [T-076 · Kanban index and manual-review closure validation](Tickets/T-076.md) | Done | Completed scope; see ticket evidence | — |
| [T-077 · Performance, code review and validation handoff docs](Tickets/T-077.md) | Done | Completed scope; see ticket evidence | — |
| [T-078 · Panel architecture and state](Tickets/T-078.md) | Done | Completed scope; see ticket evidence | [T-063](Tickets/T-063.md) |
| [T-079 · Collapsible dock and grouped icon rail](Tickets/T-079.md) | Done | Completed scope; see ticket evidence | [T-078](Tickets/T-078.md) |
| [T-080 · Tab and group reordering](Tickets/T-080.md) | Done | Completed scope; see ticket evidence | [T-079](Tickets/T-079.md) |
| [T-081 · Floating tabbed panel containers](Tickets/T-081.md) | Done | Completed scope; see ticket evidence | [T-080](Tickets/T-080.md) |
| [T-082 · Cross-container panel and group docking](Tickets/T-082.md) | Done | Completed scope; see ticket evidence | [T-081](Tickets/T-081.md) |
| [T-084 · Scout PhotoCraft live-paint pipeline](Tickets/T-084.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-052](Tickets/T-052.md) |
| [T-089 · Layer hierarchy, row eye/lock and undo](Tickets/T-089.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md) |
| [T-093 · Discoverable Object source/open workflows](Tickets/T-093.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-062](Tickets/T-062.md) |
| [T-097 · 96px full-canvas Brush correctness and profiling baseline](Tickets/T-097.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-053](Tickets/T-053.md) |
| [T-098 · Incremental detached Brush preview compositing](Tickets/T-098.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-097](Tickets/T-097.md) |
| [T-099 · Frame-safe Brush input draining and held-preview scheduling](Tickets/T-099.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-097](Tickets/T-097.md) |
| [T-100 · Bounded sparse atomic Brush publication and Undo](Tickets/T-100.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-097](Tickets/T-097.md) |
| [T-101 · Optional NativeHard and Hokusai end-to-end throughput](Tickets/T-101.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-097](Tickets/T-097.md) |
| [T-102 · Cold dense viewport first-population performance](Tickets/T-102.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md) |
| [T-103 · Zoom-out, cache-budget and large-layer viewport stress](Tickets/T-103.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md) |
| [T-104 · Operation-specific native raster backend decision](Tickets/T-104.md) | Done | Historical backend research; 2026-11-12 GDScript-default choice superseded | [T-052](Tickets/T-052.md), [T-097](Tickets/T-097.md) |
| [T-109 · Production-scale Asset Browser and filesystem hardening](Tickets/T-109.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-063](Tickets/T-063.md) |
| [T-110 · Byte-exact UTF-8 authorization for portable Object sources](Tickets/T-110.md) | Done | Completed scope; see ticket evidence | [T-109](Tickets/T-109.md) |
| [T-111 · Line release target identity and layer eligibility](Tickets/T-111.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-112 · Atlas Line/Polygon portable Save/Open regression](Tickets/T-112.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md), [T-066](Tickets/T-066.md) |
| [T-113 · Bucket same-ID map/floor release authorization](Tickets/T-113.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-114 · Polygon registered campaign/map/floor authorization](Tickets/T-114.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-115 · Text modal registered campaign/map/floor authorization](Tickets/T-115.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-116 · Atlas Text portable Save/Open regression](Tickets/T-116.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md), [T-066](Tickets/T-066.md) |
| [T-117 · Wall Path registered campaign/map/floor authorization](Tickets/T-117.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-118 · Wall Path portable Save/Open and mask-context regression](Tickets/T-118.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md), [T-066](Tickets/T-066.md), [T-117](Tickets/T-117.md) |
| [T-119 · GM Token registered source authorization](Tickets/T-119.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-120 · Conventional File/Object menus and unified Open](Tickets/T-120.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-093](Tickets/T-093.md) |
| [T-121 · Single-snapshot bounded raster Open](Tickets/T-121.md) | Done | Completed scope; see ticket evidence | [T-120](Tickets/T-120.md) |
| [T-122 · Historical T-107 CI replay source integrity](Tickets/T-122.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md) |
| [T-123 · Predecode bounded PNG/WebP/JPEG geometry](Tickets/T-123.md) | Done | Completed scope; see ticket evidence | [T-121](Tickets/T-121.md) |
| [T-124 · Ordered queued Brush/Eraser during release drain](Tickets/T-124.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-099](Tickets/T-099.md), [T-100](Tickets/T-100.md) |
| [T-125 · Block stale Save/Close of pending Brush edits](Tickets/T-125.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-120](Tickets/T-120.md), [T-124](Tickets/T-124.md) |
| [T-126 · Guard pending Brush edits against document switches](Tickets/T-126.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-124](Tickets/T-124.md), [T-125](Tickets/T-125.md) |
| [T-127 · Guard Undo/Redo against pending Brush revision conflict](Tickets/T-127.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-124](Tickets/T-124.md), [T-125](Tickets/T-125.md), [T-126](Tickets/T-126.md) |
| [T-128 · Guard History list jumps during pending Brush drain](Tickets/T-128.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-127](Tickets/T-127.md) |
| [T-129 · Guard concurrent layer and clipboard edits during Brush drain](Tickets/T-129.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-128](Tickets/T-128.md) |
| [T-130 · Guard selection and frame source context during Brush drain](Tickets/T-130.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-129](Tickets/T-129.md) |
| [T-131 · Preserve Object rename and variant metadata on rejected publication](Tickets/T-131.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-125](Tickets/T-125.md) |
| [T-132 · Bind asynchronous Save As to its originating document](Tickets/T-132.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-120](Tickets/T-120.md), [T-131](Tickets/T-131.md) |
| [T-133 · Guard standalone OS window-close against unsaved state](Tickets/T-133.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-125](Tickets/T-125.md), [T-132](Tickets/T-132.md) |
| [T-134 · Bind authoring dialogs to originating document and layer](Tickets/T-134.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-132](Tickets/T-132.md) |
| [T-135 · Sparse indexed committed viewport traversal](Tickets/T-135.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-102](Tickets/T-102.md), [T-103](Tickets/T-103.md) |
| [T-136 · Indexed detached-preview plus committed sparse traversal](Tickets/T-136.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-135](Tickets/T-135.md) |
| [T-137 · Bounded cold detached-preview population](Tickets/T-137.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-102](Tickets/T-102.md), [T-136](Tickets/T-136.md) |
| [T-138 · Over-budget detached-preview focal retention](Tickets/T-138.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-103](Tickets/T-103.md), [T-136](Tickets/T-136.md) |
| [T-139 · Bounded sparse explicit-mask selection outlines](Tickets/T-139.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md) |
| [T-140 · Focal-first over-budget selection outlines](Tickets/T-140.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-139](Tickets/T-139.md) |
| [T-141 · Occupied sparse-mask overflow outlines](Tickets/T-141.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-139](Tickets/T-139.md), [T-140](Tickets/T-140.md) |
| [T-142 · Preserve overlapping contour tiles after an in-window pan](Tickets/T-142.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-140](Tickets/T-140.md), [T-141](Tickets/T-141.md) |
| [T-143 · Reconcile saturated contour cache for sub-tile clipped pans](Tickets/T-143.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-142](Tickets/T-142.md) |
| [T-144 · Reuse bounded outline candidate plans across deferred frames](Tickets/T-144.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-141](Tickets/T-141.md), [T-143](Tickets/T-143.md) |
| [T-145 · Retain eligible contours across shifted selection tile windows](Tickets/T-145.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-142](Tickets/T-142.md), [T-143](Tickets/T-143.md), [T-144](Tickets/T-144.md) |

## 7. Archived work

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-044 · Web-compatible player fallback — archived](Tickets/T-044.md) | Archived | Completed scope; see ticket evidence | — |


## Maintenance and proof

Ticket state/dependencies live in YAML frontmatter. Add each ticket exactly once to this Index; update it whenever status or dependency changes and run `python3 tools/validate_ticket_store.py`. A manual gate cannot be self-approved; an archived or superseded recommendation is not a completed native implementation. Historical T-107/T-122 46-check replay must remain pinned to its original workflow, while new T-106/T-107 required-native CI must report its real contemporary check inventory.
