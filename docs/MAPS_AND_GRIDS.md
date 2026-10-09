# Map, Grid, Floor and Battlemap Geometry

**Status:** proposed design and coordinate conventions.

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
