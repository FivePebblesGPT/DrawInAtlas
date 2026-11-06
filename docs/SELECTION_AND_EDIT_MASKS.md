# Selection and edit masks — current Drawing/Atlas workflow (T-072)

**Authority and availability (2026-11-02).** The owner-approved [47 Essential / 34 Later / 18 Skip inventory](DRAWING_FEATURE_INVENTORY.md) defines *scope*, not shipped tools or final UX acceptance. The [decision record](DECISIONS_DRAWING_ATLAS_2026-11-01.md), [canonical Drawing package](../addons/drawing/README.md), [test plan](DRAWING_TEST_PLAN.md) and [Kanban](Index.md) take precedence over the archived workflow below.

The independently runnable `DrawingWorkspace` in `addons/drawing/workspace.gd` currently exposes **Brush, Eraser, Select, Move, Text, Pan**. Atlas embeds the same Drawing engine for raster editing (`T-055`), while some *older Atlas tools and tests* still execute against legacy `AtlasLayer` / `AtlasRasterLayer` paths. A working legacy test does not prove the corresponding standalone tool is shipped. Atlas owns map/floor/detail, selected-cell mask constraints, entrance navigation, and the global chronological history (`T-054`); Drawing owns generic documents, tools, local edit sessions, and snapping. **No per-hex DrawingDocument** exists.

A content gesture uses `DrawingDocument.begin_edit()` → bounded `DrawingEditSession` staging → `commit()` (one undoable operation), or `cancel()` (no changes). Atlas embeds with `set_external_history(true)` and registers the edit with `AtlasEditHistory.commit_drawing()`; standalone Drawing keeps local history. Selection-only history is an **application-level opt-in, OFF by default**, not an automatic content edit. When Atlas history replays, it restores the valid originating map/floor/detail, selection and mode, preserves zoom, and pans only if content is not visible. Navigation-only actions do not create undo entries.

The once-per-gesture swept brush, exact straight **RGBA8 including hidden RGB on unchanged transparent pixels**, per-pixel edit-scope clipping, and only-touched-tile copy-on-write are generic Drawing behaviors. `DrawingEditSession.apply_region(Rect2i, PackedByteArray)` is the **bounded edit-region native-acceleration boundary**, not evidence that Blend2D, Skia or a C++ GDExtension has shipped. `T-068` is **In Progress**; no native backend is selected. Source storage uses T-066's portable `Drawings/` generations rather than a current single-file native `.scn` raster save.

## Current selection and edit-scope contract

**Available now:** `DrawingSelection` represents a generic pixel-region mask; standalone **Select** drags a rectangular selection on the active raster layer, and **Move** operates on its pixels via `DrawingClipboard`. Selection alone is not a content change. Selection-only undo/redo is **OFF by default** and opt-in at application level; Atlas embeds Drawing in its own chronological history and restores valid edit context. `DrawingSnap` provides generic constraints; Atlas supplies grid candidates and edit scopes, not per-hex files. Current selection UI does **not** claim Paint.NET lasso/intersect, arbitrary path isolation, or simultaneous multi-layer selection.

**Before / after:** select rectangle → inspect outlined bounds without pixel mutation → move contents → one content history entry → undo restores bytes/position; a cancelled edit or stale revision changes nothing. When Atlas's selected-cell mask is active, only fully eligible pixels may be edited; selecting a cell is *not* creating another DrawingDocument. **Witnesses:** `drawing/tests/standalone_smoke.gd`, `tests/drawing_history_smoke.gd`, `tests/drawing_composition_smoke.gd`; `tests/selection_smoke.gd` and `tests/selection_interactions_smoke.gd` validate separate **legacy whole-object selection** behavior.

---

## Historical Atlas-era workflow and candidate notes (not a current Drawing UX contract)

The following is preserved for original ticket/acceptance traceability. Its use of **“current”, “implemented”, “native save”, tool shortcuts and old test counts refers to the pre-separation Atlas-era prototype**, unless a statement is explicitly confirmed in the current section above. See `docs/Index.md` for the actual ticket status.


### Context and reference

[[E-TOOLS]] selects Paint.NET as the primary interaction reference. In
[Paint.NET's selection reference](https://paint.net/doc/latest/SelectionTools.html)
selection operations include Replace, Add and Subtract; its
[keyboard and mouse commands](https://paint.net/doc/latest/KeyboardMouseCommands.html)
use Ctrl+drag to add, Alt+drag to subtract, and Ctrl+D to deselect.
DrawInAtlas currently selects *whole authored ink objects* or a *whole raster
asset layer*, not partial pixels or arbitrary selection polygons. We adopt the
familiar shortcuts without claiming pixel-level Paint.NET parity. Tool-specific
pixel/geometry editing is covered by [[T-020]]–[[T-028]].

### Current interaction policy

| Action | Behavior |
| --- | --- |
| Select artwork (V) | Click nearest ink stroke or whole raster asset, or drag rectangle to select fully enclosed objects |
| Click/drag without modifiers | Replace selection; empty click clears it |
| Ctrl+click/drag (Command on macOS) | Add objects to current selection on the active layer only |
| Alt+click/drag | Subtract hit objects from the current selection on the active layer |
| Ctrl+A | Select all *visible, presented* artwork on the active layer |
| Ctrl+D / Enter (with selection tool active) | Deselect |
| Escape | Cancel a current selection or transform gesture, retaining the previously committed selection; otherwise deselect |
| Click/drag within selection or drag corner handle | Move or proportionally scale selected objects, only if editable |
| Copy / Cut / Delete / Paste | Typed artwork clipboard, bounded to one explicit layer; protected edits rejected; undoable transactions |

The selected layer/detail group is always explicit. Switching layers invalidates
prior selections; a changed layer source is also rejected as stale. Hidden
artwork detail is neither targeted by pointer selection nor by Select All; a
presentation change clears the transient selection. No implicit cross-layer
mode is supplied. Ink groups and raster chunks retain their canonical board
coordinates through camera zoom, world hex boundaries and rotated overlay
changes. Raster selection selects the entire asset's transformed footprint,
including when the asset consists of multiple signed chunks; no partial-pixel
editing is claimed.

The separate **Select grid cell** tool chooses a world cell. **Restrict edits
to current tile** uses that chosen cell polygon as a *non-spatially-transforming
edit mask* over the continuous board: it controls what edits are eligible but
never creates per-hex canvases or alters artwork coordinates. For current whole
object transforms, source and destination footprints must be entirely within
the mask; ambiguous partial-object transforms are rejected rather than clipped
or silently moved. Existing selection can remain visible outside the mask but
transforms/delete are disabled when out of scope. Regular strokes are clipped
by the edit scope using the appropriate authoring tool. Native grid measurement
settings never rescale saved artwork.

### Verification and limitations

- `tests/selection_smoke.gd`: geometry, padded vector bounds, affine raster
  placement, rotated transforms, scope enforcement, selection combination,
  persistence and source-snapshot invalidation.
- `tests/selection_interactions_smoke.gd`: modifier gestures and cancellation;
  layer isolation, clipboard and history, locks and masks, hidden detail, zoom,
  rotated hex overlays and fresh-process native save roundtrip.
- `tests/selection_interactions_visual.gd`: real pointer modifier events,
  framebuffer-visible selection outline and compact-window layout under
  Xvfb/Mesa Compatibility.
- Existing `clipboard_smoke.gd`, `tools_ui_smoke.gd`, `continuous_canvas_smoke.gd`
  and `storage_smoke.gd` remain regression gates.

A multi-layer combined selection, arbitrary lasso, pixel-precise partial raster
selection and persistent selection regions are **not** implemented or implied
by this object-selection contract. They would require separately scoped
artwork-tool and representation decisions. Physical trackpad tuning and manual
UX acceptance remain unverified; do not equate automated checks with user
approval.
