# Eraser workflow — T-021

## Interaction policy

The primary reference is [Paint.NET's Eraser](https://paint.net/doc/latest/EraserTool.html), adapted to the board's existing **typed vector and raster** editing model. This ticket **does not decide the ink representation** (see [[T-028]]) or refactor the underlying geometry algorithm (see [[T-036]]). It does make the current removal semantics explicit rather than concealing a destructive format switch.

| Active layer | E / drag and tap | Protection and alpha | Undo |
| --- | --- | --- | --- |
| **Ink** (vector) | Cut the **swept round eraser** out of stroke centerline geometry, accounting for each stroke's original width. A fully hit dot disappears; other strokes become independent surviving segments. **Not** a background-colored stroke and **not** whole-object deletion. | Surviving fragments retain original RGB, alpha and width. The tool does not fade their alpha; a color/opacity picker is not offered. A cell edit mask protects any stroke whose entire padded bounds are not inside the selected cell. | One completed pointer gesture replaces the ink snapshot. Undo restores the exact original path, color, width and layer. |
| **Raster** (chunked RGBA) | Clear covered pixels to **transparent black `(0,0,0,0)`**. One continuous swept round hard eraser includes intervening pixels, even across signed chunk seams. Existing opaque and partially transparent pixels inside the stroke are fully cleared; untouched pixels retain their original RGBA. | No new raster chunk is allocated to erase empty space. A masked pixel is erased only if its entire transformed pixel quad is allowed. Locked, hidden and non-presented detail never accept the gesture. | One completed pointer gesture replaces the detached raster layer snapshot. Undo restores its original pixel bytes and metadata. |
| **Terrain, links, map documents, references** | **Not erasable by this tool.** Use terrain painting, link management or explicitly scoped selection/object commands instead. | The Eraser only targets an editable active ink or raster layer. Tool selection can move from a non-supported layer to the existing ink layer; it does not erase the terrain. | Neither links nor other documents are included in an eraser command. |

The Eraser and Brush share the **0.5–256 board-unit width** field and hovered mouse-wheel adjustment (0.5 per notch). The actual hard round eraser diameter is shown as a high-contrast coral-tinted cursor ring, correctly scaled with viewport zoom. The pointer ring is UI-only, not artwork or saved content. The inspector explains the two supported erase modes and hides brush color/alpha controls while E is selected, then restores them for Brush. The **E shortcut** and left click/drag are retained; right/middle drag still pans.

### Deliberate differences from Paint.NET

Paint.NET can soften an eraser via color alpha/hardness and edits primarily raster pixels. DrawInAtlas's **current** eraser is full strength for both supported representations. On vector ink it cuts editable geometry rather than painting alpha into pixels; raster erasure is binary per covered pixel rather than pressure/hardness-modulated. Offering Paint.NET's partial-alpha slider for only one representation would mislead users. Changing representation, introducing per-vertex alpha or pressure/hardness, and selecting only a subset of objects for the Eraser require separate decisions and migration/UX work ([[T-028]], [[T-036]]). Existing native saves and old artwork are not rewritten by this ticket.

## Verification (Godot 4.8 beta2)

- `tests/eraser_smoke.gd`: vector cuts including turns and dots, stroke alpha preservation, no-op history, invalid and cell selection masks; raster alpha, signed seams, no allocations, protected layers and quad boundaries; editor undo/redo, independently linked-map preservation and native-save roundtrips of both representations.
- `tests/eraser_visual.gd`: X11 pointer press/drag/release, eraser UI and ring at two zoom levels, true visible gap, single history transaction, restore of brush controls, native screenshot.
- Both suites are CI gates. CI's existing Web release export and source/pack save interoperability gates stay enabled.

Manual usability acceptance, pressure support and physical trackpad tuning are **not** verified by automated tests.
