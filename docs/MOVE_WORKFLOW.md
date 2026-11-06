# Move tool — active-layer artwork manipulation (T-022)

**Move artwork (M)** in the left Tools sidebar is distinct from **Select artwork
(V)** and **Select grid cell**. The latter selects a world hex for edit masks,
not an artwork container. The board remains one continuous coordinate system;
movement never creates a per-hex canvas or a battlemat.

## Interactions

- **V** selects whole objects on the active ink layer or the entire raster
  asset layer. Ctrl-add/Alt-subtract and selection-marquee behavior stay with V.
  Switching **V → M → V** retains this transient selection.
- **M** clicks an existing ink stroke or whole raster layer to select it, then
  drags it in the same gesture. Starting inside the bounds of an existing
  selection moves *all* selected objects. Clicking empty canvas clears the
  selection; M does not start a marquee. The inspector says which kind of
  object is selected. **Ctrl+D** or **Enter** deselect; **Escape** cancels a
  gesture without moving its source or discarding a previously committed
  selection. The M key and palette icon choose the same tool.
- A drag has a **live in-canvas preview** from the same transform as commit.
  The original layer is unchanged until release. Releasing without a nonzero
  movement or an eligible preview produces no history entry. One successful
  move is one undo/redo action.
- **Snap to grid** is an explicit opt-in and uses the T-016 cell-to-cell board
  displacement. It never forces previously off-grid content onto an anchor;
  it handles rotated grids and independent zoom correctly. Numeric transforms
  in the inspector remain unsnapped.
- **Edit restrictions** are checked both against source and destination:
  locked/hidden layers, unpresented authored detail, stale selections, and
  selected-cell masks cannot silently move artwork. A forbidden preview is
  not committed. Other layers, links, frames, and grid settings do not follow
  a move.

## Representation and future objects

An ink stroke's canonical board points are translated, retaining stroke width
and RGBA. A raster layer's **affine transform** is composed with a board-space
translation; its original chunks and pixels are not resampled. The native save
schema remains unchanged. Text and editable point-by-point wall paths do not
exist as authored object types yet: [[T-026]] and [[T-027]] must extend the
selection/move labeling and transform behavior for those *new* types. The move
tool does not invent or flatten those objects in advance.

## Verification

`tests/move_smoke.gd` exercises selecting on press, grouped movement,
previews, cancellation, locks, edit masks, hidden authored detail, rotated-hex
snapping, affine raster movement, undo/redo and native-save round-trip.
`tests/move_visual.gd` validates native pointer/shortcut behavior, palette,
inspector feedback, framebuffer rendering and 960×660 / 800×600 layouts.
Both are CI gates. Automated coverage is not a substitute for physical-pointer
or user acceptance testing.
