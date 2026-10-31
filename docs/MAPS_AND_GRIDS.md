# Map, Grid, Floor and Battlemap Geometry

> [!important] Geometry reference, not the revised ownership contract
> Earlier independent-document scale/battlemap assumptions below are superseded where they conflict with [[E-002]] and [[E-006]]. The hex overlay covers one shared chunked board with separately authored detail; tile restriction is a selection mask. Battlemats are retired. A projection frame in [[E-007]] controls viewing, not artwork transforms. Keep useful coordinate math, but use [[Index]] for current acceptance.

**Status:** T-002 shared-board contract implemented below; older sections are historical/proposed and must not override it.

## Current shared-board coordinate and ownership contract — T-002 (2026-10-30)

This section takes precedence over legacy map-scale and battlemap-placement language below.
It describes the **implemented shared board**, not the future semantic-zoom
thresholds, preview policy or battlemat migration (T-003–T-005, T-012/T-015).

1. **Board identity and coordinates.** Each `AtlasMapDocument` is one independent,
   unbounded two-dimensional document with coordinates `Vector2` in **board units**.
   A world map has **one** document for all hexes, assigned and empty alike.
   A floor is a vertical content stack; an authored detail level is a subset of
   its layers. No implicit per-hex document exists, and the camera never
   changes boards by scrolling into an unassigned hex. Pointer conversion is
   `document = camera_center + (screen - viewport_center) / camera_zoom`;
   zoom/pan do not alter authored data.
2. **Grid versus content.** The optional board grid maps document points to
   square indices or axial `(q,r)` hexes, using its own origin/rotation/spacing.
   `cell_polygon` lives in the same document coordinates as drawing, and the
   half-open cell/axial rounding rule selects one cell. A highlighted cell is
   **not** an image or edit owner: *Restrict edits to current tile* supplies
   its polygon as an optional `AtlasEditScope` mask to ink, raster, terrain and
   transforms. Without the mask ink and raster can cross any cell border.
3. **Chunk ownership.** Raster content belongs to an `AtlasRasterLayer`, not
   to the hex under it. Within a raster layer, a pixel `(x,y)` has exactly one
   signed chunk owner `(floor(x/256), floor(y/256))` and local pixel
   `(x,y) - 256*owner` in `[0,255]²`, including negative positions. Chunks
   are addressed by that canonical key and stored once per raster layer;
   painting/erasing across seams updates multiple chunks as **one gesture**.
   Pixels are mapped from board space through the inverse raster-layer
   transform and `pixels_per_unit`; changing the overlay grid does not move
   them. Imported partial edge chunks may expand to 256² without moving
   existing pixels. Continuous vector ink is owned exactly once by its ink
   layer as a whole `AtlasStroke` in board coordinates, even if it crosses
   many virtual chunk regions: there is **no per-cell duplication** or
   chunk-split vector object yet. Terrain cells retain their own frozen
   content-grid geometry where applicable (older prototype behavior).
4. **Detail-group authority.** Each authored `AtlasLayer` carries a
   `detail_level` integer, `0..32` (`D0` = overview; absent in older saves
   defaults to `0`). A group is the set of layers on the same floor with the
   same level; **all groups use identical board coordinates**. To author more
   detail, assign/create a layer in `D1`, `D2`, etc., instead of creating a
   hex child document, subdividing an existing stroke or rescaling pixels.
   Layer IDs remain unique within the floor across groups. Each detail layer
   is independently editable and persistable, with normal undo/redo.
5. **Presentation versus editing.** The Layers panel independently exposes
   *Presented artwork detail* (a viewer-local level; not saved) and the
   selected layer's *authored detail* (history-backed saved metadata). Only
   layers in the presented level are drawn. Picking a layer explicitly makes
   its level the presented one; merely changing the presented level **never
   changes** `active_layer_id`. Hidden-by-LOD editing is refused rather than
   silently painting another level. Presentation switches during a gesture
   are refused, so an eventual automatic LOD driver must defer them until
   the gesture completes. T-004 will decide viewport thresholds and hidden
   target indication; T-005 will enable/configure automatic presentation.
   This ticket deliberately does **not** interpret `automatic_navigation`
   (which currently enters linked documents at a zoom limit) as artwork LOD.
6. **Measurement and persistence.** `grid.cell_size` is hex circumradius or
   square side **in board units**; `grid.distance_per_cell` and
   `grid.distance_unit` describe the map's native travel measurement (e.g.
   `3 mi/hex` or `5 ft/square`). Editing those values, grid origin, rotation,
   visibility or spacing never rescales freehand art/chunks. It is **not**
   a camera, battlemap or physical projector scale. Native `.scn` saves
   persist the per-layer `detail_level` through `@export_storage` and the
   layer validation/clone path. Old native/legacy layers are interpreted as
   `D0`; raster clipboard decode accepts both the prior metadata shape and
   the new one, rejecting invalid new levels. Camera/presented level remain
   transient viewer state.

Viewport fit, visual-scale mismatch and automatic authored-LOD transition design are specified in [[ZOOM_AND_ARTWORK_LOD]] (T-004). The existing T-002 presentation controls remain manual until T-005.

**Adjacent-hex reproduction:** On a hex board, use D0 ink from the center of
axial `(-1,0)` through `(2,0)` in one stroke. On a D0 raster layer, make a
stroke from board `(-261,4)` to `(261,4)` with a 3-unit brush. It crosses
hex cells and three signed x chunk seams (`-256`, `0`, `256`) without
leaving gaps/duplicate owners; erasing follows the same path. Zoom toward an
unassigned axial `(41,-38)` cell: no new document is created. Turn on
*Restrict edits* after selecting a cell: new edits clip/reject against its
polygon, while the existing cross-hex stroke is unchanged. Add a D1 ink layer
and draw at the same board coordinates; changing the presented detail shows
D1 instead of D0 without changing the active editing target or the native
measurement. `tests/continuous_canvas_smoke.gd` exercises these cases and a
native-save round-trip; the Layers UI regression exercises the real panel.


## 1. Keep four different concepts separate

| Concept | Meaning | Example |
| --- | --- | --- |
| Map scale | Level of geographic detail of an independent document | World, region, city, encounter |
| Floor | Vertical elevation within a document | Basement, ground, tower floor 3 |
| Layer | Ordered editable content plane within a floor | Terrain, objects, tokens, labels |
| Grid | Optional coordinate/snap/measurement scheme for a document | Pointy hex, flat hex, square, none |

A child map may have a different grid and map scale from its source. Floors are not children in the semantic-zoom sense. There is only **one active editable `MapDocument` per workspace**; the other visible maps are references.

## 2. Coordinate spaces

- **Document coordinates:** continuous 2D `Vector2` in a map-local unit system; all content belongs here.
- **Cell coordinates:** discrete grid-specific values (`Vector2i` for square x/y; axial q/r for hex). Gridless maps use document positions, not invented cells.
- **Placement coordinates:** a BattlemapPlacement's local cell space, mapped into **parent document space** by a transform or symbolic display anchor.
- **Viewport/screen coordinates:** mouse events/pixels transformed through a camera into document coordinates.

No global geographic transform is required for abstract links. Each map's origin, grid rotation, cell dimensions and distance unit are independent.

### Grid contract

Proposed operations:

```text
DocumentToCell(documentPosition) -> GridCell
CellToDocument(cell) -> Vector2 (canonical center)
Snap(documentPosition, snapMode) -> Vector2
GetCellPolygon(cell) -> Polygon2D (in document coordinates)
GetNeighbors(cell) -> cell[]
DistanceInCells(cellA, cellB) -> number
```

Grid configuration should include `shape` (`GRIDLESS`, `SQUARE`, `HEX_POINTY`, `HEX_FLAT`), `cell_size`, `origin`, `rotation`, `distance_per_cell`, `distance_unit`, and visibility/snapping settings. Document units per cell are **not** the same as feet/miles per cell. Rendering at 64 document units for a five-foot square is valid; projector calibration maps display pixels to physical dimensions separately.

### Native units and exploration scale

The DM chooses each map's native unit and distance per cell when creating it. Linked maps retain their own values; no campaign-wide unit harmonization or exact physical conversion is required. For example, a wilderness board can use **3 mi/hex**, another region 1 mi/hex, and an encounter 5 ft/square. These are independently chosen labels, not instructions to subdivide world hexes into battle squares.

The runtime exposes native distance/unit separately from overlay shape, spacing, origin, rotation and visibility. **File → New board** chooses these values for an independent blank document. The inspector changes them afterward through reversible commands; changing distance/unit labels never converts linked maps, and changing overlay geometry never moves freehand ink. Square spacing is cell side length; hex spacing is explicitly labeled as circumradius in board coordinates. The sample world uses 3 mi/cell; existing saves retain their values.

Schema v3 preserves the inherited terrain prototype's original geometry as `terrain_grid`, independently of `grid` (the editing overlay and authoritative native measurement settings). Legacy v1/v2 loads capture their existing grid as this terrain basis. Typed layers will own content-specific geometry later. Prototype cell painting is blocked when the overlay no longer matches that basis; freehand ink remains editable. Very dense overlay grids are temporarily hidden while zoomed out to keep rendering bounded.

Whether a hex distance means a center-to-center travel step, across-flats width, or another campaign convention remains undecided. Do not silently impose that convention. Physical unit conversion, mismatch warnings, rounding policies and content rescaling remain deferred.

### Square grid

Square cell conversion: subtract grid origin, invert grid rotation, divide by cell pitch, then floor to integer x/y. Reverse mapping uses cell center and forward transform. For spatial hit-testing, use half-open boundaries to prevent selecting two adjacent cells simultaneously.

### Hex grid

Store axial coordinates (q, r) and derive cube coordinate s = -q-r. For a hex circumradius R and grid origin at (0, 0), typical unrotated center formulas are:

- Pointy: x = sqrt(3) * R * (q + r/2), y = 3 * R * r/2.
- Flat: x = 3 * R * q/2, y = sqrt(3) * R * (r + q/2).

Inverse conversion uses fractional axial coordinates followed by **cube rounding** to keep q+r+s=0. Handle grid rotation/origin outside the axial math using a transform. Store the chosen orientation and coordinate convention in the document; do not silently swap offset and axial conventions.

Use cell polygons, not bounding boxes, to clip painting along hex edges.

### Grid overlays

Each document has one **primary editing grid** for cell selection, fill, snapping and distances, plus optional secondary visual grids. A secondary grid can be selected as the primary grid explicitly; merely showing it should not change editing behavior. A gridless map permits freehand editing and document-space selection.

## 3. Battlemap creation and placement

### Tool interaction

1. From **any active parent map**, choose Create Battlemap Grid.
2. Drag a rectangular footprint, rotate freely with a handle and optionally angle-snap (proposed shortcut: Shift at 15-degree increments).
3. Quantize row/column count to whole square cells and choose local battle cell pitch (proposed default 64 document units) and game distance (proposed default 5 ft).
4. Choose **spatial** or **symbolic** placement and optionally a parent-reference crop.
5. Create a child `MapDocument` with a local square grid. Enter it to edit: the parent is never painted through the child workspace.

The placement is a parent-map object; resizing/rotating it **from the parent** modifies its metadata, not the child's actual raster or tile contents. In the child, its own art and floor/layer stacks are editable, while the parent reference is read-only.

### Spatial placement

Let P be a parent document position, O the placement origin in parent document units, theta its angle, and k > 0 its uniform parent-document units per battle grid cell. The parent-space point for a local cell coordinate (u, v) is:

```text
P = O + Rotate(theta) * (k * [u, v])
[u, v] = Rotate(-theta) * (P - O) / k
```

Clamp spatial hit tests against 0 <= u < columns and 0 <= v < rows. Render the footprint as a rotated rectangle, using inverse transform for pointer hit testing. If drawn rectangle dimensions are not exact cell multiples, settle on dimensions via user-visible snapping/quantization before creation.

Spatial alignment allows the parent-crop reference to be resampled into the child viewport. The child raster should remain independently editable and unmodified by later changes to the placement transform.

### Symbolic placement

A symbolic placement only locates the encounter on the parent. Its rectangular marker shape/rotation is a hit region and **must not** be interpreted as physical scale or an exact crop. Store the marker transform and the child grid dimensions separately. An optional manually chosen reference crop can visually connect them without pretending geographic accuracy.

This separation matters on a six-mile wilderness hex: a 100-foot battle area should remain discoverable as a usable marker without requiring a physically tiny rectangle.

### Overlap behavior

Multiple placements may overlap. On hover show stacked candidates; clicking selects explicitly. Automatic semantic zoom requires an unambiguous candidate, otherwise it pauses and exposes a chooser. Selection and painting ignore child previews until a user explicitly navigates into that child.

### Temporary encounters (later)

A temporary battle grid can use the same map/placement model but with session-only storage. Persisting it converts its document into the campaign registry without changing geometry or editing tools.

## 4. Read-only parent reference inside a battlemap

The active battlemap renders editable layers **above** an optional translucent parent underlay. The reference renderer stores source map ID, source crop or alignment, opacity, visibility and any selected floor/preview variant. It never becomes a normal paint layer and is excluded from selection, bucket-fill, clipboard and save-as-map raster unless the user explicitly requests flattening.

For spatial placements, derive crop/alignment from placement geometry. For symbolic placements, ask for an independent crop/thumbnail. Parent content may change; define a policy to refresh a **live** reference or freeze a snapshot. The default can be live where available, with a visible stale/missing reference indicator on failure.

Player presentation need not show the reference at all; reference opacity is an editor preference, not an implicit visibility permission.

## 5. Selected-cell edit lock

**Default OFF**: brush, road/line, bucket, selection and other edits may cross to neighboring cells.

**ON**: restrict persistent modifications to the currently selected cell of the primary editing grid. Selecting another cell remains allowed without unlocking; pan, zoom, preview and navigation are unaffected. If there is no selection, fail closed: no editing.

| Tool class | Policy while locked |
| --- | --- |
| Cell painting | Filter target set to selected cell |
| Raster brush/eraser | Intersect stroke mask with selected cell polygon |
| Bucket fill | Limit flood region to selected cell's polygon/cell data |
| Line/road/vector | Clip geometry to selected polygon |
| Cut/copy/paste | Read anywhere if allowed; apply mutations only inside polygon |
| Place/move/resize object | Require full edited footprint inside polygon, else reject (MVP) |
| Create/move spatial battlemap | Require placed footprint inside polygon, else reject |
| Symbolic marker/link placement | Require marker hit region inside polygon (MVP) |

One central `EditScopeController` validates **all** command types. A renderer-only clipping mask is insufficient because it would allow off-cell data mutations. Undo uses the same clipped command payload. Editing lock is local editor/session state, not a persisted ownership rule or a multiplayer ACL.

When switching to a different map or active primary grid, reset selected cell and lock state (or explicitly restore a per-map preference in a later iteration); never reuse stale axial coordinates against a square grid.

## 6. Layers and floors

Suggested layer types: `TileLayer`, `RasterLayer`, `VectorLayer`, `ObjectLayer`, `TokenLayer`, and `AnnotationLayer`. Implement incrementally. Layers have ordered placement, visibility, opacity, locked status, blending policy and metadata. A floor holds its own layer ordering; floor UI supports switching and optionally ghosting neighboring floors read-only. An object can carry elevation/floor ID independent of world map scale.

## 7. Geometry and editing tests

- Axial-to-document and document-to-axial round-trip at centers for both hex orientations, including nonzero origins/rotation.
- Neighbor adjacency and cube-rounding near cell boundaries.
- Square world/cell conversions under nonzero grid origin/rotation.
- Arbitrary rotation (e.g. 37 degrees) with parent-to-placement inverse mapping.
- Spatial placement size quantized to complete cells; no divide-by-zero on scale.
- Symbolic marker dimensions do not affect battlemap game distances.
- Two overlapping rotated placements are selectable individually.
- With lock OFF, road crosses a hex boundary; ON, command data and rendering both stop at the polygon edge.
- Locked paste/object move cannot mutate neighbors.
- Child editing never alters parent source tiles, raster chunks or undo history.
