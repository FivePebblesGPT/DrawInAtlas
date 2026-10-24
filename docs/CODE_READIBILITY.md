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

## Naming and responsibility

- Prefer clear identifiers such as `floor_id` and `selected_layer_id` over
  ambiguous `id` or `data` where several kinds of ID coexist.
- Use `snake_case` for variables/functions/files, and `PascalCase` for
  `class_name` types and scene node names.
- Bind fixed UI controls via `@onready` paths and keep their event wiring in
  scripts. Avoid public API renames unless all call sites/tests are updated.
- Keep domain logic in `scripts/domain/`, use cases in `scripts/services/`
  and UI orchestration in `scripts/ui/`. See [Architecture](ARCHITECTURE.md)
  and [Implementation notes](IMPLEMENTATION_NOTES.md).

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
