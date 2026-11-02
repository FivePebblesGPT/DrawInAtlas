# Drawing / Atlas architecture — owner decisions (2026-11-01)

**Status:** owner architecture approved through Round 9 (2026-11-02), including Option B document ownership, sparse multi-file persistence and larger-than-256 chunk direction. The *target design* is not yet implemented. Remaining detailed engineering contracts are in [[T-051]] and [[T-066]]; Drawing tool inventory remains in [[T-059]]. Epic: [[E-009]].

## Accepted Round 1–2 decisions
1. **Drawing** is a physically independent, reduced-feature PhotoCraft/Paint.NET-style application and library. Its exact feature inventory will follow.
2. Drawing artwork can be authored and saved without any Atlas campaign/map.
3. Atlas organizes logical floors over Drawing layers; there is no Atlas floor type in Drawing.
4. Drawing owns snapping tools and logic; Atlas can supply generic candidate geometry/constraints.
5. Atlas manages world surfaces, authored detail/LOD and navigation; Drawing edits and renders supplied content. Native rendering libraries are candidates, not required solutions.
6. Text creates an **editable text layer on its first successful content commit**, not merely tool selection; users may later rasterize it.
7. Painting clicks paint, even above a map entrance. Double-click the same entrance with Selection/ObjectSelection or Pan to navigate.
8. Atlas retains **one global ordered undo/redo timeline**. Standalone Drawing has its own local undo service without importing Atlas.
9. **No historical user saves exist to migrate**: no migration task, backwards-compatibility requirement or destructive-conversion pipeline; new files still require safe save/load/recovery.
10. Drawing is **physically independent**, not just a well-structured namespace.

## Accepted Round 3 decisions (2026-11-01)
11. **Monorepo:** independent Drawing Godot project and reusable Drawing package in the **same repository** as Atlas. Do not create a separate Git repository by default.
12. **Both reuse modes:** principally **Object Assets** authored in an Object Editor, reused through linked Atlas instances or duplicated as independent source assets. Earlier wording about linked whole-map drawings was ambiguous; see Round 4 clarification.
13. **Floor = layer group:** one logical Atlas floor maps to a Drawing layer group. Atlas owns floor metadata and mapping, not Drawing.
14. **Missing authored LOD = blank:** display **no lower-detail artwork underneath** an empty higher-detail level. Atlas can show an explicit empty-detail status/navigation UI; it must not fabricate lower-level art.
15. **Shared world-coordinate reference:** all authored detail levels of a given map align to one continuous world coordinate system. Detail levels may have different raster pixel densities.
16. **Cross-map undo navigates:** when a global undo affects the edit recorded on map A while viewing map B, navigate to A to reveal the result.
17. **One text element per layer.** Explicit rasterization converts that layer to raster content in one undoable operation.
18. **Web support may be dropped**, but has **not** been definitively dropped. Do not treat Web compatibility as an unconditional blocking gate for the new architecture; make desktop/Web release targets an explicit final choice.

## Proposed decomposition (engineering hypothesis, NOT an additional owner decision)
```text
One repository
  Independent Drawing Godot application
      -> One reusable Drawing library/package
             DrawingDocument + raster/text/object layer groups
             pixels, snapping, painting, selection, rendering,
             document file I/O and local edit transactions
  Atlas Godot application -> same Drawing package/API
             asset registry (linked vs copied)
             map bindings/transforms, floor -> layer-group mapping
             authored-detail selection, world navigation/grid
             entrance hit testing, global undo and project storage
```
**One canonical Drawing implementation** must serve both projects. Godot project boundaries and actual source/import layout remain a T-051 layout spike because the repository currently uses `project.godot` at its root. A nested project directory alone does not prove source isolation.

## Consequences and tensions requiring deliberate design
- **Shared assets vs shared world coordinates:** an asset needs stable local geometry plus a per-map placement transform. All D-levels within a map share the *same Atlas world reference*, but a reused castle might appear at different positions/scales in unrelated maps. Do not mistake shared **coordinate reference** for identical texture pixel density or identical asset placement.
- **Linked vs copied:** linked uses one canonical asset ID; copied creates a new asset ID and independent editable state. Decide whether live links can be external standalone files or only registry-managed project assets (T-060).
- **Layer groups as floors:** the Drawing group tree is generic; Atlas owns which group is a floor. Editing a group should not accidentally change group membership in other maps; define copy-on-write only if genuinely intended.
- **Blank missing LOD:** never silently substitute or ghost lower-detail artwork. Do not allocate a giant empty image; blank is a sparse/empty view until the first authored mark. Atlas must expose current D-level and a reliable way back.
- **Precision:** default Godot `Vector2` values have 32-bit precision, and Godot 2D rendering does not automatically solve huge-world precision via the large-world build option. Test integer/chunk-index world positions and camera-relative drawing coordinates at distant signed locations before settling the API. Reference: https://docs.godotengine.org/en/4.4/classes/class_vector2.html and https://docs.godotengine.org/en/4.4/tutorials/physics/large_world_coordinates.html .
- **Cross-map undo + linked art:** a transaction must retain its *originating map/floor/detail context* as well as the asset ID. On global undo, navigate to the originating map, even if other maps also show the same asset. View navigation itself should not add another history entry.
- **One text element per layer:** large maps may contain thousands of text layers; layer-tree virtualization and selection performance matter.
- **Conditional Web:** native-library adoption may simplify desktop, but must not silently remove a release target. Resolve Web target explicitly before final release gates.

## Outstanding questions (not silently approved)
1. Project/package layout, source packaging and Godot import isolation; standalone/Atlas desktop OS targets.
2. Shared asset lifetime, external-file linkage vs project-owned registry, rename/delete/update conflict and copy behavior.
3. One DrawingDocument per map/detail or a shared document containing floor and detail groups; whether one group can appear on multiple floors.
4. Asset-local to Atlas-world transform, reference scale, chunk/world precision, and pixels-per-world-unit per detail level.
5. Blank high-detail UI and overlay visibility; whether entering a blank level auto-creates content only upon a paint commit.
6. Navigation destination on undo if the original map/floor no longer exists; redo symmetry and camera placement.
7. Text font embedding, fallback, visual rasterization fidelity; entrance double-click thresholds/overlaps.
8. Final Web support decision and provided Drawing feature list.

## Scope control
Historical migration work is waived. Source/test cleanup may still be necessary, and fresh formats must roundtrip. No mandatory third-party native LOD engine before [[T-057]] produces measurements. No presumed UX acceptance.

## Round 4 clarification — Object Editor, exact group hierarchy and contextual undo (2026-11-01)

**Authoritative correction to the earlier ambiguous phrase “linked artwork”:**
- The owner imagines a **reusable object asset**, authored in an **Object Editor**, and placed as an **object instance** on Atlas maps. **This is not primarily a live link to a whole map DrawingDocument.** Keep background/map surface authoring separate from reusable object authoring.
- Editing an object's **source asset** and choosing **Save** updates that source and therefore its linked Atlas instances. **Save As** creates an independent new asset/copy. Whether Save As automatically rebinds the currently selected Atlas instance is **unanswered**.
- Object assets may contain generic Drawing raster/vector/text layers, as agreed in the Object Editor design. A placed instance has its own transform and selection identity. Atlas must not silently mutate the source when moving or rotating an instance. Need to decide whether per-instance edit overrides exist and whether objects can contain other object instances.
- Confirmed exact hierarchy: **Map → Floor group → Detail group → Layers**. These groups are organized by Atlas through generic Drawing layer/group constructs; detail content shares map-world coordinates. Missing high-detail drawing remains blank.
- Global undo should feel **Blender-like** by following the affected selection and restoring/switching into the relevant editing **mode**, in addition to returning to the originating map. Capture stable edit context in commands; on undo/redo, switch to the affected map/floor/detail, select the affected object/layer and restore a valid mode as appropriate. It is **not yet decided** whether ordinary selection-only or mode-only changes themselves push undo steps, whether each past tool is restored, or which camera position is used. Do not claim Blender-specific behavior as an exact contract.
- The uploaded `DrawInAtlas — Draw Module UI Specification` is preserved as the **proposed** [[DRAW_MODULE_UI_SPEC]]. Its one-row top bar, `BarDivider`, tab/rail/dock/status layout and overflow behavior are tracked in [[T-063]] and linked from [[T-059]]. This is not a complete tool feature inventory nor a signed-off final UI.

### Boundary sketch
```text
Drawing reusable engine / standalone editor
  - world/surface drawing: raster + object + text layers and layer groups
  - reusable Object Asset editor: asset-local editable layers + save/save-as
Atlas
  - Map -> Floor group -> Detail group -> Layers
  - object instance registry: (source_asset_id, instance_id, world transform)
  - object placement/selection and link resolution
  - one chronological history + selection/mode/context restoration
```

### New risk cases to test
1. Edit asset source through instance A; linked instances B/C refresh. Undo should restore source once and select/focus the relevant origin without confusing source vs instance selection.
2. Save As copied asset; original stays unchanged. User must know whether instance A still references original or is rebound.
3. Transform instance without touching source; undo selects that instance and restores appropriate instance/placement mode.
4. Undo an edit after changing to another map/mode, with stale or deleted selection. Restoration must be safe and not create another history entry.
5. Asset editor UI and Atlas-embedded Drawing share one canonical engine but can expose different workspace commands; the compact Draw UI spec remains proposed.

See [[T-060]], [[T-062]], [[T-054]], [[T-063]] and the remaining questions in [[T-051]].

## Round 5 owner decisions — context-sensitive Save As and optional selection history (2026-11-02)

**These explicitly supersede the earlier open Round 4 questions.**

1. **Save As after entering Object Editor through an Atlas castle instance:** create a *new independent Object Asset* (e.g. Variant B) **and automatically change that specific originating Atlas instance to reference Variant B**. Other linked instances continue referencing the original source; original source artwork remains unchanged. The Object Editor continues working with the new asset after Save As.
2. **Save As opened independently of an Atlas instance:** create the new asset and switch the active Object Editor document to it; no Atlas instance can be rebound because no instance-edit context exists. This is the consistent default for standalone Drawing/Object Editor.
3. **Selection undo recording is optional, OFF by default.** An explicit user-facing setting enables selection-only operations (e.g. selecting a different layer or object, or clearing a selection) as history steps. With the setting OFF, pure selection changes do not consume undo history, **but content operations always retain/restore their relevant selection and editing mode context** as decided earlier.
4. Turning this setting ON is not permission to record every hover, mouse movement, camera pan or tool-mode switch. Record only committed, meaningful selection transitions with before/after contexts. De-duplicate no-ops, coalesce a single gesture into one history step, avoid replay recursion, and do not mark an artwork document dirty for selection-only steps.
5. Whether mode-only actions and navigation-only actions get their *own* undo steps remains unapproved; the selection setting does not automatically include them. Retaining existing queued selection steps when toggled OFF is a proposed implementation policy, not an additional owner decision.

### Implementation consequences
- Save As from an instance is **one logical Atlas operation**: create a source asset + update the *captured originating instance binding*; use immutable instance/map IDs and revision guards. If it is no longer the same instance, reject unsafe rebinding, keep the draft and offer an explicit recovery path. Source creation / instance rebinding / global history must never silently partially succeed.
- Undo of Save As restores the originating instance's old binding and relevant selection/object-editing mode. **Round 6 decision:** Variant B remains in the asset library as an independent saved asset, even when no instances reference it. Redo reconnects the same Variant B asset ID; it must not create another variant.
- Keep independent Object Editor semantics and Atlas-specific rebind orchestration at a clean boundary: **Drawing/Object Editor** creates/copies an asset, while **Atlas** owns which instance points to which asset.
- Selection-only history applies to both standalone Drawing and embedded Atlas insofar as each exposes the same history configuration/API; in Atlas the operations join its single global chronological history. A selection-only step affects no canonical artwork and must not advance a project-content savepoint.

See [[T-051]], [[T-054]], [[T-060]], [[T-062]], [[T-056]] and [[T-063]].

## Round 6 — Save As undo retention policy (owner approved, 2026-11-02)

- Undo of Save As through an Atlas instance **reverts only that instance's asset binding and relevant editing context**. The newly saved Variant B **remains available in the object asset library**, even when unreferenced. Do **not** delete the new asset on undo or automatically garbage-collect it because its reference count is zero.
- Redo uses the **same stable Variant B asset ID** and rebinds the instance. It must not duplicate B, overwrite the original or silently recreate B under a new ID.
- Variant B remains a normal asset that the user may reuse, edit, save or explicitly delete. Automatic deletion/reclamation of unused variants is **not** currently approved; revisit only if user feedback warrants it.
- This is an intentionally **asymmetric undo**: creation/persistence of the new source survives, while the Atlas instance reference is undoable. If Variant B is stored inside the Atlas project, undo may **not** return the project to its old saved/clean state; the storage/dirty-savepoint model must report this truthfully.
- If B is explicitly deleted after undo, redo cannot fabricate it. Define a safe missing-asset/error path (or disable invalid redo) without corrupting the original binding. All Save As writes and instance updates must still commit safely, without half-created/half-rebound states.
- Tests should verify Save As A→B, undo A→original with B retained, redo A→same B, editor reopening B, save/reopen with unreferenced B, and a deleted-B redo failure. See [[T-060]], [[T-062]], [[T-054]], [[T-056]].

## Round 7 — campaign-side Objects, authoring workflow, desktop, UX (2026-11-02)

**Accepted by owner; this section supersedes earlier “open” questions wherever they overlap.**

1. **Portable project-side Object library.** Store Object Asset files in an `Objects/` folder **next to the campaign file**. Use project-relative references and durable asset IDs so the **campaign file plus adjacent `Objects/` directory** can be copied/moved together. This is not a machine-global library and not silent external live-file synchronization. The current native `.scn` campaign may continue, but its old *single-file-all-content* guarantee no longer covers reusable Object Assets. See [[E-SAVE]] and [[T-060]].
2. **Publish on Save only.** Changes made in the Object Editor are local/staged until the user presses **Save**. Other linked Atlas instances continue showing the last published asset version during editing; Cancel/close-without-save cannot leak draft changes. Save updates the source and refreshes all linked placements. Save As through an originating instance still creates Variant B and rebinds that instance only; undo leaves B saved in `Objects/`.
3. **LOD raster density.** Every authored detail level shares one Atlas world-coordinate reference, but can have **independent explicit pixels-per-world-unit**, with a sensible default progression. Changing density must not silently reposition the art or distort world-space layout. Drawing receives resolved surface/pixel transforms, not Atlas domain types.
4. **Undo viewport.** On global undo/redo, restore affected map/floor/detail/valid selection/editing mode. If any of the affected geometry is already partly visible, **do not move the camera**. Otherwise pan/focus until some of it is visible, **preserving the current zoom**. If map/target no longer exists, recover safely and notify the user rather than selecting a wrong replacement. Previous proposal to change zoom is superseded.
5. **Desktop scope.** Prioritize Windows and Linux. **Drop Web as an active release target for now**; Web-specific ticket [[Archive/Web/T-044]] is archived. The native player/projector privacy work stays active. Desktop GDExtension options need not support WASM at this stage.
6. **Dedicated Object Editor document tab**, using the same Drawing engine. Add an **Asset Browser** as a peer of Colors/Layers/History in the dock with equivalent show/hide, resizing/tab and focus behavior.
7. **Blank detail:** no lower-detail art is displayed, but grid, entrance/hit-testing and map-navigation overlays remain usable.
8. **Nested Object Assets are intended to be supported.** Object sources may instance other Object Assets using local transforms. Reuse map placement/rendering machinery where possible. Prevent direct/indirect reference cycles and runaway traversal; nested selection, preview invalidation, dependency saving and Save As behavior require a dedicated implementation ticket [[T-064]]. The owner did not specify an implementation milestone/depth cap.
9. **Per-instance overrides initially:** transform and visibility only. No arbitrary per-instance pixel/material edit overrides.
10. **Selection-history preference:** application-level, **OFF by default**, not a per-document setting. Content undo still restores selection/editing context.
11. **Invalid history target:** safe fallback with a visible notification; never silently select or edit an unrelated replacement.
12. **Delete Object Asset:** prompt to **remove references/placements**, **retain placements as visible `NULL` placeholders** (GMod-like), or cancel. Preserved placeholders keep stable instance identity, transform and original asset reference for inspection or deliberate repair, without dangerous implicit replacement.
13. **Font handling:** bundle required known fonts **in the portable project save/package** and preserve explicit font references; validate licence/redistribution before bundling. Exact font physical location (embedded Resource or sibling `Fonts/`) is an implementation decision.
14. **Entrance navigation:** use standard **configurable** double-click behavior (time/distance) and stable entrance ID checks. Brush/paint remains higher priority than entrance navigation.
15. **Draw module UI:** [[DRAW_MODULE_UI_SPEC]] is still proposed; the owner has not provided the promised full feature list. The requested Asset Browser dock is an accepted addition.

### Explicitly NOT decided: DrawingDocument granularity
The owner asked for a concrete explanation; **no selection is approved yet**:
- **A. One DrawingDocument per Atlas map**, with generic group tree `Map → Floor group → Detail group → Layers`. A standalone Drawing session can inspect all floor/detail groups in one document. One coherent group tree, but potentially large metadata and a need for lazy sparse content.
- **B. One DrawingDocument per Atlas floor/detail pair**, with Atlas mapping all such documents into the same visible group tree. Better isolation/lazy loading but more complicated cross-floor moves, selection/undo and coordinated saves.
- **C. One DrawingDocument per Atlas floor**, with detail groups inside, as a compromise.
**Engineering preference:** A, contingent on owner preference and a realistic large-map benchmark. This is not an accepted decision and remains an explicit T-051 gate.

### Other open implementation contracts
Project/object file format (relative paths + IDs + atomic multi-file Save), staged source-edit publication versus global undo, nested asset dependency/copy rules, map instance visibility at blank detail, missing-source placeholder recovery, import/export, exact group storage and default pixel density progression. These are not reasons to re-open the accepted owner UX decisions.

## Round 8 — DrawingDocument ownership and sparse multi-file storage (owner approved, 2026-11-02)

**This supersedes the Round 7 A/B/C discussion:** owner chose **Option B** — **exactly one internal DrawingDocument per Atlas `(map_id, floor_id, detail_id)`**. Atlas presents `Map → Floor group → Detail group → Layers`; each detail group's visible layers come from its one DrawingDocument. Floor/detail are Atlas domain group nodes; **DrawingDocument stays a generic Drawing model** with its own layers and subgroups, without knowing maps/floors/authored D-levels.

**Internal ≠ independently opened by the end user.** The owner does **not** expect anyone to open a map's D1/floor-2 DrawingDocument as an ordinary file. Atlas opens and manages it behind the unified Layers hierarchy and active surface. This does **not** repeal the separately approved standalone Drawing program: standalone users can still create/open ordinary Drawing files and edit Object Assets; Atlas's internal floor/detail documents need no dedicated user-visible document tabs.

**Physical persistence:** return to **sparse, multi-file storage** for map artwork in addition to the already approved adjacent `Objects/` folder. Only populated raster chunks and necessary metadata are persisted. An empty D-level is logical metadata/a blank view, not an eager full-size raster allocation. Keep separate document/layer manifest identities and stable signed chunk coordinates. The campaign file is now a **metadata/index authority**, not a container of every raster payload; project portability means copying its **whole sibling project tree**.

Illustrative candidate, not frozen binary schema or filename convention:
```text
CastleCampaign/
  CastleCampaign.scn              # Atlas map/floor/detail registry, navigation, project metadata
  Drawings/
    documents/<document-id>.meta  # Drawing layers, groups, density, chunk references
    chunks/<sha-prefix>/<sha>.webp # sparse, content-addressed payloads
  Objects/<asset-id>.*             # independently saved reusable Object Assets
  Fonts/                          # redistribution-safe bundled font assets
```
The exact manifest encoding, how to bucket payloads, whether chunk blobs are project-wide deduplicated, and whether documents are stored in subdirectories are **engineering design choices under [[T-066]]**. Do not assert a decided `document.meta` syntax or an approved ZIP/single-file pack. A saved Object Asset may itself use the shared Drawing chunk codec, without being confused with map-surface documents.

**Existing implementation evidence, not yet multi-file:** `AtlasRasterChunk.SIZE = 256`, signed `Vector2i coord`, SHA-256 content IDs, RGBA8 canonical chunk images and validated lossless WebP exist in `scripts/artwork/raster_chunk.gd`, `raster_layer.gd`, and `scripts/persistence/webp_store.gd`; current `AtlasCampaignStore` still packs a native one-file `.scn`. Extract/reuse validated logic without claiming on-disk chunk separation already works.

### Consequences accepted or implied
- **No user-facing “Open D1.drawing” workflow.** Atlas resolves map/floor/detail to a stable document ID, activates it lazily and exposes its layers through the unified map hierarchy.
- **No per-hex documents**: a floor/detail DrawingDocument spans continuous shared-world coordinates; hex boundaries and selection masks are overlays/constraints.
- **Different D-levels** have independent authored pixels/density and may render blank, while retaining grid/entrance/navigation overlays.
- **Map floor/detail layer moves** between different DrawingDocuments are cross-document copy/move transactions, not a pointer switch silently stealing the same layer. Atlas global history owns their undo.
- **Multi-file consistency is a real requirement:** saving only touched chunk blobs isn't enough; manifest revisions, campaign references, atomic promotion/recovery and garbage-collection policy are necessary. A mere folder of `.webp` files is not crash-safe project persistence.
- **Empty/untouched areas** must allocate neither giant image memory nor thousands of empty files. Lazy loading/caching and bounded file counts need benchmarks.
- **No old-save migration** is required, but new-format backup/recovery, missing-chunk validation and portable copying are mandatory.

### Still pending engineering decisions
Manifest/chunk file format and indices; content-addressed deduplication vs per-doc files; cross-file staged commits; independent Object Assets sharing chunk blobs vs wholly self-contained files; package export/backup; savepoint and deletion behavior; density-change resampling; exact lazy-load/cache policy. These are plans to be measured and approved, not hidden product questions. See [[T-051]], [[T-061]], [[T-066]].

## Round 9 — chunk geometry: increase size, benchmark before freezing (owner 2026-11-02)

**Owner direction:** existing **256×256 chunks are too small as a hard-coded final choice**, due to high sparse-file overhead and less efficient compression across continuous painted regions. Adopt a **larger target chunk size** for the new Drawing engine/storage, but do not assert a measured winner without measurements.

**Engineering candidate:** benchmark `512`, `1024` (**initial leading hypothesis**) and `2048` square pixels versus current `256` baseline. A full RGBA8 decoded chunk consumes respectively 1, 4, 16 versus 0.25 MiB. A fully painted 4096² pixel region comprises respectively 64, 16, 4 versus 256 chunks. Actual compressed sizes will depend on artwork; improvements cannot be assumed for extremely sparse isolated marks.

**Keep two choices separate:**
1. **Logical edit/chunk size** controls signed tile coordinates, re-encoding on edit, runtime working-set size, undo deltas, cache/culling and memory pressure.
2. **Physical storage packing/sharding** controls number of filesystem files, per-file metadata and transaction cost. Multiple logical chunks might share one pack even if their logical chunk size is modest; this should be benchmarked, not used as an excuse to retain tiny edit tiles indefinitely.

Do not set the new file schema's tile size by `AtlasRasterChunk.SIZE = 256`. Existing 256 chunk code and lossless WebP/hash validation are **testable baselines**, not required production dimensions. Choose a clear **per-document/persisted tile-size invariant** and version it so signed chunk coordinates have unambiguous meaning. A runtime tile-size change requires explicit retiling/manifest conversion, not silently reinterpreting saved coordinates. Since there are no historical user saves, no legacy format migration is needed, but reopening files produced by the new version must always work.

**Required measurements under [[T-067]]:** dense adjacent painting, long strokes crossing boundaries, tiny isolated marks at far-apart coordinates, texture-like/noisy artwork, blank/transparent regions and exact hidden RGB/alpha. Measure encoded bytes, file counts/metadata, encode/decode/flush latency, random tiny edit cost, undo snapshot/delta memory, viewport pan/zoom and cache churn, initial load/reopen and crash-safe generation overhead. Benchmark at least one native Windows/Linux configuration using a deterministic dataset. The selected production size is an engineering result, **not yet approved as exactly 1024**.

This direction does not reverse Option B, portable `Objects/`, sparse `Drawings/`, blank authored detail, Save-only object publication or the split between Drawing and Atlas.
