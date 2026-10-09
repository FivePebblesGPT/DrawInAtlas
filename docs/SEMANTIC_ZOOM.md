# Semantic Zoom, Navigation and Cross-Map Previews

**Status:** proposed behavior. Semantic zoom is navigation between documents, not automatically resampling the same drawing.

## 1. Geometric versus semantic zoom

- **Geometric zoom:** adjust the current document's camera zoom between map-specific `min_zoom` and `max_zoom`. Never changes editable map.
- **Semantic zoom:** follow a `MapLink` to a different document. Each document has its own grid, layers, floors and camera defaults.
- **Manual navigation:** click/double-click a location, search result, breadcrumb, or explicit Enter/Back action. It bypasses the wheel buffer.
- **Automatic navigation:** at a geometric zoom boundary, three **additional, consecutive logical wheel steps** in the same direction are required before entering/exiting.

Inward transitions prefer the child link beneath the zoom focus/pointer. Outward transitions prefer the immediate navigation-history source, restoring the saved camera. Only one map document is editable at a time.

## 2. Exact three-step zoom buffer

The wheel step that moves the camera *to* the boundary does not count. Only steps occurring **while already clamped at the boundary** are buffered.

| Input/action | Current state | Result |
| --- | --- | --- |
| Wheel inward below maximum | Geometric zoom | Zoom, reset buffer |
| Wheel inward reaching maximum | Camera still below maximum before event | Clamp, reset buffer; **0/3** |
| 1st extra inward logical step | At max, valid child candidate | Hold at max, **1/3** |
| 2nd extra inward step | Same candidate/direction | Hold at max, **2/3** |
| 3rd extra inward step | Same candidate/direction | Begin child transition; clear buffer |
| Wheel outward above minimum | Geometric zoom | Zoom, reset buffer |
| 1st / 2nd extra outward step | At min, valid return target | Hold, **1/3** / **2/3** |
| 3rd extra outward step | At min, same return target | Return to previous map/camera; clear |
| No eligible link/return target | At boundary | Clamp, no navigation |
| Reverse scroll | Any pending buffer | Reset; process reversal normally |

**A logical step is not necessarily a raw input event.** Normalize mouse wheels and trackpads separately, using platform/event-specific scroll magnitude to accumulate gesture units. To avoid a single large touchpad burst automatically jumping maps, cap the semantic-boundary counter to at most one accepted step per dispatch/gesture detent and suppress residual overscroll upon transition. The precise trackpad normalization must be tested on target platforms.

### Buffer identity and reset conditions

`BoundaryGate` stores:

```text
boundary_kind: ENTER | EXIT | NONE
direction: IN | OUT
candidate_id: link_id | history_entry_id
count: 0..2 (the third triggers)
last_step_timestamp
```

Reset when:
- Wheel direction reverses or camera leaves the relevant boundary.
- Candidate changes, no eligible candidate exists, or cursor leaves its hit region.
- Active map changes or a transition starts/completes/fails.
- A non-zoom editing drag begins or user chooses another tool as appropriate.
- The time between logical steps exceeds a short inactivity timeout (proposed 900 ms; configurable after usability testing).

At an inward boundary, repeated wheel input **without a child under the pointer/focus** must do nothing. If multiple candidate links overlap, show a chooser; do not count steps toward an arbitrary link. Avoid count accumulation while the chooser is unresolved.

The buffer is per-viewer ephemeral input state and is **never serialized into a map document**. Show a subtle three-segment indicator near cursor or status bar, without modal confirmation.

### Pseudocode (behavior, not production implementation)

```text
onZoomLogicalStep(viewer, direction, pointer):
  if navigator.transitioning:
      return

  if canGeometricallyZoom(viewer.camera, direction):
      applyZoomAndClamp(viewer.camera, direction, pointer)
      viewer.boundaryGate.reset()
      return

  candidate = resolveLinkAtBoundary(viewer, direction, pointer)
  if candidate is ambiguous:
      showCandidateChooser()
      viewer.boundaryGate.reset()
      return
  if candidate is missing or unauthorized:
      viewer.boundaryGate.reset()
      return

  if viewer.boundaryGate.consume(direction, candidate.id) == THIRD_STEP:
      navigator.requestTransition(candidate)
```

For a zoom event that starts below the boundary and overshoots it, clamp to the limit and count **zero** boundary steps even if the device reports a large delta.

## 3. Navigation state machine

```text
IDLE
  -> PREPARING (resolve link, check visibility/permissions, load target)
  -> TRANSITIONING (animate source focus, crossfade)
  -> ACTIVATING (set target active document, floor and camera)
  -> IDLE

PREPARING / TRANSITIONING
  -> CANCEL_OR_FAILURE (restore source state)
  -> IDLE
```

Keep the source document active until the destination has successfully loaded and permissions are resolved. Only then commit the history entry and active map change. Do not mutate either document's artwork during transitions.

### Per-viewer navigation history

Each entry records source map ID, source floor ID, camera center, geometric zoom, optional rotation, preview/editor preferences if desired, and the traversed link ID. History belongs to the viewer, not to the map and not to the whole campaign.

On **Back** or the buffered outward exit, restore the latest entry's exact camera and floor, even if the parent was originally accessed from an unusual angle or zoom. When entering through a different entrance link, the same target map can use a different arrival focus/floor.

On a map opened from global search with no parent history, zooming outward must not guess a parent; provide a breadcrumb/back-to-results action or explicit list of incoming links.

## 4. Link alignment and visual transition

### Abstract / portal link

Source anchor/region and target arrival focus are unrelated coordinate spaces. Examples: city icon in a six-mile hex; dungeon entrance; tower stairs. Animate toward the source anchor, expand the target's preview, crossfade into the target document, then place its camera at the specified arrival state. Do not interpolate world coordinates between abstract maps.

### Spatially aligned link

Optionally stores a transform from target document space (or a battlemap grid space) into parent document space. This can produce a more exact crop/zoom transition. It must still allow the two documents to be edited independently.

For rotated battlemaps, the placement transform maps battlemap grid coordinates to the parent; editing the placement on the parent does not move individual painted pixels in the child.

Suggested transition modes: `INSTANT`, `ZOOM_CROSSFADE` (default) and later `ALIGNED_ZOOM`. Animation duration and reduced-motion settings are viewer preferences; fast manual navigation should be possible.

## 5. Child-map discovery without entering

Maps may have many child links and a user may forget which hex contains a particular encounter. Make the following **read-only** visualization modes available on any parent map:

| Mode | Behavior |
| --- | --- |
| Off | Hide child-map indicators |
| Markers | Icons/types/counts on source anchors; cluster when zoomed far out |
| Thumbnails | Pinned cached child previews near anchors, including stacks at shared locations |
| Overlay | Spatially transformed preview artwork within aligned footprints; abstract links fall back to pinned thumbnails |

Offer hover enlargement, link name/type, related floor count, and one-click Enter. Previews do not themselves change the active document, capture brush input, participate in selection, or become part of ordinary map export.

### Map Overview / search panel

Support filters for **selected hex**, **currently visible map area**, **whole current map**, and eventually **campaign-wide**. Entries include name, type, tags, hierarchical breadcrumb (from chosen navigation context), anchor location, cached thumbnail and floor count when applicable.

Index links and metadata without loading every child art document. Traverse the graph with a visited-ID set to avoid cycles, bounded recursion depth, and a result cap; some map documents have multiple incoming links and should not be accidentally duplicated as full data loads. Results can offer **Focus on parent anchor** or **Enter map**.

Previews are per `MapLink` when location artwork differs by entrance. A `MapDocument` can also have a canonical snapshot, but it cannot represent all entrances.

## 6. Parent underlay when editing the child

The opposite direction is equally important. When inside an independent battlemap workspace, show a configurable read-only translucent **parent reference underlay** behind its editable content.

- Spatial child: sample the transformed portion of the parent corresponding to the placed grid.
- Symbolic child: use a manually selected source crop/preview or a preselected thumbnail; do not assume a physical scale correspondence.
- Underlay controls: show/hide, opacity, source/floor selection, live refresh or freeze snapshot.
- Underlay is **not a MapLayer**; its pixels cannot be painted, erased, cut, copied, bucket-filled or accidentally saved as battlemap art.
- GM/player visibility rules apply to underlays and thumbnails, not merely the editable child layer.

## 7. Preview infrastructure

`MapPreviewManager` resolves links; `MapReferenceRenderer` displays references; `ThumbnailCache` stores bounded, versioned previews. Cache keys should include document revision, floor/visible layer set, camera/crop definition, preview purpose and **permission scope**. A public/player thumbnail must never reuse a GM-only cache entry.

Invalidate relevant previews after art edits, layer visibility changes, link/placement changes or fog/permission updates. Render visible overlays only; load overview previews lazily. A missing/corrupt preview produces a neutral placeholder and still allows opening the source document if authorized.

When a map has huge content, thumbnail generation must be budgeted separately from interactive painting so drawing remains responsive.

## 8. Acceptance scenarios

1. Reach max geometric zoom: no transition yet. Three extra inward wheel detents on one valid child enter it; two do not.
2. Reach min geometric zoom: three extra outward detents restore exactly the previous map/camera.
3. Reverse direction after 2/3: counter resets; a later inward detent is the first step, not third.
4. Pause longer than timeout after 2/3: counter resets.
5. Move pointer from child A to B after 2/3: B starts at 1/3.
6. A map with no child cannot be entered via blind inward scrolling.
7. Overlapping children force explicit candidate selection.
8. Scroll/trackpad high-resolution burst cannot single-event cross an automatic boundary.
9. Multiple thumbnails appear across neighboring hexes without activating them.
10. Symbolic link shows a pinned thumbnail rather than falsely registered artwork.
11. Editing a child with parent reference enabled leaves parent chunk hashes unchanged.
12. GM-only previews/fog are absent from player projection and network payloads.
