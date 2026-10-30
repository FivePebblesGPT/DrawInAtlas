# Polygon shape — T-025 review contract

**Status:** Implementation candidate; interaction and style acceptance still requires the project owner's agreement. The authoritative completion tracker remains `docs/Index.md`.

## User interaction

- Choose **Shapes → Polygon (P)**. Polygon works on the currently selected visible, unlocked **ink** layer, and selects an existing ink layer when switching from terrain/raster. It does not create a child map, raster layer, or independent document.
- **Click** to place individual vertices. The pointer previews the possible next edge, and after three valid fixed vertices the renderer shows the closed outline or interior of exactly those fixed vertices. Pending pointer motion does **not** add a fourth vertex to an Enter-committed polygon.
- **Close** by clicking the first vertex within an 8-screen-pixel radius, double-clicking after at least three vertices are fixed, pressing Enter, or right-clicking. Backspace removes the last vertex; Escape or switching tools cancels the entire gesture. Mouse release alone does not commit.
- **Style:** Inspector toggles between a round-stroked solid-color **outline** (default, brush width applies) and a **solid fill with no separate outline** (the chosen RGBA color fills the interior). This deliberately does not implement independent outline and fill colors, dashed edges, or per-point editing. The `PolygonFill` state is session-only until a shape is created.
- **Snap:** Optional grid snapping applies to *each vertex* in canonical document coordinates. The choice is frozen at the start of each polygon gesture; camera zoom and grid rotation don't change the stored coordinates.

Unlike Paint.NET's current Shapes tool, which uses preset drag-created polygons and a temporary post-drag edit mode, this implementation uses point-by-point vertex placement. That deliberate variation follows this ticket's arbitrary polygon requirement and does not pre-implement T-026's independently **editable open/closed wall paths**. The default outline/solid-fill styling and Enter-to-finish behavior take their cues from [Paint.NET's Shapes tool](https://paint.net/doc/latest/ShapeTools.html) and its [toolbar Finish convention](https://paint.net/doc/latest/Toolbar.html).

## Data and editing contract

- A valid polygon has 3–256 finite, nonrepeated neighboring vertices, nonzero area, and no nonadjacent edge intersection. Invalid or incomplete gestures produce **no history entry** and no stored artwork.
- The model is a single closed `AtlasStroke`. Outline mode remains the existing closed centerline stroke; solid-fill mode stores the optional `filled: true` flag. Omission defaults to false, so older serialized strokes and native saves remain compatible. All transforms, clipboard operations and history snapshots copy that flag.
- Filled interiors render as one colored polygon, avoiding doubled alpha along the border. An outline's normal width is retained. Filled shapes can be selected by clicking anywhere inside. The Eraser removes a touched filled shape as a whole object rather than silently splitting it into open line fragments.
- Edit scope, visibility, locks, and authored-detail presentation remain enforced by the history command. Outline shapes use the existing centerline clipping policy; filled polygons must fit **entirely** inside the active cell-mask bounding constraint, including their width margin, or are rejected without partially filling outside the mask. This conservative choice intentionally does not synthesize partial/triangulated fill fragments.
- Existing polygon geometry is *not* point-editable after commit. Selection/Move transformations still operate on the whole shape; point handles belong to T-026's separate path model.

## Verification evidence

- `tests/polygon_smoke.gd`: geometry, concavity, invalid/degenerate input, outline/fill, preview/commit, close/cancel/backspace, locks, masks, selection, eraser, undo/redo and native saves.
- `tests/polygon_visual.gd`: real native pointer clicks, visible fill interior at preview and commit, palette/inspector and compact viewport.
- Both suites are run in `.github/workflows/godot-check.yml` and require explicit passing markers.
- Legacy headless, native frame, Web export and source/pack save interoperability checks are required alongside these focused regressions.

**Open acceptance decision:** Approve the point-by-point closure shortcuts, outline versus single-color solid fill, whole-shape erasure and conservative whole-fill masking before T-025 is checked in `docs/Index.md`.
