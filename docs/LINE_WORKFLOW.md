# Line tool: raster-first interaction contract (T-024 review candidate)

Status: **proposed for owner acceptance**, not a completed T-024 ticket.

## Existing behavior retained under raster-first authoring

- Press the primary pointer button on an active, **visible and unlocked Raster layer** to set a start; drag to preview; release to commit exactly one history command. A click without movement paints a round point. Escape, a tool change, focus loss, or history undo/redo cancels the draft without writing pixels.
- `AtlasStroke` is **transient gesture geometry** (document-board points, RGBA color, width in board units), **not** a saved editable Line object. On release, `AtlasRasterBrush.paint_stroke()` paints into a detached raster layer at its stored pixel density (normally 4 px/board unit); `AtlasLayerEdit` applies the result as one undoable raster change. Native save persists the raster chunks, not Line stroke records. Editable semantic wall paths belong to T-026.
- The current painter supplies a **solid line with round ends and constant width**. The Brush color and width controls are shared. Unlike the freehand Brush, which freezes its style at press, a Line's **color and width controls remain live**: changing either while the pointer is stationary refreshes the draft's detached raster preview, with no source-pixel or history mutation. The same style is used at release.
- The selected authored detail level must be displayed; automatic tool routing chooses an editable Raster layer at that level, creating one when needed. Hidden/locked targets cannot be painted. Cell edit masks **clip** both the rendered draft and committed raster pixels in document coordinates, rather than rejecting every line that crosses a mask boundary.
- The preview and final image use the same raster painter, transform and coverage rules. Undo/redo replace the affected raster-layer snapshot in one command per accepted gesture. Neither the preview nor the editor's texture caches are stored as authored artwork.

## Optional modifiers

- **Shift** rounds the dragged direction to 15° increments in board coordinates without shortening its length.
- **Alt** treats the press position as the line midpoint; the dragged displacement extends equally in both directions.
- **Shift+Alt** combines the angular constraint with symmetric placement.
- Modifiers affect the current preview and are evaluated again on release, so a modifier change before release cannot commit stale geometry. Pressing or releasing Shift/Alt while the canvas has keyboard focus refreshes the draft without moving the pointer.
- Session-only **Snap to grid** remains opt-in (T-016). When enabled, the raw press and pointer positions first snap to square/hex cell centers using the board transform; Shift's angle rule and Alt centering then apply. **Angle restriction takes precedence** if the resulting endpoint is no longer exactly on a grid center. The grid toggle's state is frozen for a gesture. Grid edits do not transform existing lines.

## Deliberately outside scope

- Paint.NET's post-release four editable line/curve handles, fill patterns, cap/arrow/dash selectors and secondary-color right click require separate UI/model policy; this candidate does not assert those are supported. Future paths in T-026 are independent editable objects, not a silent rewrite of painted Line pixels.
- A Line is a raster-painting tool; it does **not** create persistent stroke objects or provide post-release vector editing. Line selection or partial-pixel mask manipulation would be a separate design decision.
- Manual ergonomic agreement on modifiers, start/end caps, style choices and whether release should remain the commit action is outstanding. No acceptance checkbox is changed automatically.

## Evidence

- `tests/line_smoke.gd`: geometry for all four quadrants, Shift/Alt combinations, zoom levels, rotated square-grid snapping, RGBA/width, live inspector restyling without pointer movement, detached preview/final equality, D0/D1 raster isolation, cancel, edit mask, locks, hidden detail, undo and native save.
- `tests/line_visual.gd`: native pointer and framebuffer checks for Shift+Alt, restyling an idle preview, visible framebuffer changes before release, draft/final equality, Escape and compact 800×600 layout. Both suites are CI-gated by `.github/workflows/godot-check.yml`.
- Primary editor reference: [Paint.NET Line/Curve Tool](https://paint.net/doc/latest/LineCurveTool.html), describing Shift 15° and Alt-centered drawing, width/styles and a post-release finish workflow. This candidate intentionally retains DrawInAtlas's one-gesture raster commit until accepted.
