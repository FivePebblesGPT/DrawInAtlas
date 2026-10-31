# Viewport zoom and authored artwork LOD — T-004 (2026-10-30)

> [!important] Design contract, not the automatic-LOD implementation
> This investigation defines the presentation geometry and behavior to be used
> by [[T-003]], [[T-005]] and subsequent UI work. It does **not** replace
> independent maps with a per-hex hierarchy, turn on automatic LOD, migrate
> Greyhaven/battlemats or change the current navigation limits. The confirmed
> ownership/editing decisions are in [[E-002]], [[E-006]] and
> [[MAPS_AND_GRIDS#Current shared-board coordinate and ownership contract — T-002 (2026-10-30)|T-002's coordinate contract]].

> [!note] Subsequent implementation in T-005
> Automatic artwork LOD, the 24× camera ceiling and inspection control now
> exist. This T-004 investigation preserves measurements of the *earlier* 3×
> implementation for context. The implemented 0.65/0.45 thresholds still need
> real-device/usability tuning; see [[T-005]].

## 1. Reproduce the observed scale problem

The checked-in `examples/northern_marches.tres` sample still demonstrates the
**old linked-document experience**, not the proposed shared-detail flow:

| Sample | Source facts | At camera zoom `1` |
| --- | --- | --- |
| Northern Marches world | Pointy hex grid, 45 board units circumradius | One hex spans about 78 × 90 screen px (unrotated) |
| Greyhaven city | Square grid, 48 board units/cell; occupied 13 × 9 cells | Artwork bounds `(-288, -192)` to `(336, 240)` = **624 × 432** screen px |
| Relative width | Greyhaven artwork width / world hex diameter | `624 / 90 = 6.93` |

The world and Greyhaven have **different board coordinate systems** today;
opening the Greyhaven linked document resets to a stored destination camera.
The number 6.93 demonstrates the *visual discontinuity*, **not** a physically
valid ratio between 3 mi/hex and 10 ft/square. Those native measurement
settings do not transform artwork or define pixels on screen.

On an illustrative 800 × 600 canvas, the world hex's 90 px height occupies
15% of viewport height at zoom 1 and only 45% at the current 3× ceiling.
An unrotated 45-unit-radius pointy hex needs zoom `0.8 × 600 / 90 = 5.33`
to occupy 80% of viewport height. The existing `AtlasMapNavigator` clamps
geometric zoom to `[0.5, 3.0]`, uses `1.2×` wheel steps, and has a separate
opt-in three-blocked-step **linked-document** gate. None of those numeric
limits constitute an artwork-detail threshold. The sample's old child-map
navigation and picture-like previews are separate work under T-012/T-015 and
T-003; this ticket does not silently migrate them.

Reproduce with:

```sh
godot --headless --path . --script res://tests/zoom_lod_contract_smoke.gd
xvfb-run -a godot --display-driver x11 --audio-driver Dummy \
  --rendering-method gl_compatibility --path . \
  --script res://tests/zoom_lod_contract_visual.gd
```

The headless witness reads the actual sample resource, measures Greyhaven's
artwork bounds, tests zoom-wheel round trips with an off-center pointer,
checks a translated/37°-rotated hex's geometric fit, and verifies that both
D0 and D1 share world positions. The native framebuffer witness renders
**overview → fitted local detail → overview** in one continuous board at the
same point, with independent red/green authored strokes, and saves three
images under `user://validation/zoom-lod-*.png`. Its fit demonstration sets
`canvas.camera_zoom` directly **above the currently shipped navigator limit**;
it is a technical proof of the coordinate contract, not evidence that the
ordinary editor UI can already perform the proposed fit or automatic transition.

## 2. Leaflet lessons, translated rather than copied

- **Continuous camera:** Leaflet separates the map's coordinate projection
  from viewport pixel scale. Its `setZoomAround` preserves a stationary
  point under the cursor; `fitBounds` chooses the scale necessary to fit a
  geographic rectangle. Retain those two behaviors on the flat document,
  using the board's linear camera transform, without Mercator or world-wrap.
- **Coverage before absolute levels:** Leaflet's tile-size/zoom-level model
  doubles projected size per integer zoom and supports fractional zoom.
  Our `D0…D32` labels instead represent **independently authored content
  groups**, not zoom exponents, physical-unit conversions or automatic
  resampling levels. Camera zoom remains continuous; changing the displayed
  group must never rebase it.
- **Source resolution vs. display scale:** Leaflet can overzoom raster tile
  sources when a high-resolution source is unavailable, while overlays stay
  registered. Here a raster layer's `pixels_per_unit` is its **source pixel
  density**; at camera zoom `z`, one native raster pixel covers `z / pixels_per_unit`
  screen pixels before optional layer transformations. A high D-number does
  not itself mean higher pixel density. Use source density when judging
  visual crispness, but never stretch/rewrite content as part of an LOD switch.
- **Spatial preview:** Fitting a source's real board-space bounds is useful;
  placing a 96 × 64 image beside an entrance marker is not a spatial preview.
  A board-aligned preview must use the same camera transform and transparent
  source alpha, unlike the previous opaque/offset picture. T-003 owns that
  renderer and detailed empty-content policy.

Sources: [Leaflet Zoom Levels](https://leafletjs.com/examples/zoom-levels/)
and [Leaflet API: `fitBounds`, `getBoundsZoom`, `setZoomAround`,
`zoomSnap`, `TileLayer.maxNativeZoom`](https://leafletjs.com/reference).

## 3. Coordinate and viewport-coverage contract

For a board point `P`, viewport size `V`, camera center `C`, and positive
camera scale `z` (screen pixels per board unit):

```text
screen(P) = (P - C) × z + V/2
document(s) = C + (s - V/2)/z
C_after_pointer_zoom = document(s_before) - (s_before - V/2)/z_after
```

No per-hex image coordinate conversion is permitted. The world overlay grid,
ink, chunks, floors and each separately authored detail group use the **same**
document coordinates. Grid origin/rotation, `cell_size`, and native distances
must not modify stored artwork or camera center. A painted point is unchanged
when viewed at D0, D1, zoomed, rotated-grid, or panned.

The unit of **viewport coverage** is a ratio, not a hardcoded camera value.
For target detail bounds `B` in document coordinates, calculate its rotated
geometry's axis-aligned screen bounds (for a hex, the AABB of
`grid.cell_polygon(cell)`), then:

```text
coverage(B, z, V) = max(B.width × z / V.width, B.height × z / V.height)
fit_zoom(B, V, padding_fraction) = min(
    (1 - padding_fraction) × V.width / B.width,
    (1 - padding_fraction) × V.height / B.height)
```

Handle empty/degenerate/invalid bounds by refusing the fit and retaining the
current camera; never divide by zero. The illustration above uses 20% total
padding, **not** a final UI default. Fit framing must account for the actual
canvas size after sidebars, not the outer application window size. A selection,
author-defined detail footprint, or the hovered grid cell can supply `B`;
not every detail group has a hex footprint. For an empty hex, the **grid cell
polygon itself** provides useful bounds without allocating a document.

LOD selection should use current viewport coverage and availability of
**authored artwork within the visible/target region**, not `map.kind`, link
existence, a fixed number of additional wheel steps, or just a nominal zoom.
When raster content is pixel-limited, density (`pixels_per_unit` and the
layer transform) may inform an inspection warning, but does not confer
selection authority on another layer. `D` numbers provide **order**, not
numeric magnification factors. No automatic rescaling of independently
painted detail groups is allowed.

## 4. Presentation transitions and editing target

1. Camera movement is independent of detail-group presentation. It remains
   anchored on the pointer for wheel/pinch and centered on the target for
   explicit fit. Zooming *in and out* follows the same function; no jumps to
   another board, coordinate origin, floor, or selected edit layer.
2. An automatic viewer (T-005) chooses among authored detail groups **with
   relevant visible content**; it may keep D0 at an otherwise empty local
   location. When no group has content there, the transparent/neutral board
   and grid remain navigable; a missing D1 never blocks zoom or creates
   synthetic artwork. Manual inspection may explicitly show an empty D1.
3. Use separate **entry and exit coverage thresholds** (hysteresis) so
   tiny scroll or pan changes cannot flicker between detail groups. Start
   with an atomic switch rather than blending unrelated authored layers,
   to avoid ambiguous edit ownership or an opaque preview rectangle.
   Evaluate thresholds after camera changes and viewport resizes; a group
   switch does not cause a second camera movement.
4. During a brush stroke, transform, drag or other editing gesture, defer
   *presentation* changes until the gesture ends. **Never retarget the
   gesture or the selected layer.** If automatic presentation hides the
   selected layer after the gesture, visibly indicate e.g.
   `Viewing D1 · Editing Ink (D0, hidden)` near the tools/layers and disable
   editing until the user intentionally reveals/selects the target; offer an
   obvious action to show that authored level. An automatic viewer must not
   quietly invoke `select_layer` or mutate `detail_level` metadata.
5. Manual override disables automatic switching until re-enabled, without
   modifying saved artwork. T-005 will make automatic LOD the default on a
   fresh session; this is **not** `automatic_navigation`, which currently
   means linked-map traversal. Ordinary editable layers, floors and world
   links are separate from authored artwork levels.
6. Preview captures (T-003) must use a known board-space frame with source
   alpha. Inline composites use the same camera projection and should not
   add opaque fill outside painted pixels. An isolated thumbnail may use a
   checkerboard/background for readability, clearly distinct from inline
   canvas artwork. Previews must include the appropriate authored group
   and maintain their position across panning, zooming and rotated grids.

## 5. Implementation handoff and explicitly open tuning

- **T-003:** replace floating unregistered link pictures with correctly
  anchored transparent detail previews; test rotated hexes, adjacent hexes,
  signed raster-chunk seams and empty detail. This ticket now has the frame
  and coordinate policy needed for implementation.
- **T-005:** add the automatic presentation driver, initially default-on,
  explicit manual override and hidden-target indicator. Query authored
  levels by content visibility; change presentation only when idle. Its zoom
  controls must eventually support `fit_zoom` beyond the old arbitrary 3×
  ceiling for local detail, with zoom-cap/safety behavior verified on real
  brush widths, grids and input devices.
- **T-012/T-015:** retire the old linked-battlemap placement/navigation UX
  while preserving independent legacy data and references; never treat
  `D1` as a child document or overload a floor link as a detail transition.

**Numerical policy deliberately still open for T-005 / usability testing:**
entry/exit coverage ratios, whether thresholds apply to hovered cell or an
explicitly defined authored-detail footprint, maximum practical camera range,
zoom velocity on trackpads, preview LOD sampling/resolution ceilings,
possible short crossfade duration after edits are committed, and user-facing
wording/placement of the hidden-target action. None are forced by Leaflet,
`D` indices or the legacy `[0.5,3]` camera interval. A reasonable *trial*
for usability evaluation would be `enter ≈ 0.65`, `exit ≈ 0.45` of the
relevant viewport dimension, **not an accepted production setting**.

**Evidence boundary:** deterministic smoke tests and native screenshots show
that this geometry supports overview → local → overview without relocating
artwork. They do **not** constitute manual UX acceptance or claim that the
automatic presentation/fit controls have been shipped. Those belong to
subsequent tickets, and the final threshold values need user evaluation.
