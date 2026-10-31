# Line tool: interaction contract (T-024 review candidate)

Status: **proposed for owner acceptance**, not a completed T-024 ticket.

## Existing behavior retained

- Press the primary pointer button on the active, editable ink layer to set a start; drag to preview; release to commit exactly one history command. A click without movement creates a round point. Escape, a tool change, or focus loss cancels the draft without mutating the source.
- The current stroke representation is an `AtlasStroke` (document-space points, RGBA, width). The current renderer supplies a **solid line with round ends and constant width**. The Brush color and width controls are shared; their chosen values are copied into the stroke at commit. No dashed patterns, arrowheads, line cap selectors, curve handles, or destructive migrations are silently added here.
- The active authored detail level must be displayed, and the active ink layer must be editable; locked layers are rejected. Cell edit masks **clip** the rendered draft and committed stroke in document coordinates, rather than rejecting all crossing lines.
- Preview and final artwork are drawn through the same layer rendering path. Native save persists the unchanged `AtlasStroke` schema. Undo/redo operate on one stroke command per accepted gesture.

## New optional modifiers

- **Shift** rounds the dragged direction to 15° increments in board coordinates without shortening its length.
- **Alt** treats the press position as the line midpoint; the dragged displacement extends equally in both directions.
- **Shift+Alt** combines the angular constraint with symmetric placement.
- Modifiers apply to the current preview and are evaluated again on release, preventing a stale draft from being stored if a modifier changes before release. Pressing or releasing Shift/Alt while the canvas has keyboard focus also refreshes the draft without moving the pointer.
- Session-only **Snap to grid** remains opt-in (T-016). When enabled, the raw press and pointer positions first snap to square/hex cell centers using the board transform; Shift's angle rule and Alt centering are then applied. **Angle restriction takes precedence** if the resulting endpoint is no longer exactly on a grid center. The grid toggle's state is frozen for a gesture. Grid edits do not transform any existing line.

## Deliberately outside scope

- Paint.NET's post-release four editable line/curve handles, fill patterns, cap/arrow/dash selectors and secondary-color right click require separate UI/model policy; this candidate does not assert those are supported. Future paths in T-026 are independent editable objects, not a silent rewrite of line strokes.
- Raster line drawing and partial-pixel selection are not introduced. The Line tool requires an ink layer (the existing tool-selection behavior).
- Manual ergonomic agreement on modifiers, start/end caps, style choices and whether release should remain the commit action is still outstanding; no acceptance checkbox is changed automatically.

## Evidence

- `tests/line_smoke.gd`: geometry for all four quadrants, Shift/Alt combinations, zoom levels, rotated square-grid snapping, RGBA/width, cancel, edit mask, locks, hidden detail, undo/redo and native save.
- `tests/line_visual.gd`: native real pointer, framebuffer draft/commit comparison, Escape, compact 800×600 layout; both suites gated by `.github/workflows/godot-check.yml`.
- Primary editor reference: [Paint.NET Line/Curve Tool](https://paint.net/doc/latest/LineCurveTool.html), describing Shift 15° and Alt-centered drawing, width/styles, and its post-release finish workflow. The prototype intentionally retains DrawInAtlas's one-gesture commit until accepted.
