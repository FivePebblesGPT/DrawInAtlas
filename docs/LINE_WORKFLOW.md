# Line — current Drawing/Atlas workflow (T-072)

**Authority and availability (2026-11-02).** The owner-approved [47 Essential / 34 Later / 18 Skip inventory](DRAWING_FEATURE_INVENTORY.md) defines *scope*, not shipped tools or final UX acceptance. The [decision record](DECISIONS_DRAWING_ATLAS_2026-11-01.md), [canonical Drawing package](../addons/drawing/README.md), [test plan](DRAWING_TEST_PLAN.md) and [Kanban](Index.md) take precedence over the archived workflow below.

The independently runnable `DrawingWorkspace` in `addons/drawing/workspace.gd` currently exposes **Brush, Eraser, Select, Move, Text, Pan**. Atlas embeds the same Drawing engine for raster editing (`T-055`), while some *older Atlas tools and tests* still execute against legacy `AtlasLayer` / `AtlasRasterLayer` paths. A working legacy test does not prove the corresponding standalone tool is shipped. Atlas owns map/floor/detail, selected-cell mask constraints, entrance navigation, and the global chronological history (`T-054`); Drawing owns generic documents, tools, local edit sessions, and snapping. **No per-hex DrawingDocument** exists.

A content gesture uses `DrawingDocument.begin_edit()` → bounded `DrawingEditSession` staging → `commit()` (one undoable operation), or `cancel()` (no changes). Atlas embeds with `set_external_history(true)` and registers the edit with `AtlasEditHistory.commit_drawing()`; standalone Drawing keeps local history. Selection-only history is an **application-level opt-in, OFF by default**, not an automatic content edit. When Atlas history replays, it restores the valid originating map/floor/detail, selection and mode, preserves zoom, and pans only if content is not visible. Navigation-only actions do not create undo entries.

The once-per-gesture swept brush, exact straight **RGBA8 including hidden RGB on unchanged transparent pixels**, per-pixel edit-scope clipping, and only-touched-tile copy-on-write are generic Drawing behaviors. `DrawingEditSession.apply_region(Rect2i, PackedByteArray)` is the **bounded edit-region native-acceleration boundary**, not evidence that Blend2D, Skia or a C++ GDExtension has shipped. `T-068` is **In Progress**; no native backend is selected. Source storage uses T-066's portable `Drawings/` generations rather than a current single-file native `.scn` raster save.

## Current implementation versus Line candidate

**Engine primitive available; standalone Line tool NOT shipped:** A straight solid segment can be supplied as a two-point `PackedVector2Array` to `DrawingEditSession.paint_path()` within one revision-frozen gesture; commit or cancel retains the same atomic history rules as Brush. The standalone palette currently has no Line entry, on-canvas live endpoint preview, Shift/Alt modifiers, or saved semantic line objects. `T-024` is **Ready**; the controls and live-restyling sequence below apply to an earlier Atlas raster-first candidate, not a newly accepted Drawing UX.

**Witnesses:** `tests/drawing_raster_backend_benchmark.gd` covers canonical segment coverage; `tests/line_smoke.gd` and `tests/line_visual.gd` witness the **legacy candidate** press → draft → release and modifier handling. The future port must maintain stable edit-mask context and one history action, with separate native-backend evaluation under T-068.

---

## Historical Atlas-era workflow and candidate notes (not a current Drawing UX contract)

The following is preserved for original ticket/acceptance traceability. Its use of **“current”, “implemented”, “native save”, tool shortcuts and old test counts refers to the pre-separation Atlas-era prototype**, unless a statement is explicitly confirmed in the current section above. See `docs/Index.md` for the actual ticket status.


Status: **proposed for owner acceptance**, not a completed T-024 ticket.

### Existing behavior retained under raster-first authoring

- Press the primary pointer button on an active, **visible and unlocked Raster layer** to set a start; drag to preview; release to commit exactly one history command. A click without movement paints a round point. Escape, a tool change, focus loss, or history undo/redo cancels the draft without writing pixels.
- `AtlasStroke` is **transient gesture geometry** (document-board points, RGBA color, width in board units), **not** a saved editable Line object. On release, `AtlasRasterBrush.paint_stroke()` paints into a detached raster layer at its stored pixel density (normally 4 px/board unit); `AtlasLayerEdit` applies the result as one undoable raster change. Native save persists the raster chunks, not Line stroke records. Editable semantic wall paths belong to T-026.
- The current painter supplies a **solid line with round ends and constant width**. The Brush color and width controls are shared. Unlike the freehand Brush, which freezes its style at press, a Line's **color and width controls remain live**: changing either while the pointer is stationary refreshes the draft's detached raster preview, with no source-pixel or history mutation. The same style is used at release.
- The selected authored detail level must be displayed; automatic tool routing chooses an editable Raster layer at that level, creating one when needed. Hidden/locked targets cannot be painted. Cell edit masks **clip** both the rendered draft and committed raster pixels in document coordinates, rather than rejecting every line that crosses a mask boundary.
- **Preview authorization is stable for the gesture:** at press, Line remembers its map, floor, Raster layer, and exact edit-mask footprint. If the selection or mask geometry changes before release, the draft is discarded with an explanatory status message: **no pixels or undo entry** are produced. A fresh gesture under the current mask may commit normally. When the mask is disabled, changing the merely highlighted cell does not unnecessarily invalidate a Line. These checks concern draft-to-commit consistency, not a new user-visible Line constraint.
- The preview and final image use the same raster painter, transform and coverage rules. Undo/redo replace the affected raster-layer snapshot in one command per accepted gesture. Neither the preview nor the editor's texture caches are stored as authored artwork.

### Optional modifiers

- **Shift** rounds the dragged direction to 15° increments in board coordinates without shortening its length.
- **Alt** treats the press position as the line midpoint; the dragged displacement extends equally in both directions.
- **Shift+Alt** combines the angular constraint with symmetric placement.
- Modifiers affect the current preview and are evaluated again on release, so a modifier change before release cannot commit stale geometry. Pressing or releasing Shift/Alt while the canvas has keyboard focus refreshes the draft without moving the pointer.
- Session-only **Snap to grid** remains opt-in (T-016). When enabled, the raw press and pointer positions first snap to square/hex cell centers using the board transform; Shift's angle rule and Alt centering then apply. **Angle restriction takes precedence** if the resulting endpoint is no longer exactly on a grid center. The grid toggle's state is frozen for a gesture. Grid edits do not transform existing lines.

### Deliberately outside scope

- Paint.NET's post-release four editable line/curve handles, fill patterns, cap/arrow/dash selectors and secondary-color right click require separate UI/model policy; this candidate does not assert those are supported. Future paths in T-026 are independent editable objects, not a silent rewrite of painted Line pixels.
- A Line is a raster-painting tool; it does **not** create persistent stroke objects or provide post-release vector editing. Line selection or partial-pixel mask manipulation would be a separate design decision.
- Manual ergonomic agreement on modifiers, start/end caps, style choices and whether release should remain the commit action is outstanding. No acceptance checkbox is changed automatically.

### Evidence

- `tests/line_smoke.gd`: geometry for all four quadrants, Shift/Alt combinations, zoom levels, rotated square-grid snapping, RGBA/width, live inspector restyling without pointer movement, detached preview/final equality, D0/D1 raster isolation, cancel, edit masks (including mid-drag changes and retry), locks, hidden detail, undo and native save.
- `tests/line_visual.gd`: native pointer and framebuffer checks for Shift+Alt, restyling an idle preview, visible framebuffer changes before release, draft/final equality, Escape, changed edit-mask rejection, and compact 800×600 layout. Both suites are CI-gated by `.github/workflows/godot-check.yml`.
- Primary editor reference: [Paint.NET Line/Curve Tool](https://paint.net/doc/latest/LineCurveTool.html), describing Shift 15° and Alt-centered drawing, width/styles and a post-release finish workflow. This candidate intentionally retains DrawInAtlas's one-gesture raster commit until accepted.
