# DrawInAtlas

**Status: early GDScript editor scaffold, not a full-featured VTT.**

DrawInAtlas is a proposed Godot-based, map-first tabletop editor for West Marches / hexcrawl D&D campaigns. It aims to combine the flexible drawing and collaboration of a whiteboard with the coordinate grids, linked locations, encounter maps, floors, and player presentation needed for a virtual tabletop.

The repository now contains a **Godot 4.7.2 (standard) GDScript-only** editor vertical slice. See [Implementation Notes](docs/IMPLEMENTATION_NOTES.md) for running it and for the features still missing. All persisted raster map artwork and previews must use **WebP** (lossless for editable data, optionally lossy for derived thumbnails). Web export compatibility is a hard requirement.

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
| [Implementation notes](docs/IMPLEMENTATION_NOTES.md) | GDScript scaffold, WebP policy, run/test steps and limits |

## Run and test

- Open in the **Godot 4.7.2 standard** build (not .NET) and run `main.tscn`.
- Paint cells, select a hex, restrict painting to a cell, create rotated battlemaps and enter linked maps from the sample project.
- Save/load uses a provisional `user://drawinatlas_campaign.json` slot. Canonical raster and derived preview image files must be `.webp`.
- Smoke test: `godot --headless --path . --script res://tests/smoke.gd`.
- Project/web-export checks are described in `.github/workflows/godot-check.yml`.

Networking, full layers/floors editing, raster tools, projector multiwindow, rich preview search and Web browser storage UX remain future work.
