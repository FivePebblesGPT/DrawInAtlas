# Code readability and scene structure

> [!info] Implementation reference
> The broader findings in [[ManualReview_2026-10-30]] now drive [[Index]]. Explicit typing/skill guidance is [[T-001]]; additional module readability and commented-step work is tracked by [[T-033]], [[T-034]], [[T-035]], [[T-036]] and [[T-037]]. Earlier focused readability checks are historical evidence.

This document tracks readability improvements on `aidev`. Comparing the number
of `.gd` files to `.tscn` files was misleading: the domain model, application
services and test scripts do not describe node trees.

For the post-milestone-6 simplification, code-only review findings and prioritized
manual-review paths, see [archived readability review](Archive/2026-10-30/READABILITY_REVIEW.md).

## Fixed UI belongs in scenes

Migrated in this refactor:

- `prefab/ui.tscn` owns the editor workspace shell, canvas, inspector containers
  and status label; `AtlasEditor` wires up their signals.
- `prefab/grid_controls.tscn` and `prefab/board_dialog.tscn` define the shared
  grid form and board creation dialog.
- `prefab/layer_panel.tscn`, `prefab/overview_panel.tscn` and
  `prefab/preview_panel.tscn` define stable controls and layout.
- `prefab/preview_renderer.tscn` defines the hidden viewport/canvas and is
  instantiated only on demand, preserving lazy preview rendering.
- `prefab/inspector.tscn` owns the complete floor/tool/artwork/grid/reference
  form; `AtlasInspector` binds scene-unique controls and emits typed intents.
- `prefab/campaign_browser.tscn` owns the map list, name/tags form and preview;
  `AtlasCampaignBrowser` coordinates read-only discovery in Maps and Search.
- `prefab/link_dialog.tscn` owns entrance/footprint draft controls;
  `AtlasLinkedMaps` translates its intents into `AtlasLinkEdit` transactions.

`AtlasEditor` no longer constructs fixed controls with `.new()`. It composes
panels from scenes and connects their intents to workspace actions. Its public
control references still refer to the actual scene nodes. `AtlasCanvas` creates
data-dependent layer renderers while drawing; these are appropriate
runtime-created nodes.

Guideline: author stable visual hierarchies and defaults in `.tscn`, then
instantiate reusable views with `PackedScene.instantiate()`. Pure
`Resource` data objects and `RefCounted` service classes do not need a visual scene.

## Find code by responsibility

```text
scripts/
  campaign/                 Campaign, maps, floors, grids, links and placements
  artwork/                  Layers, strokes and raster chunks
  editing/                  User gestures, selection, clipboard and history
    commands/               Reversible edits applied to campaign data
  navigation/               Overview/search, view state, previews and zoom gate
  persistence/              Native scene store, validation and layer/pixel codecs
  interface/                Canvas, editor shell, panels and import controls
  examples/                 Resource definitions for bundled demonstration data
examples/
  northern_marches.tres     Editable example maps, grids, terrain and link
```

The `Atlas` **class-name** prefix remains a deliberate namespace because
GDScript's `class_name` registry is global. Filenames omit that redundant
prefix now that ownership is expressed by directories.

- Prefer specific identifiers such as `floor_id` and `selected_layer_id`.
- Bind scene-owned controls via `@onready`; keep signals/actions in scripts.
- A link's `hit_radius` is a **document-space** marker pick tolerance, not a
  grid cell size or viewport pixel radius. See `scripts/campaign/map_link.gd`.
- User saves are one binary `.scn` containing data-only map nodes and embedded
  Resources/WebP, plus an adjacent `.bak.scn`. UI render scenes are not save nodes.
  Keep format-specific loading/saving in `scripts/persistence/`, rather than
  teaching panels, gestures or navigation about either representation.

## Workspace ownership

The original module refactor reduced `scripts/interface/editor.gd` from 1,462 to 716
lines and removed its 23 fixed-control constructor call sites (including shared
builders). The important change is the ownership boundary, not the line count:

| Owner | Responsibility | Communication |
| --- | --- | --- |
| `AtlasEditor` | Session startup/save/load, document-level commands, undo/redo and composition | Connects typed signals and refreshes panels |
| `AtlasInspector` | Fixed inspector form, floor-ID mapping, conditional sections, numeric values | Emits intents; never edits campaign data |
| `AtlasCampaignBrowser` | Maps/search results, metadata form, read-only preview requests | Emits Open/Focus/metadata intents |
| `AtlasArtworkEditor` | Scoped ink/raster/tile editing, selections, import and clipboard | Uses canvas/history; emits layer/tool/message signals |
| `AtlasMapNavigator` | Map/floor camera memory, Back, pointer zoom and opt-in link gate | Uses canvas/view session; emits successful view changes |
| `AtlasLinkedMaps` | Parent-owned link/placement actions, command submission and draft creation | Uses canvas/history/navigator; never constructs forms |
| `AtlasLinkDialog` | Scene-owned endpoint, arrival, mode and geometry draft controls | Emits detached Resource intents; never edits the campaign |
| `AtlasMapReferences` | Derived crops, bounded capture scheduling, parent source/freeze and child display | Uses content-aware image cache and private capture service |
| `AtlasMapCapture` | Isolated input-disabled artwork rendering, cancellation and signatures | Shared by sidebar previews and reference crops |

Modules receive their actual dependencies, not an `AtlasEditor` backpointer.
The inspector and browser do not execute edit commands. Navigation does not
dirty documents. Artwork editing does not know which form or sidebar is open.
The existing menu/action facade is retained at the workspace boundary; internal
canvas signals connect directly to the responsible module.

Example: clicking the inspector's Add floor button emits `floor_created(name)`.
The workspace submits an `AtlasFloorEdit`, then asks the navigator to activate
the new floor. The successful view change refreshes the scene-owned forms.
Changing a label, section layout or default is now a scene edit, rather than a
change to that command workflow.


## Function steps: explain algorithms, not syntax (T-037)

Use **intent-named, commented phases** in a function that handles several
responsibilities (especially coordinates, traversal, mutation and result
construction). A phase is a cohesive block of work with an identifiable
input/output or safety invariant, not an arbitrary number of lines.

1. **Guard and normalize** inputs before expensive or mutating work.
2. **Establish the working space and bounds**, naming conversions and units
   where they could be confused (for example, board units versus raster pixels).
3. **Traverse or compute**, stating eligibility, scope and termination/limit
   rules at the block where they matter.
4. **Stage changes**, keeping partial results separate from canonical source
   state until all relevant checks can succeed.
5. **Construct and return** the result at the end of a successful operation.

Not every function needs all five phases or any phase comments: short cohesive
helpers should stay short. When the phases are present, put a blank line and a
brief `#` comment **before** each non-obvious block. Name the phase by what it
ensures or produces (rather than numbering `Step 1`, `Step 2`, etc.). Explain
*why* an ordering, coordinate conversion, limit, or ownership rule matters;
do not narrate obvious assignments or individual `if` statements. Keep useful
local variables adjacent to the code they explain. Extract a named helper when
its transformation or subalgorithm has a clear contract, can be understood on
its own, or is reused; avoid fragmentation into trivial one-line wrappers.
Preserve explicit types on all declarations, including locals, and follow the
file's existing indentation style.

**Representative paint example:** `AtlasRasterBrush.paint()` in
`scripts/editing/raster_brush.gd` now uses these boundaries without rewriting
its algorithm:

- Validate the layer, color and path before any candidate work.
- Enclose the board-space sweep and transform its bounds into raster pixels,
  accounting for the layer's transform.
- Cap candidate work before scanning, even over empty raster chunks.
- Test pixel centers and edit-mask quads, recording changes against the
  original layer (not once per path sample).
- Build a detached snapshot only after the entire scan succeeds.

The source already has meaningful `_touches()`, `_source_over()` and
`AtlasFill._paint_pixel_colors()` helpers; keep them instead of making the
main flow a series of one-line calls. The T-037 demonstration added only
comments and spacing; the later [[T-034]] implementation extracted a cohesive
pixel-staging scan. The geometry/eraser passes [[T-035]] and [[T-036]] remain
separate and must preserve their modules' behavior.

**Raster brush application (T-034):** `AtlasRasterBrush.paint()` now validates and
maps the board-space sweep to a raster candidate rectangle, checks the
candidate-work budget, and hands eligible pixels to `_stage_pixel_changes()`.
That helper keeps sparse-chunk erase gating before coordinate conversion,
checks coverage at transformed pixel centers, tests whole-quad edit masks,
and blends each accepted pixel once against its original image. On success,
the shared writer constructs a detached snapshot; on error, staged colors
are discarded. Keep these decisions in this order rather than replacing
them with per-sample writes or eager snapshot allocation.

**Fill application (T-033):** `AtlasFill.tiles()` now makes the terrain-key
validation, finite background bound, cell eligibility, bounded traversal and
copy-on-success steps visible. `AtlasFill.raster()` separates document-to-pixel
seed conversion from two named scans: a four-connected seed-color flood and a
sorted stored-chunk scan for global mode. Each scan returns at most `limit + 1`
eligible pixels; the caller rejects overflow before asking the shared snapshot
writer to clone and edit any image. Masking uses whole transformed pixel quads;
even transparent pixels must be stored. The shared writer can also grow partial
chunks for brush edits, while fills never select those unstored areas.

## Validation

Run the Godot 4.8-beta2 headless import/parse check and the UI smoke tests
listed in the README, notably `tests/layer_ui_smoke.gd`,
`tests/organization_ui_smoke.gd`, `tests/tools_ui_smoke.gd` and
`tests/editor_modules_smoke.gd`. The module suite exercises form signals,
numeric transforms, campaign replacement and two-workspace state isolation.
Scene path checks alone cannot prove signal or focus behavior.
