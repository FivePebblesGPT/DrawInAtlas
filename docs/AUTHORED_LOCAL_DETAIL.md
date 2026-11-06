# Authored local detail on a continuous board — T-012 (2026-10-30)

## Current authored-detail implementation — T-070 (2026-11-02)

**Authority:** [[DECISIONS_DRAWING_ATLAS_2026-11-01]], [[DRAWING_WORLD_MAPPING]], [[DRAWING_ATLAS_COMPOSITION]] and [[DRAWING_STORAGE_CONTRACT]]. The original T-012 description below explains the **historical native-layer authoring path**; the canonical Drawing core now supplies the artwork instead.

- **Identity:** Atlas projects **Map → Floor group → Detail group → Layers**. One internal generic **DrawingDocument per `(map_id, floor_id, detail_id)`** is lazily materialized; it is not an ordinary tab or a file exposed to Atlas users. A floor is an elevation group, not D1, and **no hex receives its own DrawingDocument**. Independently opened standalone Drawing files are a separate workflow.
- **Same world position, separate pixels:** D0–D32 have one signed map-world reference (**1024 ticks/world unit**) and individually specified rational pixel densities (`num/den`). The default `2^min(D,10)` is configurable before committed art, not a fixed zoom or distance mapping. Signed raster tiles are sparse and have versioned per-document stride; D1 can exist logically with no image allocation. Changing authored density after content is committed needs a deliberate resample.
- **No fallback underlay:** when a viewer explicitly shows **empty D1**, it stays transparent, with **no D0 artwork**, even above painted D0. Atlas still draws the **grid, entrance markers, navigation/hit-testing overlays** and the empty-detail indicator. The legacy automatic authored-LOD selector can choose D0 when higher-detail artwork is absent in the viewed area; this is a **presentation choice**, not D0 painted into D1 or a rule for explicit D1 inspection. Read-only previews do not become editable layers.
- **Editing and history:** a pointer gesture binds the active map/floor/detail, document and layer **at start**; zoom or presentation cannot redirect it. Atlas global history restores the originating context and preserves current zoom; Drawing standalone has a separate history timeline. A selected-cell restrict-edits polygon is an optional mask, never a child map. Atlas Save uses multi-file sparse generations, not the native `.scn` path discussed in the T-012 historical text below.
- **Legacy floor links:** explicitly following an entrance may navigate to another **independent map/floor**; it does not automatically switch D-levels or own a piece of a hex. Floor-link terminology and hands-on usability remain gated by [[T-017]]; no retired battlemat container is reinstated.

### Historical T-012 native-layer workflow and migration inventory

The remainder of this page describes the earlier T-012 editor and native `.scn` behavior, retained for its workflow history and legacy-data notes. It **does not override** the current canonical Drawing implementation or the owner's decision that **no historical user saves require migration**.

> [!important] Current ownership and authoring contract
> This design implements the decision in [[E-002]] and [[E-006]]: local detail is **artwork authored at another level on the same board**, not a battlemap document, nested canvas, grid subdivision, or placement object. It takes precedence over the historical battlemap model in [[MAPS_AND_GRIDS]]. Removal of legacy controls and safe conversion of existing saves are **separate tickets** [[T-014]] and [[T-015]].

## Identity, ownership and positioning

- An `AtlasMapDocument` owns a continuous, unbounded board coordinate system. All hexes, including unpainted ones, inhabit that board. `AtlasFloor` owns an ordered collection of typed `AtlasLayer` instances. Each layer's persisted `detail_level` (`D0` through `D32`) assigns it to an **independently authored artwork group** on its existing floor. A level is an ordinal for presentation, **not** a zoom factor, new document, child board, fixed physical scale, or a coordinate transform.
- `D0` is the overview (also the default for older layers). A named `D1` street layer or `D2` interior layer stores its own strokes, tiles, or signed raster chunks. Two layers can describe the **same** document point with different art without copying or inheriting each other's strokes. Layers in one group retain their ordinary ordering, visibility, lock and opacity. Levels may be empty or sparsely populated; there is no mandatory per-hex detail record and no automatic blank document creation.
- World/grid `origin`, `rotation`, `cell_size`, and native distance labels remain a **separate overlay/measurement concern**. Pan/zoom, including fitted local zoom, changes the camera only. Board points do not move when the user changes a grid or presented detail. Raster chunk ownership remains that layer's signed-chunk coordinate space; terrain layer content retains its own grid basis where applicable.
- `AtlasCampaign.maps` continues to represent genuinely independent documents, not authored detail. A `MapLink` or `AtlasPlacement` from an older save is **not required** to find, view or edit a D1/D2 level. Legacy linked documents remain readable until their conversion is approved and implemented (T-015). Neither a nested document nor a movable footprint can be introduced as a *new* local-detail ownership rule.

## Authoring and selecting local detail (existing workflow)

1. Open the shared board and the appropriate floor. Navigate/pan/zoom to the place to develop; an empty hex is valid.
2. In **Layers**, turn off **Automatic artwork detail (zoom)** temporarily to inspect/author an otherwise empty level. Set **Manual artwork detail** to `D1` (or `D2` and higher for intentionally finer art). Use the existing **New ink / terrain / raster layer** controls. The new layer is assigned that presented level, remains in the **same** board/floor, and becomes the **explicit editing target**. Rename it to identify its content (for example, *Greyhaven streets*). The level itself has no special world-hex ownership.
3. Select a layer in the list to choose the editing target. That explicit user action also shows its level; merely panning/zooming or changing the presented level does **not** silently retarget edits. Automatic presentation can later be re-enabled; if it displays a different level, the edit target is reported as hidden and editing is rejected. **Show editing layer detail** intentionally switches to manual inspection. Never change the shown level during an in-progress gesture.
4. Work at arbitrary board coordinates using the ordinary pen, terrain, raster and selection tools. **Restrict edits to current tile**, if enabled, is an edit mask and not a parent/child relation. Undo/redo and native saves operate on the same owning layers, preserving level metadata and independent artwork.
5. To *present* detail, enable automatic artwork LOD: T-005 chooses an available authored level based on local content and viewport coverage, with hysteresis. D0 remains visible when higher levels have no visible artwork at the viewed location. The manual control is an inspection/authoring override; the current camera does not decide what layer edits go to.

**Boundary:** The current layer UI is functional but not a final hierarchy or snapping design; [[T-018]] covers organization and [[T-016]] covers detail snapping. `D1` and `D2` are intentionally **not** assigned fixed feet-per-hex or zoom thresholds. T-005's existing thresholds still require manual usability tuning. No projectors, tokens or player-facing privacy rules follow from the layer grouping.

## Legacy data: conversion inventory and decision gates (T-015)

The current code still contains `AtlasPlacement` (`scripts/campaign/battlemap_placement.gd`), `AtlasMapLink`, `AtlasLinkedMaps`, the `Tool.BATTLEMAP` drag path, link dialogs, map previews, navigation history, and `AtlasCampaign.maps` / `.links` / `.placements` persistence. The sample still contains a separate Greyhaven document. These are **legacy compatibility**, not new local-detail owners. T-014 removes creation affordances; T-015 inventories consumers and coordinates any conversion.

| Existing information | Preservation/conversion requirement |
| --- | --- |
| Child document and floor/layer IDs, names, metadata, order, visibility, locks and native units | Preserve originals in a versioned backup; enumerate source and destination floor mappings, target `D` levels and ID collisions. Do not overwrite a layer merely because names match. |
| Ink strokes, selection geometry and raster images/chunks | Retain geometry, widths, alpha and editability. A valid **spatial** placement supplies a candidate affine child→parent transform; applying it to points, widths, layer transforms and pixel sampling needs measured tests, especially for rotation, negative chunks and resampling. Raster cannot be treated as a renamed layer. |
| Terrain cells and grid-dependent fills | Preserve source terrain grid, native unit labels, orientation, spacing and cell content. A child square grid cannot simply become parent hex cells; decide whether to retain independently addressable terrain geometry or convert to another representation before migration. |
| Spatial vs symbolic placements | Spatial maps may have a meaningful affine registration but are not necessarily scale-accurate. **Symbolic** placements have no authoritative geographic transform: require a user-chosen registration or leave them independent. Never infer board positions from symbolic marker size. |
| Map links, reference crops, navigation and backlinks | Classify genuinely independent maps separately from retired local-detail navigation. Re-map links/references only with explicit, unambiguous mappings; preserve unresolved references rather than dropping them. Projection frames are NOT substitutes for placements. |
| Existing save, native scene and history | Test against pre-conversion and post-conversion saves in separate slots, preserve a rollback route, validate source/exported-pack interchange, and make conversion atomic/idempotent. Do not silently mutate a loaded save or destroy historic undo metadata. |

**Approval gate:** A deterministic conversion policy for ambiguous scale, symbolic placement, map identity and grid/terrain content must be approved before T-015 changes stored data. Until then load and save legacy content intact; new local detail uses the `detail_level` layer property without a schema bump. T-014 removes obsolete creation UI, not existing saved art. Genuine independent maps can remain independent when their purpose is justified; this ticket does not demand flattening the entire campaign graph.

## Projection stays separate

[[E-007]] and [[T-013]] own the projector framing object, player viewport/crop and calibration. A projection frame can look at any subset of the continuous board and should never own strokes, relocate layers, rescale the board grid, or stand in for a former battlemat transform.

## Reproducible witness

`tests/local_detail_workflow_smoke.gd` opens a real editor, creates D1 and D2 artwork using the **Layers** controls at distinct and shared board coordinates, changes presentation and editing targets separately, exercises editing/undo, verifies that campaign maps/links/placements do not increase, and round-trips the native save. This establishes the usable no-battlemat authoring path and guards the ownership contract; it does not claim that historical battlemap data has already been migrated.
