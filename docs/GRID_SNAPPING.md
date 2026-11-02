# Artwork snapping contract (T-016)

## Current generic Drawing and Atlas snapping boundary — T-070 (2026-11-02)

**Authority:** [[DECISIONS_DRAWING_ATLAS_2026-11-01]], [[DRAWING_WORLD_MAPPING]] and [[DRAWING_ATLAS_COMPOSITION]]. The T-016 settings below describe the **legacy Atlas tool/inspector path**; they do not exhaust the independently runnable Drawing package's snapping API.

- **Drawing owns generic snapping** (`addons/drawing/snap.gd`): optional spacing/origin, guides, candidate positions, proximity tolerance and point/displacement functions, with no `AtlasMap`, floor, hex or D-level imports. Atlas supplies candidates and any applicable grid or object constraints. The old Inspector checkbox for specific shape/move tools is not a campaign-wide, mandatory quantization policy.
- **Atlas coordinates:** every `(map_id, floor_id, detail_id)` resolves one internal generic **DrawingDocument** on the same map's signed **1024 ticks/world unit** frame. D-levels have independent explicit rational pixel densities. `AtlasWorldSpace.snap_ticks` supports signed integer spacing/origin; Atlas grid routines supply rotated square/hex centers in world coordinates. Converting a snapped world point to pixels uses **floor division** on signed density, not a new grid origin or camera-rounded screen pixels.
- **Selection masks:** a grid cell/hex is an Atlas **selection or edit mask**, not a DrawingDocument, tile owner, or storage boundary. Restrict-edits uses the selected polygon only for applicable edits; no implicit clipping/rescaling is applied to existing pixels. Gesture preview, commitment and undo must use the same coordinate/mask rule; switching the presented D-level cannot secretly move the captured edit to another document.
- **Independent controls:** **geometric zoom**, authored D-level presentation, derived previews and entrance navigation do **not** trigger a snap or edit. Pen/Eraser are not forcibly snapped by the legacy shape-tool toggle. Explicitly showing empty D1 leaves the grid and entrance hit-testing available but no D0 artwork; snapping does not fill it. Existing floor-link navigation is Atlas-owned and pending [[T-017]] usability review.

### Historical T-016 Inspector snapping behavior

The detailed tool list and tests below remain the legacy Atlas inspector contract. They are a compatibility description, not evidence of a final Drawing-only or Atlas-unified snapping UX.

The continuous board holds artwork at arbitrary **board-space** positions. The
visible grid is an **editing guide**, not an owner of drawing content. Snapping
is an **opt-in, editor-session setting** in the right Inspector under **Grid
Snapping** for Line, Rectangle, Ellipse and artwork selection. It defaults off,
is inactive when the board is gridless, and does not persist or rescale art.
The checkbox stays in the current state when switching tools; pen/eraser,
cell painting/fill, marquee selection, free resize, numeric move/scale/rotate,
and viewport/presentation/navigation operations do not inherit snapping.

## Coordinates and gestures

- Square-grid points snap to **cell centers**, calculated by the grid's
  `document_to_cell`/`cell_to_document` methods with origin, spacing and
  rotation. Hex grids use the nearest **axial cell center** via the same API.
  This is not pixel rounding and is independent of camera zoom.
- With snapping on, Line/Rectangle/Ellipse snap the **start and finish**
  document points before building the shape. Rectangle and ellipse remain
  axis-aligned in board space; the two opposite controls snap, not every
  generated perimeter vertex. A degenerate shape is not committed.
- With snapping off, the pointer's document coordinates are used exactly.
  Pen and eraser always use free document coordinates regardless of checkbox.
- A selected ink object or raster layer **move gesture** snaps to the
  *displacement between* the nearest grid centers at press and current pointer.
  It does not force an existing off-grid anchor onto the grid merely because
  the user clicked it. This displacement is applied in board coordinates,
  preserves a raster asset's pre-existing rotation/shear, and is zero on a
  press/release without movement.
- Resizing, numerical object transforms and selection marquees are not
  quantized: the operator can adjust precision without a misleading snapped
  affordance. Edit masks use the actual geometry of the configured board
  grid; a forbidden move/shape does not bypass the mask. They never reposition
  previously authored content.

The **same draft stroke or transform** is used for the preview and emitted
commit. On pointer release the final position is processed once more through
that same conversion. Undo restores the original subcell coordinates exactly;
no grid edit is itself an implicit artwork transform. Selecting an authored
D1–D32 layer remains an explicit editing choice; automatic LOD does not alter
snapping or gesture targets. Projector framing/calibration is out of scope and
owned by [[T-013]].

## Evidence

`tests/snapping_smoke.gd` checks free and snapped shapes at three zoom levels,
rotated/offset squares and hexes, four quadrants, selection-move preview/commit
consistency, undo, masks, gridless fallback and no implicit repositioning.
`tests/snapping_visual.gd` checks native pointer use of the inspector toggle,
visible draft versus commit, and 960/800-pixel layouts. CI runs both suites.

This is the implemented interaction policy; human ergonomics and the choice of
center-versus-vertex anchors can be revisited with a specific manual review.
