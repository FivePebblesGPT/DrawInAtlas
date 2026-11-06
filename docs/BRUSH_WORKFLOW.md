# Brush — current Drawing/Atlas workflow (T-072)

**Authority and availability (2026-11-02).** The owner-approved [47 Essential / 34 Later / 18 Skip inventory](DRAWING_FEATURE_INVENTORY.md) defines *scope*, not shipped tools or final UX acceptance. The [decision record](DECISIONS_DRAWING_ATLAS_2026-11-01.md), [canonical Drawing package](../addons/drawing/README.md), [test plan](DRAWING_TEST_PLAN.md) and [Kanban](Index.md) take precedence over the archived workflow below.

The independently runnable `DrawingWorkspace` in `addons/drawing/workspace.gd` currently exposes **Brush, Eraser, Select, Move, Text, Pan**. Atlas embeds the same Drawing engine for raster editing (`T-055`), while some *older Atlas tools and tests* still execute against legacy `AtlasLayer` / `AtlasRasterLayer` paths. A working legacy test does not prove the corresponding standalone tool is shipped. Atlas owns map/floor/detail, selected-cell mask constraints, entrance navigation, and the global chronological history (`T-054`); Drawing owns generic documents, tools, local edit sessions, and snapping. **No per-hex DrawingDocument** exists.

A content gesture uses `DrawingDocument.begin_edit()` → bounded `DrawingEditSession` staging → `commit()` (one undoable operation), or `cancel()` (no changes). Atlas embeds with `set_external_history(true)` and registers the edit with `AtlasEditHistory.commit_drawing()`; standalone Drawing keeps local history. Selection-only history is an **application-level opt-in, OFF by default**, not an automatic content edit. When Atlas history replays, it restores the valid originating map/floor/detail, selection and mode, preserves zoom, and pans only if content is not visible. Navigation-only actions do not create undo entries.

The once-per-gesture swept brush, exact straight **RGBA8 including hidden RGB on unchanged transparent pixels**, per-pixel edit-scope clipping, and only-touched-tile copy-on-write are generic Drawing behaviors. `DrawingEditSession.apply_region(Rect2i, PackedByteArray)` is the **bounded edit-region native-acceleration boundary**, not evidence that Blend2D, Skia or a C++ GDExtension has shipped. `T-068` is **In Progress**; no native backend is selected. Source storage uses T-066's portable `Drawings/` generations rather than a current single-file native `.scn` raster save.

## Current Brush contract and executable sequence

**Available now:** Brush is in the standalone palette and Atlas's composed main canvas; the old ink/vector-specific Brush assertions below describe the legacy path. Choose an editable raster layer → choose **Brush** → press/drag/release → one `DrawingEditSession.paint_path()` gesture commits to its original document and detail. A single covered pixel is blended at most once during that gesture, including turns and overlapping pointer samples; a later gesture can accumulate alpha. Undo restores the prior pixels; redo reapplies them. Cancel or a rejected revision makes no change. The canonical UI exposes a **pixel-width** control and color; the historical 0.5–256 **board-unit** inspector and ring should not be presented as standalone controls.

**Witnesses:** `drawing/tests/standalone_smoke.gd` for independent Brush → history → reopen, `tests/drawing_composition_smoke.gd` for live Atlas pointer routing and the frozen map/detail target, `tests/drawing_raster_backend_benchmark.gd` for canonical overlap/byte parity, and `tests/brush_smoke.gd` / `tests/brush_visual.gd` for **legacy ink/raster** inspector and vector behavior. Brushes with pressure, softness, advanced spacing or native library acceleration are not asserted available.

---

## Historical Atlas-era workflow and candidate notes (not a current Drawing UX contract)

The following is preserved for original ticket/acceptance traceability. Its use of **“current”, “implemented”, “native save”, tool shortcuts and old test counts refers to the pre-separation Atlas-era prototype**, unless a statement is explicitly confirmed in the current section above. See `docs/Index.md` for the actual ticket status.


### Reference and scope

The Paint.NET Paintbrush is the primary reference for **click to make a mark, drag for a continuous stroke, size and RGBA editing, and one complete gesture**. References: [Paint.NET Paintbrush](https://paint.net/doc/latest/Paintbrush.html) and [Keyboard & Mouse Commands](https://paint.net/doc/latest/KeyboardMouseCommands.html). DrawInAtlas draws in *board units* rather than pixel-only image coordinates and retains the project's existing navigation gestures.

This ticket improves the existing `PEN` tool; it does not introduce a second brush, switch ink representations, migrate save data, or change the eraser model (see [[T-021]], [[T-028]] and [[T-036]]).

### User interaction

- **B / Brush** in the Tools sidebar; **left click** makes one round mark, **left drag** makes one continuous hard round stroke. Press → motion → release is one undoable history command. Right/middle drag remains canvas pan, not Paint.NET's secondary color gesture.
- The right inspector exposes **Color / opacity** (alpha-enabled color picker) and **Width (board units)**. Diameter is 0.5–256, adjustable precisely by typing or by 0.5 per hovered wheel notch per [[T-011]]. New width/color/alpha values apply to the next brush gesture; an already-started stroke snapshots them at press time.
- A high-contrast double-outline cursor ring follows the pointer over editable ink/raster layers, at the actual board-space radius × camera zoom. It is not drawn into authored artwork or saved pixels. It disappears when the pointer leaves the canvas or another tool is chosen. Hidden/locked layers and mismatched presented-detail targets do not show an editable brush ring.
- On an **ink layer**, the stroke remains editable vector geometry, with unchanged document-space point samples, source RGBA and width. Existing round join/cap logic from [[T-010]] preserves uniform opacity at turns and taps.
- On a **raster layer**, a hard round swept footprint uses the source color **over** the old RGBA pixels. Paint is applied **once per covered pixel per gesture**, even when adjacent sampled brush circles overlap; a second gesture can accumulate alpha. The operation is a detached raster-layer snapshot for undo/redo. Opaque brush and transparent-pixel no-op behavior remain unchanged. This affects future paint gestures, *not* existing saved pixels.
- The grid does not tile, own or interrupt brush geometry. Strokes cross cells, hexes and signed raster chunk seams; grid/camera zoom, pan and rotation never mutate authored coordinates. Enabled edit-cell masks clip vector ink by the full stroke radius, or admit only raster pixels whose entire transformed quad is inside the mask. Locked/hidden layers and hidden authored detail reject brush edits.

##### Intentional differences / later scope

Paint.NET offers brush hardness/spacing, stylus pressure, input smoothing and a secondary brush color. These are **not** silently claimed as features: DrawInAtlas currently uses a constant-diameter hard brush and explicit board-unit samples, and right-drag pans. Future stylistic presets, if desired, require separate product acceptance. The pending ink-representation investigation [[T-028]] remains a separate decision. Brush ring appearance and physical-trackpad input still warrant owner usability review.

### Acceptance evidence (Godot 4.8 beta2, 2026-10-30)

- `tests/brush_smoke.gd`: **34 checks** for RGBA source-over, alpha accumulation per gesture (but not per sample), transparent no-op, masks, negative/positive chunk ownership, locked/hidden content, inspector RGBA synchronization, vector/raster history and native save roundtrips.
- `tests/brush_visual.gd`: **12 native checks**, actual X11 press/drag/release and pointer motion, exact cursor diameter at 1× and 2× zoom, rendered translucent stroke, undo/redo, and a 960×660 screenshot.
- CI runs both tests, checks their pass markers, and rejects `SCRIPT ERROR:` / `ERROR:` / failed assertions.
- **33/33 headless suites** (two batches) and **17/17 native framebuffer suites** (in batches) passed, including prior drawing/selection/LOD/layout/preview checks. The Web release export, main-scene launch, parser/import and explicit typing audit passed.
- **4/4** fresh-process save portability checks passed: source write → pack read, pack write → source read.
- Remote CI, browser runtime and hands-on owner acceptance have **not** been run. The distinct pending T-009, T-015 and T-018 decisions remain open.
