# Code readability and scene structure

This document tracks readability improvements on `aidev`. Comparing the number
of `.gd` files to `.tscn` files was misleading: the domain model, application
services and test scripts do not describe node trees.

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

**Still WIP:** `AtlasEditor` creates inspector section controls and map
sidebar fields in `_build_*_controls` and `_build_sidebar_views`. Migrate
these separately without breaking exported/public references. `AtlasCanvas`
creates data-dependent layer renderers while drawing; unlike fixed interface
controls, these are appropriate runtime-created nodes.

Guideline: author stable visual hierarchies and defaults in `.tscn`, then
instantiate reusable views with `PackedScene.instantiate()`. Pure
`RefCounted` domain objects and service classes do not need a scene.

## Find code by responsibility

```text
scripts/
  campaign/                 Campaign, maps, floors, grids, links and placements
  artwork/                  Layers, strokes and raster chunks
  editing/                  User gestures, selection, clipboard and history
    commands/               Reversible edits applied to campaign data
  navigation/               Overview/search, view state, previews and zoom gate
  persistence/              JSON/WebP store, validation and layer codec
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
- Preserve the JSON + WebP save format for user-edited campaigns; use
  `Resource`/`.tres` for authorable presets and reusable Godot assets.


## Explain algorithms, not syntax

- Name phases clearly, use guard clauses when helpful and separate meaningful
  algorithm steps with a blank line. Preserve behavior rather than minimizing
  line count.
- Comment why a lifecycle, coordinate, rendering or persistence invariant is
  needed; do not narrate obvious assignments.
- Type public API inputs/outputs and follow existing file indentation until
  formatting is intentionally standardized.

## Validation

Run the Godot 4.8-beta1 headless import/parse check and the UI smoke tests
listed in the README, notably `tests/layer_ui_smoke.gd`,
`tests/organization_ui_smoke.gd` and `tests/tools_ui_smoke.gd`.
Scene path checks alone cannot prove signal or focus behavior.
