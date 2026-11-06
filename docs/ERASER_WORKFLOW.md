# Eraser — current Drawing/Atlas workflow (T-072)

**Authority and availability (2026-11-02).** The owner-approved [47 Essential / 34 Later / 18 Skip inventory](DRAWING_FEATURE_INVENTORY.md) defines *scope*, not shipped tools or final UX acceptance. The [decision record](DECISIONS_DRAWING_ATLAS_2026-11-01.md), [canonical Drawing package](../addons/drawing/README.md), [test plan](DRAWING_TEST_PLAN.md) and [Kanban](Index.md) take precedence over the archived workflow below.

The independently runnable `DrawingWorkspace` in `addons/drawing/workspace.gd` currently exposes **Brush, Eraser, Select, Move, Text, Pan**. Atlas embeds the same Drawing engine for raster editing (`T-055`), while some *older Atlas tools and tests* still execute against legacy `AtlasLayer` / `AtlasRasterLayer` paths. A working legacy test does not prove the corresponding standalone tool is shipped. Atlas owns map/floor/detail, selected-cell mask constraints, entrance navigation, and the global chronological history (`T-054`); Drawing owns generic documents, tools, local edit sessions, and snapping. **No per-hex DrawingDocument** exists.

A content gesture uses `DrawingDocument.begin_edit()` → bounded `DrawingEditSession` staging → `commit()` (one undoable operation), or `cancel()` (no changes). Atlas embeds with `set_external_history(true)` and registers the edit with `AtlasEditHistory.commit_drawing()`; standalone Drawing keeps local history. Selection-only history is an **application-level opt-in, OFF by default**, not an automatic content edit. When Atlas history replays, it restores the valid originating map/floor/detail, selection and mode, preserves zoom, and pans only if content is not visible. Navigation-only actions do not create undo entries.

The once-per-gesture swept brush, exact straight **RGBA8 including hidden RGB on unchanged transparent pixels**, per-pixel edit-scope clipping, and only-touched-tile copy-on-write are generic Drawing behaviors. `DrawingEditSession.apply_region(Rect2i, PackedByteArray)` is the **bounded edit-region native-acceleration boundary**, not evidence that Blend2D, Skia or a C++ GDExtension has shipped. `T-068` is **In Progress**; no native backend is selected. Source storage uses T-066's portable `Drawings/` generations rather than a current single-file native `.scn` raster save.

## Current Eraser contract and executable sequence

**Available now:** Select a visible/unlocked raster target → **Eraser** → press/drag/release. The canonical `DrawingEditSession.paint_path(..., erase=true)` stages a hard swept footprint, writes transparent black `(0,0,0,0)` only to covered eligible pixels, and commits once. It does not overwrite untouched transparent pixels' hidden RGB. Undo restores their exact original bytes. Erasing an unallocated region is a no-op, not an instruction to create an empty tile. The historical editable-ink geometry-cutting policy below describes **legacy `AtlasInkLayer`**, not the standalone Eraser.

**Witnesses:** `drawing/tests/standalone_smoke.gd` and `tests/drawing_composition_smoke.gd` cover canonical erase and host history; `tests/drawing_raster_backend_benchmark.gd` checks mask/byte parity; `tests/eraser_smoke.gd` / `tests/eraser_visual.gd` cover legacy vector cuts and UI. Opacity-controlled erasure, pressure, and a native backend are **not** newly shipped by this documentation update.

---

## Historical Atlas-era workflow and candidate notes (not a current Drawing UX contract)

The following is preserved for original ticket/acceptance traceability. Its use of **“current”, “implemented”, “native save”, tool shortcuts and old test counts refers to the pre-separation Atlas-era prototype**, unless a statement is explicitly confirmed in the current section above. See `docs/Index.md` for the actual ticket status.


### Interaction policy

The primary reference is [Paint.NET's Eraser](https://paint.net/doc/latest/EraserTool.html), adapted to the board's existing **typed vector and raster** editing model. This ticket **does not decide the ink representation** (see [[T-028]]) or refactor the underlying geometry algorithm (see [[T-036]]). It does make the current removal semantics explicit rather than concealing a destructive format switch.

| Active layer | E / drag and tap | Protection and alpha | Undo |
| --- | --- | --- | --- |
| **Ink** (vector) | Cut the **swept round eraser** out of stroke centerline geometry, accounting for each stroke's original width. A fully hit dot disappears; other strokes become independent surviving segments. **Not** a background-colored stroke and **not** whole-object deletion. | Surviving fragments retain original RGB, alpha and width. The tool does not fade their alpha; a color/opacity picker is not offered. A cell edit mask protects any stroke whose entire padded bounds are not inside the selected cell. | One completed pointer gesture replaces the ink snapshot. Undo restores the exact original path, color, width and layer. |
| **Raster** (chunked RGBA) | Clear covered pixels to **transparent black `(0,0,0,0)`**. One continuous swept round hard eraser includes intervening pixels, even across signed chunk seams. Existing opaque and partially transparent pixels inside the stroke are fully cleared; untouched pixels retain their original RGBA. | No new raster chunk is allocated to erase empty space. A masked pixel is erased only if its entire transformed pixel quad is allowed. Locked, hidden and non-presented detail never accept the gesture. | One completed pointer gesture replaces the detached raster layer snapshot. Undo restores its original pixel bytes and metadata. |
| **Terrain, links, map documents, references** | **Not erasable by this tool.** Use terrain painting, link management or explicitly scoped selection/object commands instead. | The Eraser only targets an editable active ink or raster layer. Tool selection can move from a non-supported layer to the existing ink layer; it does not erase the terrain. | Neither links nor other documents are included in an eraser command. |

The Eraser and Brush share the **0.5–256 board-unit width** field and hovered mouse-wheel adjustment (0.5 per notch). The actual hard round eraser diameter is shown as a high-contrast coral-tinted cursor ring, correctly scaled with viewport zoom. The pointer ring is UI-only, not artwork or saved content. The inspector explains the two supported erase modes and hides brush color/alpha controls while E is selected, then restores them for Brush. The **E shortcut** and left click/drag are retained; right/middle drag still pans.

##### Deliberate differences from Paint.NET

Paint.NET can soften an eraser via color alpha/hardness and edits primarily raster pixels. DrawInAtlas's **current** eraser is full strength for both supported representations. On vector ink it cuts editable geometry rather than painting alpha into pixels; raster erasure is binary per covered pixel rather than pressure/hardness-modulated. Offering Paint.NET's partial-alpha slider for only one representation would mislead users. Changing representation, introducing per-vertex alpha or pressure/hardness, and selecting only a subset of objects for the Eraser require separate decisions and migration/UX work ([[T-028]], [[T-036]]). Existing native saves and old artwork are not rewritten by this ticket.

### Verification (Godot 4.8 beta2)

- `tests/eraser_smoke.gd`: vector cuts including turns and dots, stroke alpha preservation, no-op history, invalid and cell selection masks; raster alpha, signed seams, no allocations, protected layers and quad boundaries; editor undo/redo, independently linked-map preservation and native-save roundtrips of both representations.
- `tests/eraser_visual.gd`: X11 pointer press/drag/release, eraser UI and ring at two zoom levels, true visible gap, single history transaction, restore of brush controls, native screenshot.
- Both suites are CI gates. CI's existing Web release export and source/pack save interoperability gates stay enabled.

Manual usability acceptance, pressure support and physical trackpad tuning are **not** verified by automated tests.
