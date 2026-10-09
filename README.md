# DrawInAtlas

**Status: concept and architecture design; no editor features implemented yet.**

DrawInAtlas is a proposed Godot-based, map-first tabletop editor for West Marches / hexcrawl D&D campaigns. It aims to combine the flexible drawing and collaboration of a whiteboard with the coordinate grids, linked locations, encounter maps, floors, and player presentation needed for a virtual tabletop.

The repository currently contains a minimal Godot 4.8 project. The documents below describe **planned behavior and recommended architecture**, not completed application functionality.

## Product principles

- **One editable map at a time.** Other maps may be visible only as read-only previews or reference underlays.
- **Independent map documents connected by links.** The campaign is a graph, not a mandatory geographic tree.
- **Hybrid semantic zoom.** Ordinary wheel input zooms the current map; crossing a map boundary requires three additional logical wheel steps before automatic navigation.
- **Arbitrary battlemaps.** Drag and rotate a square-grid footprint on any map, then edit the battlemap in its own workspace.
- **Different grids, different scales.** World hexes, regional hexes, gridless city drawings, and 5-foot battle grids need not align.
- **Projector-first, multiplayer-ready.** GM editing and player presentation are separate views over shared campaign data.

## Documentation

| Document | Purpose |
| --- | --- |
| [Product design](docs/PRODUCT_DESIGN.md) | Goals, feature inventory, user experience and acceptance criteria |
| [Architecture](docs/ARCHITECTURE.md) | Modules, runtime boundaries, commands, rendering, persistence and permissions |
| [Maps and grids](docs/MAPS_AND_GRIDS.md) | Map/floor/layer semantics, rotated battlemaps, geometry and tile-edit lock |
| [Semantic zoom and previews](docs/SEMANTIC_ZOOM.md) | Navigation, exact three-step buffer, cross-map references and discovery |
| [Data model and storage](docs/DATA_MODEL.md) | Proposed serialized shapes, stable IDs, indexing and migrations |
| [Implementation plan](docs/IMPLEMENTATION_PLAN.md) | Vertical slices, priorities, risks and test plan |

## Development state

- Existing Godot project: `project.godot`
- Existing minimal scene: `main.tscn`
- No editing, campaign-file, or networking implementation is asserted by these documents.

All JSON examples, API shapes, and module names are **proposals** to evolve through implementation. See the [implementation plan](docs/IMPLEMENTATION_PLAN.md) for the first testable slice.
