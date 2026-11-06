# Move — current Drawing/Atlas workflow (T-072)

**Authority and availability (2026-11-02).** The owner-approved [47 Essential / 34 Later / 18 Skip inventory](DRAWING_FEATURE_INVENTORY.md) defines *scope*, not shipped tools or final UX acceptance. The [decision record](DECISIONS_DRAWING_ATLAS_2026-11-01.md), [canonical Drawing package](../addons/drawing/README.md), [test plan](DRAWING_TEST_PLAN.md) and [Kanban](Index.md) take precedence over the archived workflow below.

The independently runnable `DrawingWorkspace` in `addons/drawing/workspace.gd` currently exposes **Brush, Eraser, Select, Move, Text, Pan**. Atlas embeds the same Drawing engine for raster editing (`T-055`), while some *older Atlas tools and tests* still execute against legacy `AtlasLayer` / `AtlasRasterLayer` paths. A working legacy test does not prove the corresponding standalone tool is shipped. Atlas owns map/floor/detail, selected-cell mask constraints, entrance navigation, and the global chronological history (`T-054`); Drawing owns generic documents, tools, local edit sessions, and snapping. **No per-hex DrawingDocument** exists.

A content gesture uses `DrawingDocument.begin_edit()` → bounded `DrawingEditSession` staging → `commit()` (one undoable operation), or `cancel()` (no changes). Atlas embeds with `set_external_history(true)` and registers the edit with `AtlasEditHistory.commit_drawing()`; standalone Drawing keeps local history. Selection-only history is an **application-level opt-in, OFF by default**, not an automatic content edit. When Atlas history replays, it restores the valid originating map/floor/detail, selection and mode, preserves zoom, and pans only if content is not visible. Navigation-only actions do not create undo entries.

The once-per-gesture swept brush, exact straight **RGBA8 including hidden RGB on unchanged transparent pixels**, per-pixel edit-scope clipping, and only-touched-tile copy-on-write are generic Drawing behaviors. `DrawingEditSession.apply_region(Rect2i, PackedByteArray)` is the **bounded edit-region native-acceleration boundary**, not evidence that Blend2D, Skia or a C++ GDExtension has shipped. `T-068` is **In Progress**; no native backend is selected. Source storage uses T-066's portable `Drawings/` generations rather than a current single-file native `.scn` raster save.

## Current selection and Move contract

**Available now:** in standalone Drawing choose **Select** and drag a rectangle to define pixels on the active raster layer; choose **Move**, press/drag/release to translate those selected pixels with `DrawingClipboard.move_selection()` and one `DrawingEditSession` commit. Undo/redo returns their exact bytes; a zero-displacement gesture adds no content edit. Generic selection/move is not the legacy **whole `AtlasRasterLayer` affine-transform** model described below. No promise of cross-layer lasso, nonuniform transform handles, or per-object move modes follows from the current UI.

Atlas separately owns valid map/floor/detail and global contextual history; explicit generic snapping (`DrawingSnap`) does not import Atlas grid types. **Witnesses:** `drawing/tests/standalone_smoke.gd`, `tests/drawing_history_smoke.gd`, and `tests/drawing_composition_smoke.gd` establish current edit/history/host boundaries. `tests/move_smoke.gd` / `tests/move_visual.gd` cover the legacy whole-object/affine interaction, not canonical pixel-move UI.

---

## Historical Atlas-era workflow and candidate notes (not a current Drawing UX contract)

The following is preserved for original ticket/acceptance traceability. Its use of **“current”, “implemented”, “native save”, tool shortcuts and old test counts refers to the pre-separation Atlas-era prototype**, unless a statement is explicitly confirmed in the current section above. See `docs/Index.md` for the actual ticket status.


**Move artwork (M)** in the left Tools sidebar is distinct from **Select artwork
(V)** and **Select grid cell**. The latter selects a world hex for edit masks,
not an artwork container. The board remains one continuous coordinate system;
movement never creates a per-hex canvas or a battlemat.

### Interactions

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

### Representation and future objects

An ink stroke's canonical board points are translated, retaining stroke width
and RGBA. A raster layer's **affine transform** is composed with a board-space
translation; its original chunks and pixels are not resampled. The native save
schema remains unchanged. Text and editable point-by-point wall paths do not
exist as authored object types yet: [[T-026]] and [[T-027]] must extend the
selection/move labeling and transform behavior for those *new* types. The move
tool does not invent or flatten those objects in advance.

### Verification

`tests/move_smoke.gd` exercises selecting on press, grouped movement,
previews, cancellation, locks, edit masks, hidden authored detail, rotated-hex
snapping, affine raster movement, undo/redo and native-save round-trip.
`tests/move_visual.gd` validates native pointer/shortcut behavior, palette,
inspector feedback, framebuffer rendering and 960×660 / 800×600 layouts.
Both are CI gates. Automated coverage is not a substitute for physical-pointer
or user acceptance testing.
