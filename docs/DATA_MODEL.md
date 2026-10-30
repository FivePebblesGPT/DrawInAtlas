# Campaign Data Model and Persistence

> [!important] Existing representation, pending model decisions
> This describes the implementation, not the revised canvas contract. [[E-002]] and [[E-006]] record the confirmed shared-board/artwork-LOD/local-object direction; [[E-003]] and [[E-SAVE]] track model and persistence cleanup. Existing dictionary helpers are under investigation in [[T-029]]. Completion is tracked in [[Index]].

**Status:** current Resource-backed runtime model and native single-file **`.scn`** saves, locally verified on Godot 4.8-beta1. Embedded Resources are not standalone `.res` user files. The JSON examples farther below illustrate relationships and historical formats, not the physical storage layout.

## Current native checkpoint contract (native v1)

Keep native resource/scene serialization behind `AtlasCampaignStore`. Floor,
overview and editing code operate on typed runtime objects and stable IDs;
they must not infer identity from a resource filename or a node path. Multiple
entrances still reference one independent destination map, including its
explicit floor and arrival camera.

Persist canonical campaign/map/floor/layer/link/placement content. Do not pack
the running editor workspace into a save: its selected floor/layer, camera,
Back history, gesture state and private preview renderers belong to the viewer.
Preview images are derived data, never substitutes for the original artwork.
The data-only save root owns map-document nodes whose embedded Resources supply
the map registry. Map IDs, rather than child order, are canonical; floor/layer
array order remains significant. The binary `.scn` embeds every map and lossless
WebP chunk and uses whole-scene ResourceSaver compression. Native version **1**,
domain validation, exact RGBA8 hashes and a deterministic semantic digest gate
activation. No user artwork sidecars or JSON schema are written inside the file.

`AtlasCampaignStore` stages and verifies candidates, retains the previous
validated generation beside the campaign as `.bak.scn`, and replaces the head.
`.pending.scn` and `.bak.pending.scn` are never automatic recovery candidates.
Only a valid head may rotate into the backup. Failure leaves active work intact;
backup recovery carries diagnostics and requires a new save to clear dirty state.

All raster payloads reconstruct exact RGBA8 bytes including transparent RGB;
the decoded Image is a runtime cache. Repeated loads isolate mutable nested
Resources and Images. Shipped application scripts are permitted external
dependencies; arbitrary external artwork/campaign dependencies are rejected.
Old JSON saves remain untouched, with **no legacy user-save importer**.

Whole-file save/load and eager hydration costs, codec selection AD-10 and
measured fidelity/size/memory trade-offs are in [archived benchmarks](Archive/2026-10-30/NATIVE_SAVE_BENCHMARKS.md).
See [archived native-save report](Archive/2026-10-30/NATIVE_SAVE_IMPLEMENTATION.md) for transaction details and
portability evidence. Browser smoke remains deferred; Windows/macOS replacement
and physical-media power-loss durability are not claimed.

Milestone 6 uses the existing link/placement fields and native format v1 without
adding a schema. `AtlasLinkEdit` atomically changes one source-owned entrance,
its footprint and an optional new independent document. Reference sources,
frozen images, preview crops and traversed-entrance history are viewer state,
not extra Resources in the campaign file. See [linked maps](LINKED_MAPS.md).

### Historical JSON checkpoint / retained in-memory dictionary schema (v6)

Before native saves, the store wrote a checksummed JSON head, `.bak` and immutable
`.assets/<pixel-sha256>.webp` chunks. That user-file path has been retired, not
converted. The following v1–v6 rules still describe the compatibility dictionaries
used by validation, cloning and tests; they are not the native container schema.

Each floor owns an ordered `layers` array (back to front): `TILES` has sparse terrain plus its own geometry, `INK` has vector strokes, and `RASTER` has bounded RGBA8 chunks and pixels-per-board-unit calibration. Layer IDs are stable within a floor; all kinds share name, visibility, lock and opacity fields. Raster metadata contains chunk coordinates, dimensions and hashes, never inline lossy pixel payloads or arbitrary file paths.

Versions 1–3 migrate their single terrain/ink payloads into typed layers; v4 raster layers default to identity placement. V5 records each raster layer's affine `transform` as six finite numbers (basis X, basis Y, origin) and rejects singular transforms. Moving/scaling/rotating an asset does not rewrite chunk pixels or their hashes. The frozen terrain basis is preserved. Old floor `terrain`/`strokes` properties are compatibility views, not duplicate serialized authorities. Full-precision JSON/checksums preserve numeric settings; raster hashes include normalized RGBA8 bytes and dimensions.

V6 adds map `tags` and a link's `source_floor_id`; `target_floor_id` remains
explicit. Missing legacy floor fields resolve to each endpoint map's saved
default. Floor order and `default_floor_id` are persistent metadata, while the
currently viewed floor/camera/layer are workspace state. Renaming/reordering or
choosing a default never rebases artwork, tile geometry or native measurement
units. Missing target map/floor/placement references remain representable for
overview placeholders and source Focus actions.

Clipboard payloads use a separate `drawinatlas.clipboard` v1 envelope, not campaign IDs or file paths. Ink coordinates are relative to the copied bounds; raster chunks carry self-contained verified lossless WebP bytes; tile cells carry explicit grid metadata and relative coordinates. Paste assigns fresh raster layer IDs and does not harmonize native units. Viewer selections, gesture previews and edit scopes remain transient and are never saved as artwork.

Neither the historical checkpoint nor the native replacement implements a full
journal or autosave. Native recovery retains one complete previous generation;
artwork is embedded rather than stored as immutable sidecars.

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

## 2. Historical illustrative JSON package

This earlier proposal is superseded by the single binary `.scn` contract above.
Its following examples describe graph relationships rather than prescribe
the format of new saves.

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
        <floor-id>/<layer-id>/<chunk-coordinate>.webp
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

The earlier layout used JSON metadata and **lossless .webp** raster chunks,
with optional lossy derived thumbnails. Native scene packaging now embeds
metadata Resources and lossless WebP bytes without turning thumbnails into artwork.

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
- Format for sparse tiles, vector geometry and large clipboard payloads (raster chunks are WebP).
- Whether battlemap reference is live by default or a frozen snapshot.
- Which authorization metadata belongs to campaign files versus hosted-session policy.
- How to package/share assets without violating their licenses.

These are implementation experiments, not blockers for defining document and link IDs now.
