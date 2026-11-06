# Brush workflow — T-020

## Reference and scope

The Paint.NET Paintbrush is the primary reference for **click to make a mark, drag for a continuous stroke, size and RGBA editing, and one complete gesture**. References: [Paint.NET Paintbrush](https://paint.net/doc/latest/Paintbrush.html) and [Keyboard & Mouse Commands](https://paint.net/doc/latest/KeyboardMouseCommands.html). DrawInAtlas draws in *board units* rather than pixel-only image coordinates and retains the project's existing navigation gestures.

This ticket improves the existing `PEN` tool; it does not introduce a second brush, switch ink representations, migrate save data, or change the eraser model (see [[T-021]], [[T-028]] and [[T-036]]).

## User interaction

- **B / Brush** in the Tools sidebar; **left click** makes one round mark, **left drag** makes one continuous hard round stroke. Press → motion → release is one undoable history command. Right/middle drag remains canvas pan, not Paint.NET's secondary color gesture.
- The right inspector exposes **Color / opacity** (alpha-enabled color picker) and **Width (board units)**. Diameter is 0.5–256, adjustable precisely by typing or by 0.5 per hovered wheel notch per [[T-011]]. New width/color/alpha values apply to the next brush gesture; an already-started stroke snapshots them at press time.
- A high-contrast double-outline cursor ring follows the pointer over editable ink/raster layers, at the actual board-space radius × camera zoom. It is not drawn into authored artwork or saved pixels. It disappears when the pointer leaves the canvas or another tool is chosen. Hidden/locked layers and mismatched presented-detail targets do not show an editable brush ring.
- On an **ink layer**, the stroke remains editable vector geometry, with unchanged document-space point samples, source RGBA and width. Existing round join/cap logic from [[T-010]] preserves uniform opacity at turns and taps.
- On a **raster layer**, a hard round swept footprint uses the source color **over** the old RGBA pixels. Paint is applied **once per covered pixel per gesture**, even when adjacent sampled brush circles overlap; a second gesture can accumulate alpha. The operation is a detached raster-layer snapshot for undo/redo. Opaque brush and transparent-pixel no-op behavior remain unchanged. This affects future paint gestures, *not* existing saved pixels.
- The grid does not tile, own or interrupt brush geometry. Strokes cross cells, hexes and signed raster chunk seams; grid/camera zoom, pan and rotation never mutate authored coordinates. Enabled edit-cell masks clip vector ink by the full stroke radius, or admit only raster pixels whose entire transformed quad is inside the mask. Locked/hidden layers and hidden authored detail reject brush edits.

### Intentional differences / later scope

Paint.NET offers brush hardness/spacing, stylus pressure, input smoothing and a secondary brush color. These are **not** silently claimed as features: DrawInAtlas currently uses a constant-diameter hard brush and explicit board-unit samples, and right-drag pans. Future stylistic presets, if desired, require separate product acceptance. The pending ink-representation investigation [[T-028]] remains a separate decision. Brush ring appearance and physical-trackpad input still warrant owner usability review.

## Acceptance evidence (Godot 4.8 beta2, 2026-10-30)

- `tests/brush_smoke.gd`: **34 checks** for RGBA source-over, alpha accumulation per gesture (but not per sample), transparent no-op, masks, negative/positive chunk ownership, locked/hidden content, inspector RGBA synchronization, vector/raster history and native save roundtrips.
- `tests/brush_visual.gd`: **12 native checks**, actual X11 press/drag/release and pointer motion, exact cursor diameter at 1× and 2× zoom, rendered translucent stroke, undo/redo, and a 960×660 screenshot.
- CI runs both tests, checks their pass markers, and rejects `SCRIPT ERROR:` / `ERROR:` / failed assertions.
- **33/33 headless suites** (two batches) and **17/17 native framebuffer suites** (in batches) passed, including prior drawing/selection/LOD/layout/preview checks. The Web release export, main-scene launch, parser/import and explicit typing audit passed.
- **4/4** fresh-process save portability checks passed: source write → pack read, pack write → source read.
- Remote CI, browser runtime and hands-on owner acceptance have **not** been run. The distinct pending T-009, T-015 and T-018 decisions remain open.
