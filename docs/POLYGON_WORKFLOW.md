# Polygon — current Drawing/Atlas workflow (T-072)

**Authority and availability (2026-11-02).** The owner-approved [47 Essential / 34 Later / 18 Skip inventory](DRAWING_FEATURE_INVENTORY.md) defines *scope*, not shipped tools or final UX acceptance. The [decision record](DECISIONS_DRAWING_ATLAS_2026-11-01.md), [canonical Drawing package](../addons/drawing/README.md), [test plan](DRAWING_TEST_PLAN.md) and [Kanban](Index.md) take precedence over the archived workflow below.

The independently runnable `DrawingWorkspace` in `addons/drawing/workspace.gd` currently exposes **Brush, Eraser, Select, Move, Text, Pan**. Atlas embeds the same Drawing engine for raster editing (`T-055`), while some *older Atlas tools and tests* still execute against legacy `AtlasLayer` / `AtlasRasterLayer` paths. A working legacy test does not prove the corresponding standalone tool is shipped. Atlas owns map/floor/detail, selected-cell mask constraints, entrance navigation, and the global chronological history (`T-054`); Drawing owns generic documents, tools, local edit sessions, and snapping. **No per-hex DrawingDocument** exists.

A content gesture uses `DrawingDocument.begin_edit()` → bounded `DrawingEditSession` staging → `commit()` (one undoable operation), or `cancel()` (no changes). Atlas embeds with `set_external_history(true)` and registers the edit with `AtlasEditHistory.commit_drawing()`; standalone Drawing keeps local history. Selection-only history is an **application-level opt-in, OFF by default**, not an automatic content edit. When Atlas history replays, it restores the valid originating map/floor/detail, selection and mode, preserves zoom, and pans only if content is not visible. Navigation-only actions do not create undo entries.

The once-per-gesture swept brush, exact straight **RGBA8 including hidden RGB on unchanged transparent pixels**, per-pixel edit-scope clipping, and only-touched-tile copy-on-write are generic Drawing behaviors. `DrawingEditSession.apply_region(Rect2i, PackedByteArray)` is the **bounded edit-region native-acceleration boundary**, not evidence that Blend2D, Skia or a C++ GDExtension has shipped. `T-068` is **In Progress**; no native backend is selected. Source storage uses T-066's portable `Drawings/` generations rather than a current single-file native `.scn` raster save.

## Current implementation versus Polygon candidate

**Engine primitive available; standalone Polygon tool NOT shipped:** The generic `DrawingEditSession.paint_polygon(PackedVector2Array, rgba, selection)` rasterizes a filled three-or-more-vertex polygon into one bounded edit session. Call `begin_edit()` → stage shape → `commit()` once or `cancel()` without pixels/history. It does **not** create an editable Polygon object, show interactive vertex handles, or imply a Polygon palette action. The legacy point-by-point closure, outline/fill and editor-draft behavior below belongs to still-**Ready T-025**, not to the accepted standalone UI.

**Witnesses:** `tests/drawing_raster_backend_benchmark.gd` exercises generic bounded painting; `tests/polygon_smoke.gd` and `tests/polygon_visual.gd` cover the **legacy candidate** click-vertices → Finish / Escape sequence. The candidate must be ported and reviewed separately before claiming its modifiers or vertex editing shipped.

---

## Historical Atlas-era workflow and candidate notes (not a current Drawing UX contract)

The following is preserved for original ticket/acceptance traceability. Its use of **“current”, “implemented”, “native save”, tool shortcuts and old test counts refers to the pre-separation Atlas-era prototype**, unless a statement is explicitly confirmed in the current section above. See `docs/Index.md` for the actual ticket status.


**Status:** Working raster-first implementation candidate; interaction acceptance still requires the project owner's agreement. `docs/Index.md` is the completion tracker.

### User interaction

- Choose **Shapes → Polygon (P)**. The tool targets a visible, unlocked **Raster** layer in the displayed authored detail level. Tool routing selects an existing editable Raster layer or creates one through history if needed. It never makes a child map or an independently movable Objects shape.
- **Click** to fix vertices in document coordinates. Until three vertices are fixed, the pointer may suggest a candidate polygon; after the third vertex, the translucent/outlined preview represents **exactly the fixed vertices**. Pointer movement draws a possible next edge as a separate guide; Enter never commits an unclicked fourth vertex.
- **Close** by clicking within 8 screen pixels of the first vertex, double-clicking after at least three vertices are fixed, pressing Enter, or right-clicking. **Backspace** removes the last vertex; **Escape**, switching tools, or losing window focus cancels the draft. Mouse release does not commit.
- **Style:** The inspector toggles between a solid-color round-stroked **outline** (default; brush width applies) and **solid fill** (one fill color, no independent outline). Brush color and width remain live during vertex placement: changing them repaints the detached draft even with a stationary pointer. Freehand Brush and Eraser deliberately retain their press-time styles instead. Style settings are session-only until pixels are committed.
- **Snap:** Optional grid snapping applies to each newly clicked vertex in board coordinates; the snap setting is frozen at the start of the gesture. Zoom and grid rotation do not alter already fixed vertices. If a rotated grid changes the **enabled selected-cell edit mask** while a Polygon is in progress, the draft is rejected rather than committed under the replacement mask.

Unlike Paint.NET's drag-created polygon presets with a post-drag editing mode, this proposal uses point-by-point placement for arbitrary shapes. It remains separate from T-026's independently editable wall paths. The outline/fill styles and Finish key follow [Paint.NET Shapes](https://paint.net/doc/latest/ShapeTools.html) and [toolbar Finish](https://paint.net/doc/latest/Toolbar.html) as interaction references, not an exact behavior claim.

### Raster data and editing contract

- Geometry validation uses temporary `AtlasStroke` data: 3–256 finite, nonrepeated adjacent vertices, nonzero area, and no nonadjacent edge intersection. Degenerate/incomplete input produces no history entry or pixel edits.
- The draft is painted on a **detached Raster preview** using `AtlasRasterBrush.paint_stroke()`. Commit emits the validated temporary shape and applies the resulting raster chunks through a single `AtlasLayerEdit` history command. Native saves persist pixels at the layer's pixel density (normally 4 px/board unit), **not** a persistent Polygon/Ink stroke. No save schema was added for Polygon.
- Outlines use the swept, round-ended brush; filled shapes paint their interior once, with no separately stroked border. Alpha is composited into existing pixels. Undo/redo restore the raster-layer snapshot. The preview and committed image use the same shape painter and mask logic.
- **Raster edit masks clip pixels**, requiring each transformed pixel quad to fit inside the scope; a polygon may be partially painted when it crosses the selected cell boundary. Visibility, active-target editability and authored-detail restrictions apply at both preview and commit.
- **First-vertex authorization is frozen:** the draft remembers its original map, floor, Raster layer and copied enabled cell footprint. Changing the selected cell, grid-mask footprint, active layer or editability before a later click or Finish rejects the whole draft, clears its preview and reports the conflict; no raster or undo edit is made. Finish under the original mask commits normally. Changes to highlighted cells while locking is **off** do not reject a valid draft. Escape/tool switching also discard the frozen context.
- A committed Polygon is **raster artwork**. It is not a whole-object selection target and cannot be moved, vertex-edited, or whole-shape erased independently by Objects selection tools. Raster Eraser removes pixels, while Bucket works with existing allocated raster chunks. Use Wall Path or Text to author independently editable semantic Objects.

### Verification evidence

- `tests/polygon_smoke.gd`: geometry, invalid input, outline/fill, detached preview, live inspector restyling with a stationary pointer, preview/commit pixel equality, close/cancel/backspace, changed-cell/grid/layer mask rejection and retry, locks, detail visibility, undo/redo, rotated-grid snap and native saves. Historical `AtlasInkLayer` selection/eraser checks verify legacy representations only.
- `tests/polygon_visual.gd`: native pointer clicks, filled preview before release, live color change verified in the framebuffer, changed edit-cell rejection with cleared preview, valid retry, exact preview/commit interior, inspector and 800×600 layout.
- Both tests run in `.github/workflows/godot-check.yml`. Parser/typing, neighboring tool regressions and native save/export checks remain separate gates.

**Open acceptance decision:** The owner must approve point-by-point placement and closure shortcuts, outline versus single-color fill, raster pixel editing (instead of whole-object erasure or post-commit vertex editing), and per-pixel edit-mask clipping before T-025 is checked complete.
