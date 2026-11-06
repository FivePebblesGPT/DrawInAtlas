# Wall Path — current Drawing/Atlas workflow (T-072)

**Authority and availability (2026-11-02).** The owner-approved [47 Essential / 34 Later / 18 Skip inventory](DRAWING_FEATURE_INVENTORY.md) defines *scope*, not shipped tools or final UX acceptance. The [decision record](DECISIONS_DRAWING_ATLAS_2026-11-01.md), [canonical Drawing package](../addons/drawing/README.md), [test plan](DRAWING_TEST_PLAN.md) and [Kanban](Index.md) take precedence over the archived workflow below.

The independently runnable `DrawingWorkspace` in `addons/drawing/workspace.gd` currently exposes **Brush, Eraser, Select, Move, Text, Pan**. Atlas embeds the same Drawing engine for raster editing (`T-055`), while some *older Atlas tools and tests* still execute against legacy `AtlasLayer` / `AtlasRasterLayer` paths. A working legacy test does not prove the corresponding standalone tool is shipped. Atlas owns map/floor/detail, selected-cell mask constraints, entrance navigation, and the global chronological history (`T-054`); Drawing owns generic documents, tools, local edit sessions, and snapping. **No per-hex DrawingDocument** exists.

A content gesture uses `DrawingDocument.begin_edit()` → bounded `DrawingEditSession` staging → `commit()` (one undoable operation), or `cancel()` (no changes). Atlas embeds with `set_external_history(true)` and registers the edit with `AtlasEditHistory.commit_drawing()`; standalone Drawing keeps local history. Selection-only history is an **application-level opt-in, OFF by default**, not an automatic content edit. When Atlas history replays, it restores the valid originating map/floor/detail, selection and mode, preserves zoom, and pans only if content is not visible. Navigation-only actions do not create undo entries.

The once-per-gesture swept brush, exact straight **RGBA8 including hidden RGB on unchanged transparent pixels**, per-pixel edit-scope clipping, and only-touched-tile copy-on-write are generic Drawing behaviors. `DrawingEditSession.apply_region(Rect2i, PackedByteArray)` is the **bounded edit-region native-acceleration boundary**, not evidence that Blend2D, Skia or a C++ GDExtension has shipped. `T-068` is **In Progress**; no native backend is selected. Source storage uses T-066's portable `Drawings/` generations rather than a current single-file native `.scn` raster save.

## Current implementation versus editable Wall Path proposal

**Not shipped in the canonical Drawing editor:** `DrawingDocument` currently has generic group/raster/text/objects layers, but no standalone Wall Path vertex-editing UI or published `AtlasEditablePath` equivalent in its generic package. In particular, choosing **W**, clicking vertices, entering an open path, right-click-closing, Shift-inserting or Alt-deleting are **T-026 Ready candidate behaviors**, not proven Drawing tools. The historical `AtlasStroke`/`AtlasEditablePath` shape contract below is a legacy Atlas prototype, not a substitute for a canonical object model.

**Proposed sequence for T-026:** select a valid target → click vertices → see a reversible draft → Finish as *one* history command, or Escape without a change; dragging/inserting/deleting a vertex must preserve the original map/detail and mask restrictions. No such UI is advertised as available today. **Witnesses:** `tests/wall_paths_smoke.gd` / `tests/wall_paths_visual.gd` cover the legacy implementation; `tests/drawing_history_smoke.gd` covers the generic undo/context contract into which a future port must fit.

---

## Historical Atlas-era workflow and candidate notes (not a current Drawing UX contract)

The following is preserved for original ticket/acceptance traceability. Its use of **“current”, “implemented”, “native save”, tool shortcuts and old test counts refers to the pre-separation Atlas-era prototype**, unless a statement is explicitly confirmed in the current section above. See `docs/Index.md` for the actual ticket status.


**Status:** implementation candidate; owner approval required before T-026 acceptance. This is distinct from the Polygon shape/fill tool (T-025) and selection-lasso workflows.

### Authoring and editing

- Select **Wall path (W)** in the left Tools palette and an editable ink layer at the currently presented D0–D32 detail level. The path is positioned in continuous document coordinates, independent of hexes, zoom and camera.
- Click to place control points. **Enter** or **double-click** finishes an **open** path with at least two points. **Right-click** finishes a **closed** enclosure with at least three non-collinear points; clicking near the first point also closes it. **Backspace** removes the most recent unfinished point; **Escape** cancels the unfinished path without changing history. Completed draft edges use the same vector renderer, color, opacity and width as the eventual saved wall; only the pointer-to-next-point guide is thin gold. Changing the current color/width while placing vertices repaints the draft immediately, without committing pixels or changing existing walls.
- Click an existing wall vertex and drag to move it, with a live outline preview and one undoable commit on release. A click without movement only selects the path and does not snap or move an off-grid vertex. **Shift+click** an edge to insert a point. **Alt+click** a vertex to delete one, unless that would leave fewer than two vertices (open) or three (closed). Invalid candidate positions/geometry do not mutate stored paths. The selected path's vertices appear as blue handles.
- A click on an existing path edge selects it without replacing it or starting a new path. Click **Apply color & width to selected path** in the inspector to restyle the chosen path from the current brush controls, as a separate undoable command. Existing paths do not automatically restyle when a brush setting changes. Path style is a solid round-ended outline and never a filled area; Polygon retains its independent Outline/Solid modes.
- Grid snapping is opt-in and frozen during a gesture. Point placement, insertion and vertex dragging use the board's transformed grid in document coordinates. Snapping does not rewrite unaffected vertices.

### Edits and safety

- The active ink layer must be visible, unlocked and currently presented. No tool action targets another layer/detail level, even when an object is visible elsewhere.
- Creating/editing a path checks the **entire stroked bounding rectangle** against the active cell mask; unlike ordinary freehand strokes, wall vertices are not clipped into fragments that would lose editability. Both original and replacement extents must be permitted for modifications. An invalid or disallowed action is a no-op.
- The initial point of an unfinished wall, or the press on an existing vertex, freezes the **map, floor, Objects layer instance and effective selected-cell mask**. Changing the selected cell while the mask is active, changing the editing target, or locking the original layer before completion rejects the pending path/drag, clears its preview and shows a reason; no artwork or history is changed. Right-click closure, Enter, double-click and vertex release all obey the same check. A new gesture can retry under the current mask. If masking is off, changing only cell focus does not invalidate the gesture.
- Selection, Move, uniform transform, hierarchy and clipboard retain path identity. The vector eraser removes a **whole touched path**, rather than splitting it into non-editable ink fragments. The eraser never rasterizes the path. All successful changes are one history command.
- No pressure, per-edge styling, Bezier controls, stroke dashes, or point handles for unrelated Polygon shapes in this ticket.

### Representation and compatibility

- `AtlasStroke` retains its historic format for regular strokes and Polygon shapes. An editable wall path is stored in the ink layer with `editable_path=true`, `closed_path=bool`, and a list of **unique control vertices** in `points`; a closing edge is generated only while rendering or hit-testing. `filled` must be false. `color` and `width` remain explicit style values.
- The typed `AtlasEditablePath` service validates construction and vertex operations (2–256 points open; 3–256 points closed; finite points, nonzero consecutive edges and nonzero enclosed area). Both flags are persisted through native scenes, dictionary validation, clipboard and command copies. Unknown or malformed clipboard fields are rejected. Existing saves without the flags load unchanged.
- This is an **additive** schema change, not conversion/migration of old strokes or child maps. Native-save, Web export, read/write pack interoperability and undo/redo tests are required. Once accepted, later text and representation tickets must preserve this distinct editable object.

### Proposed acceptance choices

The owner still needs to approve: click/Enter/close behavior; Shift-insert/Alt-delete/drag operations; explicit restyle action and whole-path erasure; conservative whole-path edit mask; and additive `AtlasStroke` resource flags. These choices are **proposed**, not inferred as accepted.
