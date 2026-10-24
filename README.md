# DrawInAtlas

**Status: native drawing/selection/clipboard tools, independent boards/grids, typed layers and recoverable persistence implemented; broader editor/VTT features are in progress.**

DrawInAtlas is a drawing board and map-first tabletop editor for West Marches / hexcrawl campaigns. Artwork is primary; grids and linked world, regional, city or encounter maps are optional structure, with one editable map at a time.

The development engine is **Godot 4.8-beta1**, standard build. Application code is GDScript. Canonical raster artwork must use lossless **WebP**; derived previews may use lossy WebP. Web export compatibility is required.

## Product principles

- One editable map at a time; references remain read-only.
- Independent documents with different grids, scales, floors and layers.
- Pointer-centered zoom, with three additional logical wheel steps at a boundary before automatic map navigation.
- Arbitrarily rotated battlemap footprints linked to independent encounter maps.
- Local-first editing; player presentation and multiplayer are future milestones.

## Run and test

- Open `project.godot` in Godot **4.8-beta1** and run `main.tscn` / F5.
- The sample campaign includes a world hexcrawl and linked Greyhaven city. Draw freely with the pen, cut ink with the eraser, and undo/redo complete gestures. Ink uses continuous board coordinates, including on gridless maps.
- **File → New board** creates an independent blank board with no grid, square cells, or pointy/flat hexes. Choose native units and distance per cell. The inspector edits spacing, origin, rotation and visibility without moving artwork; creation/grid edits support undo/redo.
- B selects the pen, E the eraser, V artwork selection, F raster/terrain fill, and L/R/O line/rectangle/ellipse outlines. Pen/eraser target editable ink or raster layers. Drag a selection to move it and its corner handle to scale uniformly; numeric selection controls also rotate it.
- Ctrl+C/X/V copies/cuts/pastes typed artwork; Ctrl+A selects all active ink or a raster asset, Delete removes the selection. Native clipboard images can be pasted as raster assets. Ctrl+N opens New board, Ctrl+Z / Ctrl+Shift+Z undo/redo, Ctrl+S saves, and Escape cancels a gesture. An asterisk marks unsaved work.
- The Layers panel creates empty raster layers for pixel painting and imports images ready for placement. Selected-cell scope clips new ink/pixels and rejects out-of-cell transforms; it never changes camera or grid geometry.
- The Layers sidebar selects editable ink/terrain layers, imports raster images, and controls names, visibility, locks, opacity and order. Hidden/locked content is protected by edit commands.
- Save/load uses `user://drawinatlas_campaign.json`, a verified previous `.bak` checkpoint and immutable lossless WebP chunk assets in the adjacent `.assets` directory. Load reports backup recovery instead of silently dropping bad content.
- The sidebar supports Maps, Search and Layers views, draggable width, active-icon collapse, and Ctrl+B (Command+B on macOS).
- One top menu bar provides **File** (new board/save/load), **Edit** (undo/redo), and **View** (sidebar, grid overlay, navigation). Drawing controls live in the grouped right inspector; the document title and dirty marker appear at the top right.
- Normal zoom stays on the current board; automatic linked-map navigation is opt-in. Native distance/unit labels are independent per map and never rescale artwork.
- Headless smoke tests: `godot --headless --path . --script res://tests/smoke.gd`.
- Artwork/history tests: `godot --headless --path . --script res://tests/artwork_smoke.gd`.
- Board/grid tests: `godot --headless --path . --script res://tests/board_grid_smoke.gd`.
- Layer/storage tests: run `tests/layers_smoke.gd`, `tests/storage_smoke.gd` and `tests/layer_ui_smoke.gd` with the same headless invocation.
- Editing tests: run `tests/fill_scope_smoke.gd`, `tests/clipboard_smoke.gd`, `tests/selection_smoke.gd` and `tests/tools_ui_smoke.gd` the same way.
- Native framebuffer test: `godot --path . --script res://tests/visual_smoke.gd`. The local client is the current priority; Web smoke testing is deferred while Web-compatible architecture is retained.

## Documentation

| Document | Purpose |
| --- | --- |
| [Implementation notes](docs/IMPLEMENTATION_NOTES.md) | Implemented behavior, validation and remaining limitations |
| [Product design](docs/PRODUCT_DESIGN.md) | Goals, planned features and acceptance criteria |
| [Architecture](docs/ARCHITECTURE.md) | Proposed runtime boundaries, rendering and commands |
| [Maps and grids](docs/MAPS_AND_GRIDS.md) | Map/floor/layer semantics and geometry |
| [Semantic zoom and previews](docs/SEMANTIC_ZOOM.md) | Navigation and exact three-step buffer |
| [Data model and storage](docs/DATA_MODEL.md) | Proposed serialized data and storage |
| [Implementation plan](docs/IMPLEMENTATION_PLAN.md) | Roadmap and decision log |

Floor controls, richer organization, projector output, networking and campaign import/export UX remain future work. Legacy linked-map placement actions still await reversible commands. See implementation notes for precise selection/fill limits and deferred browser validation.
