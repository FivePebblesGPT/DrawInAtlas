# Editable wall paths — proposed T-026 interaction and storage contract

**Status:** implementation candidate; owner approval required before T-026 acceptance. This is distinct from the Polygon shape/fill tool (T-025) and selection-lasso workflows.

## Authoring and editing

- Select **Wall path (W)** in the left Tools palette and an editable ink layer at the currently presented D0–D32 detail level. The path is positioned in continuous document coordinates, independent of hexes, zoom and camera.
- Click to place control points. **Enter** or **double-click** finishes an **open** path with at least two points. **Right-click** finishes a **closed** enclosure with at least three non-collinear points; clicking near the first point also closes it. **Backspace** removes the most recent unfinished point; **Escape** cancels the unfinished path without changing history.
- Click an existing wall vertex and drag to move it, with a live outline preview and one undoable commit on release. A click without movement only selects the path and does not snap or move an off-grid vertex. **Shift+click** an edge to insert a point. **Alt+click** a vertex to delete one, unless that would leave fewer than two vertices (open) or three (closed). Invalid candidate positions/geometry do not mutate stored paths. The selected path's vertices appear as blue handles.
- A click on an existing path edge selects it without replacing it or starting a new path. Click **Apply color & width to selected path** in the inspector to restyle the chosen path from the current brush controls, as a separate undoable command. Existing paths do not automatically restyle when a brush setting changes. Path style is a solid round-ended outline and never a filled area; Polygon retains its independent Outline/Solid modes.
- Grid snapping is opt-in and frozen during a gesture. Point placement, insertion and vertex dragging use the board's transformed grid in document coordinates. Snapping does not rewrite unaffected vertices.

## Edits and safety

- The active ink layer must be visible, unlocked and currently presented. No tool action targets another layer/detail level, even when an object is visible elsewhere.
- Creating/editing a path checks the **entire stroked bounding rectangle** against the active cell mask; unlike ordinary freehand strokes, wall vertices are not clipped into fragments that would lose editability. Both original and replacement extents must be permitted for modifications. An invalid or disallowed action is a no-op.
- Selection, Move, uniform transform, hierarchy and clipboard retain path identity. The vector eraser removes a **whole touched path**, rather than splitting it into non-editable ink fragments. The eraser never rasterizes the path. All successful changes are one history command.
- No pressure, per-edge styling, Bezier controls, stroke dashes, or point handles for unrelated Polygon shapes in this ticket.

## Representation and compatibility

- `AtlasStroke` retains its historic format for regular strokes and Polygon shapes. An editable wall path is stored in the ink layer with `editable_path=true`, `closed_path=bool`, and a list of **unique control vertices** in `points`; a closing edge is generated only while rendering or hit-testing. `filled` must be false. `color` and `width` remain explicit style values.
- The typed `AtlasEditablePath` service validates construction and vertex operations (2–256 points open; 3–256 points closed; finite points, nonzero consecutive edges and nonzero enclosed area). Both flags are persisted through native scenes, dictionary validation, clipboard and command copies. Unknown or malformed clipboard fields are rejected. Existing saves without the flags load unchanged.
- This is an **additive** schema change, not conversion/migration of old strokes or child maps. Native-save, Web export, read/write pack interoperability and undo/redo tests are required. Once accepted, later text and representation tickets must preserve this distinct editable object.

## Proposed acceptance choices

The owner still needs to approve: click/Enter/close behavior; Shift-insert/Alt-delete/drag operations; explicit restyle action and whole-path erasure; conservative whole-path edit mask; and additive `AtlasStroke` resource flags. These choices are **proposed**, not inferred as accepted.
