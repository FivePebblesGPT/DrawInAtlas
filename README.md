# DrawInAtlas

**Status: early GDScript editor scaffold, not a full-featured VTT.**

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
- The sample campaign includes a world hexcrawl and linked Greyhaven city. Paint cells, select a cell, restrict painting, and create rotated battlemaps.
- Save/load uses the provisional `user://drawinatlas_campaign.json` slot.
- The sidebar supports Maps, Search and Layers views, draggable width, active-icon collapse, and Ctrl+B (Command+B on macOS).
- Normal zoom stays on the current board; automatic linked-map navigation is opt-in. Native distance/unit labels are independent per map and never rescale artwork.
- Headless smoke tests: `godot --headless --path . --script res://tests/smoke.gd`.
- Native framebuffer test: `godot --path . --script res://tests/visual_smoke.gd`. Web UI/IndexedDB validation is in `tests/browser_smoke.py`; setup is documented in the implementation notes.

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

Undo/redo, configurable layers/floors, raster painting, projector output, networking and browser file import/export remain future work. See the implementation notes for the tested scope.
