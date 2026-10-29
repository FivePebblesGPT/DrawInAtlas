# Linked maps, placements and references

Execution milestone 6 implements the local-client workflow on Godot 4.8-beta1.
Maps remain independent documents, addressed by stable IDs. A link is an
entrance with a source floor and destination floor/camera; a placement is its
optional source-side footprint. Several entrances can lead to the same map.

## Author and edit entrances

Open **Linked maps…** in the inspector or View menu. The form owns drafts only;
nothing changes until a valid Apply/Create command succeeds.

- Choose an existing destination or create a new independent document. New
  documents have an explicit kind, native distance/unit and coordinate spacing;
  existing destination grids, units and artwork are never recalibrated implicitly.
- Source ownership is the current map/floor. Select the destination floor and
  arrival camera independently; coordinates are in the destination's board units.
- **Marker / portal** uses a source anchor and document-space hit radius.
- **Spatial footprint** uses origin, rotation, columns/rows, parent units per
  footprint cell and child units per footprint cell. It registers the child
  rectangle from `(0, 0)` through `(columns, rows) * child_units_per_cell`.
- **Symbolic footprint** has a discoverable source rectangle but makes no claim
  that its destination artwork is spatially aligned. Link mode is an explicit
  choice, not inferred from whether a board is a world or city.
- Use **Select / enter** to click and drag a marker or footprint on its source.
  Numeric controls resize/rotate footprints, retarget entrances and set arrivals.
  Unchanged fields retain their native precision even when their display rounds.
- **Unlink** removes the entrance and an otherwise unreferenced footprint; it
  keeps the independent destination. Shared footprints survive unlinking one
  entrance; changing shared geometry through one entrance is rejected.

The battlemap tool also supports drag creation. Its live rectangle is quantized
to at least one cell per axis using the configured parent pitch. The inspector
accepts arbitrary rotation; Q/E adjust the draft by 15 degrees. Escape cancels,
and Save commits an in-flight draft before checkpointing. A successful drag
creates the document/entrance/footprint in one transaction and enters it.

Create, edit, move, conversion between marker/footprint, and unlink support
undo/redo with stale-data guards. Creation undo removes a newly created destination
only while it is unchanged and has no other references; it never deletes later
artwork. Redo restores stable IDs without requiring another implicit navigation.
Selected-cell scope checks both original and replacement geometry. Rejection
creates neither partial campaign objects nor history entries.

## Navigate deliberately

- Enter from the form, double-click a location with Select / enter, or use the
  existing Maps/Search views. Overlapping locations open a chooser; no arbitrary
  first entrance is selected.
- Back restores the source map, floor, active layer and exact camera. Traversed
  entrance IDs remain viewer context, allowing the correct parent reference when
  a destination has multiple incoming links.
- Ordinary wheel zoom stays on the board. **Automatic linked-map zoom is off by
  default**. When enabled, three additional logical events at a clamped boundary
  enter a unique candidate or return through viewer history. Arriving at the
  boundary counts zero. There is no guessed parent when history is empty.
- Fractional wheel/vertical pan-gesture events accumulate to a logical step;
  one burst/dispatch contributes at most one step. Reversal, even a partial
  reverse detent, interrupts the previous gesture. Timeout, tool changes, Escape,
  pointer exit/candidate change and disabling automatic navigation reset it.
  Pinch magnification is geometric and never contributes boundary steps.
- Transitions are instantaneous. Arrival camera settings remain independent of
  the placement registration and of last-visited sidebar camera preferences.

## Read-only artwork references

Parent references and child previews contain visible tile, ink and raster layers
in their real order, with opacity and raster affine placement. They are derived
images, never artwork layers or selectable/copyable/paintable content.

- A spatial parent reference samples the source floor through the rotated
  footprint and clips to the registered child rectangle. Show/hide and opacity
  are viewer preferences.
- Select a parent entrance and source floor explicitly. Entry through a link
  supplies that context; otherwise automatic selection requires one unambiguous
  incoming entrance. A symbolic/marker source uses a pinned, **unregistered**
  parent thumbnail rather than a false underlay transform.
- **Freeze parent snapshot** keeps detached rendered pixels and their captured
  registration until unfrozen, including when a source footprint subsequently moves.
  Hiding it preserves the frozen snapshot. Changing its entrance/floor or
  navigating to another view resets the snapshot; missing sources invalidate it.
- Child modes are Off, Markers, Thumbnails and Spatial overlay. Spatial overlay
  registers the child crop to the footprint; symbolic/marker links fall back to
  pinned thumbnails. Coincident thumbnails stack; extra results remain accessible
  through Search.

`AtlasMapCapture` shares the existing private, input-disabled renderer between
sidebar previews and reference crops. Its world has no grids, references, linked
previews or selections, preventing recursive captures. Content signatures and
generation tokens reject old requests after edits, navigation or replacement.
Completed/cancelled viewports stop updating.

Only **eight nearby child previews** plus one parent are requested at a time;
reference crops are at most **512 pixels per axis**, pinned images are 192×128,
and the content-aware LRU retains at most **16 images**. A footer reports omitted
previews. These bound derived output and scheduling, not the size of source
artwork: native campaign loading and source-floor rendering are still eager.

## Persistence and verification

Native `.scn` format **v1** is unchanged. Entrances/placements use the existing
Resource fields. Navigation history, automatic-zoom state, reference sources,
freeze images, preview caches and renderer nodes are not campaign content.

Tests and commands are in the README and CI workflow:

- `links_smoke.gd`: atomic graph edits, detached drafts, stale/shared guards,
  selected-cell scope, independent targets and native roundtrips.
- `linked_maps_ui_smoke.gd`: authored form signals, native pointer/key/gesture
  dispatch, live rotation/cancel/save, precision, undo/redo, floor-aware arrival,
  overlap selection and deterministic boundary timing. Runs headlessly and with
  a real renderer.
- `references_ui_smoke.gd`: real framebuffer checks for rotated all-layer
  references, cropping, editing isolation, opacity, freeze/hide/unfreeze,
  source-floor selection, symbolic fallback, capture/cache bounds and cancellation.

The transition animation, arbitrary authored registration offsets/crops,
OS-specific physical trackpad tuning and sophisticated marker clustering remain
future refinements. Projector privacy and collaboration remain milestones 7–8;
these editor previews are not a player-authorized rendering implementation.
Web export remains required; browser runtime smoke is deferred.
