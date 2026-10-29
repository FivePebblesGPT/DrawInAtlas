# DrawInAtlas

**Status: native drawing/selection/clipboard tools, independent boards/grids/floors, typed layers, reversible linked-map workflows, read-only artwork references, campaign discovery and native recoverable saves implemented; projector and collaboration features are next.**

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
- Save/load uses `user://drawinatlas_campaign.scn`: one compressed binary scene containing every map and embedded lossless WebP artwork, plus an adjacent `drawinatlas_campaign.bak.scn` recovery generation. Load reports backup recovery instead of silently dropping bad content. Old JSON saves are left untouched and are not imported.
- The sidebar supports Maps, Search and Layers views, draggable width, active-icon collapse, and Ctrl+B (Command+B on macOS).
- One top menu bar provides **File** (new board/save/load), **Edit** (undo/redo), and **View** (sidebar, grid overlay, navigation). Drawing controls live in the grouped right inspector; the document title and dirty marker appear at the top right.
- Normal zoom stays on the current board; automatic linked-map navigation is opt-in. Native distance/unit labels are independent per map and never rescale artwork.
- The Floors inspector adds, renames, reorders and chooses the saved default floor through undoable edits. Each floor retains independent artwork and viewer camera/layer preferences. Referenced/protected floors cannot be deleted.
- Maps edits board names and comma-separated tags. Search supports names, floors, kinds and exact `#tags`, with campaign/current-floor/visible-area/selected-cell filters and bounded descendant traversal. Open enters the selected floor; Focus visits an entrance's source, including broken links.
- Map/overview previews are read-only, floor-specific and cached. Visible-area search updates when the canvas pans, zooms or resizes. Preview clicks never edit the source map.
- **Linked maps…** in the inspector/View menu creates or edits marker entrances and spatial/symbolic footprints. Choose an existing target or a new independent document, destination floor and arrival camera. Select / enter drags source locations; numeric controls resize/rotate them. Edits and unlinking support undo/redo; unlinking keeps the destination.
- The battlemap tool drags a quantized footprint using configured pitch and rotation; Q/E rotate its draft, Escape cancels, and Save commits it. The new document/link/placement is one reversible transaction. Overlapping entrances open a chooser rather than selecting an arbitrary map.
- Parent references render all visible artwork types, with source entrance/floor, opacity and freeze controls. Child Spatial overlay aligns registered footprints and falls back to pinned thumbnails for symbolic links. References remain derived viewer content, never editable map layers. See [linked-map workflows](docs/LINKED_MAPS.md).
- Headless smoke tests: `godot --headless --path . --script res://tests/smoke.gd`.
- Artwork/history tests: `godot --headless --path . --script res://tests/artwork_smoke.gd`.
- Board/grid tests: `godot --headless --path . --script res://tests/board_grid_smoke.gd`.
- Layer/storage tests: run `tests/layers_smoke.gd`, `tests/storage_smoke.gd` and `tests/layer_ui_smoke.gd` with the same headless invocation.
- Editing tests: run `tests/fill_scope_smoke.gd`, `tests/clipboard_smoke.gd`, `tests/selection_smoke.gd` and `tests/tools_ui_smoke.gd` the same way.
- Workspace/organization tests: run `tests/editor_modules_smoke.gd`, `tests/organization_ui_smoke.gd`, `tests/floors_view_smoke.gd`, `tests/overview_smoke.gd` and `tests/preview_cache_smoke.gd` the same way.
- Linked-map command/UI tests: run `tests/links_smoke.gd` and `tests/linked_maps_ui_smoke.gd` headlessly. The UI suite also runs with the native renderer.
- Native framebuffer test: `godot --path . --script res://tests/visual_smoke.gd`. The local client is the current priority; Web smoke testing is deferred while Web-compatible architecture is retained.
- Native preview acceptance: `godot --path . --script res://tests/preview_ui_smoke.gd`. For an isolated software-rendered run, use `LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a godot --display-driver x11 --audio-driver Dummy --rendering-method gl_compatibility --path . --script res://tests/preview_ui_smoke.gd`.
- Native linked-map/reference acceptance: use the same Xvfb/Mesa command with `tests/linked_maps_ui_smoke.gd` and `tests/references_ui_smoke.gd`.
- Reproduce raster codec and complete save-transaction measurements with the commands in [native raster benchmarks](docs/NATIVE_SAVE_BENCHMARKS.md).

## Project layout

Editor UI is composed in `prefab/*.tscn`, with controllers in
`scripts/interface/`. Core document types live in `scripts/campaign/` and
`scripts/artwork/`. Commands and editing tools live in `scripts/editing/`,
view/navigation services in `scripts/navigation/`, and save/load code in
`scripts/persistence/`. The editable bundled campaign is in
`examples/northern_marches.tres` (Godot Resources); user saves use a single embedded binary `.scn` and an adjacent validated
`.bak.scn` recovery generation.

`AtlasEditor` composes scene-owned inspector/browser forms, an
`AtlasArtworkEditor` for scoped editing and an `AtlasMapNavigator` for view
state. See [Code readability](docs/CODE_READIBILITY.md) for responsibilities.
The native campaign save implementation uses one binary **`.scn`**
containing Resource-backed domain data and embedded lossless WebP chunks.
No standalone `.res` or artwork sidecars are written.

## Documentation

| Document | Purpose |
| --- | --- |
| [Implementation notes](docs/IMPLEMENTATION_NOTES.md) | Implemented behavior, validation and remaining limitations |
| [Code readability](docs/CODE_READIBILITY.md) | UI scene composition, naming, comments and remaining cleanup work |
| [Product design](docs/PRODUCT_DESIGN.md) | Goals, planned features and acceptance criteria |
| [Architecture](docs/ARCHITECTURE.md) | Proposed runtime boundaries, rendering and commands |
| [Maps and grids](docs/MAPS_AND_GRIDS.md) | Map/floor/layer semantics and geometry |
| [Semantic zoom and previews](docs/SEMANTIC_ZOOM.md) | Navigation and exact three-step buffer |
| [Linked-map workflows](docs/LINKED_MAPS.md) | Reversible entrances/placements, explicit navigation and read-only artwork references |
| [Data model and storage](docs/DATA_MODEL.md) | Current domain/native storage contract and historical examples |
| [Native saves](docs/NATIVE_SAVE_IMPLEMENTATION.md) | Current scene format, verification and portability limits |
| [Raster benchmarks](docs/NATIVE_SAVE_BENCHMARKS.md) | Codec decision AD-10, measurements and reproduction commands |
| [Implementation plan](docs/IMPLEMENTATION_PLAN.md) | Roadmap and decision log |

Projector output, networking and campaign import/export UX remain future work. Native saves pass Godot 4.8-beta1 acceptance; whole-file rewrite/load costs and codec trade-offs are documented in the benchmark report. See implementation notes for precise feature limits and deferred browser validation.
