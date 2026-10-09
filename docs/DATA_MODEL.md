# Campaign Data Model and Storage Proposal

**Status:** proposed versioned format, not current application serialization. The examples are illustrative and intentionally small. Final schema, migration strategy and language bindings should be tested during the first vertical slice.

## 1. Identity and relationships

All persistent entities have immutable stable IDs (UUID-like strings preferred). Display names are editable and **never** serve as primary foreign keys.

```text
Campaign
  maps: MapDocument[] (registry / lazy loading)
  links: MapLink[] (directed edges; many-to-many)
  placements: BattlemapPlacement[] (parent-owned objects)
  assets: AssetDefinition[]

MapDocument
  grid: GridDefinition
  floors: MapFloor[]
  editorDefaults: optional default camera/preview setup

MapFloor
  orderedLayers: MapLayer[]

MapLayer
  contentType: TILES | RASTER | VECTOR | OBJECTS | TOKENS | ANNOTATIONS
  contentRefs: chunk IDs or object IDs
```

A `MapDocument` may have zero or more incoming links. Do not embed documents recursively inside parents: that would duplicate shared maps and break links with multiple entrances. Treat the campaign as a graph. Floors/layers are **within** a map document, not graph edges.

## 2. Proposed on-disk layout

```text
campaign/
  manifest.json
  links.json
  placements.json
  maps/
    <map-id>/
      map.json
      floors/
        <floor-id>.json
      tile_chunks/
        <floor-id>/<layer-id>/<chunk-coordinate>.bin
      raster_chunks/
        <floor-id>/<layer-id>/<chunk-coordinate>.png
      objects/
        <floor-id>/<layer-id>.json
      previews/
        public.webp
        editor.webp
  assets/
    <asset-id>.<extension>
  journal/
    operations.log
```

Metadata JSON should be human-inspectable; large painting payloads should be chunked. The illustration does not lock down chunk serialization or whether a final project is a directory, ZIP-like package or application bundle.

## 3. Manifest example

```json
{
  "schema_version": 1,
  "campaign_id": "cmp-west-marches",
  "name": "Northern Marches",
  "root_map_ids": ["map-world"],
  "map_ids": ["map-world", "map-greyhaven", "map-watchtower", "map-ambush"],
  "link_index_version": 1
}
```

Root maps are entry points for navigation, not exclusive graph parents.

## 4. Map example

```json
{
  "schema_version": 1,
  "id": "map-world",
  "name": "Northern Marches",
  "kind": "WORLD",
  "tags": ["hexcrawl", "wilderness"],
  "canvas": {
    "kind": "FINITE",
    "bounds": [0, 0, 8192, 8192]
  },
  "grid": {
    "shape": "HEX_POINTY",
    "cell_size": 64.0,
    "cell_size_convention": "CIRCUMRADIUS",
    "origin": [0.0, 0.0],
    "rotation_degrees": 0.0,
    "distance_per_cell": 6.0,
    "distance_unit": "mi",
    "snapping_enabled": true
  },
  "floor_ids": ["floor-ground"],
  "default_floor_id": "floor-ground",
  "default_camera": {"focus": [4096, 4096], "zoom": 1.0},
  "revision": 1
}
```

Here `cell_size` is in map document units. `distance_per_cell` is in game-world units. Its hex radius convention is explicit; a square grid would define `cell_size_convention` as `CELL_SIDE`.

## 5. Floor/layer example

```json
{
  "id": "floor-ground",
  "map_id": "map-world",
  "name": "Ground",
  "elevation_order": 0,
  "layers": [
    {
      "id": "layer-terrain",
      "name": "Terrain",
      "kind": "TILES",
      "visible": true,
      "locked": false,
      "opacity": 1.0,
      "chunk_index": "tile_chunks/floor-ground/layer-terrain/index.json"
    },
    {
      "id": "layer-roads",
      "name": "Roads",
      "kind": "VECTOR",
      "visible": true,
      "locked": false,
      "opacity": 1.0,
      "content": "objects/floor-ground/layer-roads.json"
    }
  ]
}
```

Store layer ordering in the array; use stable layer IDs for tool targeting and undo. Rendering may also use ephemeral overlays for selection, active grid and references, but those are not editable layer records.

## 6. Link example (abstract city)

```json
{
  "id": "link-enter-greyhaven",
  "source_map_id": "map-world",
  "target_map_id": "map-greyhaven",
  "source_anchor": [1280.0, 960.0],
  "source_region": {
    "kind": "HEX_CELL",
    "cell": [6, 4]
  },
  "arrival": {
    "focus": [2048.0, 1024.0],
    "zoom": 1.0,
    "floor_id": "floor-ground"
  },
  "alignment": {"kind": "ABSTRACT"},
  "auto_enter_enabled": true,
  "transition": "ZOOM_CROSSFADE",
  "preview": {"mode": "MANUAL", "asset_id": "asset-city-symbol"}
}
```

The link's source and arrival coordinates belong to two **different** documents. A spatially aligned link can add a validated transform instead of treating them as directly comparable. Different links may point to the same target document and specify different arrival locations.

## 7. Battlemap placement example

```json
{
  "id": "placement-market-ambush",
  "parent_map_id": "map-greyhaven",
  "child_map_id": "map-ambush",
  "link_id": "link-market-ambush",
  "mode": "SPATIAL",
  "origin": [400.0, 640.0],
  "rotation_degrees": 37.0,
  "columns": 20,
  "rows": 15,
  "parent_units_per_cell": 12.0,
  "child_document_units_per_cell": 64.0,
  "child_distance_per_cell": 5.0,
  "child_distance_unit": "ft",
  "reference": {
    "kind": "LIVE_PARENT_CROP",
    "visible_in_editor": true,
    "opacity": 0.35
  }
}
```

`parent_units_per_cell` is a conversion from a local battlemap **grid cell** to parent document units, not a D&D distance. A symbolic placement should instead persist a visually useful marker region and optional chosen crop independently of the child's cell dimensions; in that case no physical mapping is implied.

The battlemap's own authoritative grid and artwork remain in its child map document. The placement's cached grid settings are only creation parameters or a denormalized summary and must be validated against the child to avoid conflicting sources of truth.

## 8. Editing session state is not campaign content

Keep the following in workspace/user-specific preferences or transient runtime state, **not** in persisted global map art:

- Current document, camera, navigation history, zoom-boundary three-step counter.
- Selected cell, optional edit-scope lock, active tool, clipboard.
- Editor-only parent-reference opacity and preview modes (some reference defaults may live in placement metadata).
- GM/projector/client camera, visible panels, follow-GM preference.

Store deliberate persistent document metadata separately: actual layers, floors, terrain, placements, links, tags, permission flags and chosen default previews.

## 9. Indexes, cache keys and migrations

- Maintain indices for incoming/outgoing links, source-region hits, map names/tags and descendant discovery. Indexes can be rebuilt; they should not be sole copies of user data.
- Sparse chunk addresses should use stable (x, y) chunk coordinates; define behavior for negative coordinates if supporting infinite canvases.
- Previews are derived/cache content, keyed by map revision, crop, floor, layer visibility, and authorization scope; never overwrite canonical art with a thumbnail.
- Save metadata and dirty chunks consistently (temp/write/replace or transactional manifest), supporting interruption recovery.
- Increment `schema_version` when serialized meaning changes; implement migrations and round-trip tests.
- Enforce referential integrity: missing target maps should display broken-link placeholders and repair actions, not crash or silently delete links.
- Handle orphan maps explicitly; a map without incoming links can still be found in campaign search and linked later.

## 10. Unresolved schema details

- Best chunk size (initial trial: 256 or 512 pixels/cells depending on layer type).
- Format for sparse tiles, vector geometry and large clipboard payloads.
- Whether battlemap reference is live by default or a frozen snapshot.
- Which authorization metadata belongs to campaign files versus hosted-session policy.
- How to package/share assets without violating their licenses.

These are implementation experiments, not blockers for defining document and link IDs now.
