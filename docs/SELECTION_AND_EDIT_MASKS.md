# Active-layer selection and edit-mask contract (T-019)

## Context and reference

[[E-TOOLS]] selects Paint.NET as the primary interaction reference. In
[Paint.NET's selection reference](https://paint.net/doc/latest/SelectionTools.html)
selection operations include Replace, Add and Subtract; its
[keyboard and mouse commands](https://paint.net/doc/latest/KeyboardMouseCommands.html)
use Ctrl+drag to add, Alt+drag to subtract, and Ctrl+D to deselect.
DrawInAtlas currently selects *whole authored ink objects* or a *whole raster
asset layer*, not partial pixels or arbitrary selection polygons. We adopt the
familiar shortcuts without claiming pixel-level Paint.NET parity. Tool-specific
pixel/geometry editing is covered by [[T-020]]–[[T-028]].

## Current interaction policy

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

## Verification and limitations

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
