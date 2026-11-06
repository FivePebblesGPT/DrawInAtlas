# Campaign Data Model and Persistence

> [!important] Current contract (2026-11-02)
> The approved architecture is [[DECISIONS_DRAWING_ATLAS_2026-11-01]]; API/lifecycle ownership is [ADR](ADR_DRAWING_DOCUMENT_CONTRACT.md), [map/world registry](DRAWING_WORLD_MAPPING.md), [object sources](../scripts/objects/README.md) and [T-066 storage](DRAWING_STORAGE_CONTRACT.md). Earlier single-file `.scn` formats and the examples in the historical section below are **not** the present campaign Save contract.

## Current typed model and identity

| Authority | Identity and content | Implemented owner |
| --- | --- | --- |
| Atlas campaign | Stable map IDs, map links/entrances, floor metadata, grids, tokens/fog and navigation | `scripts/campaign/` and `scripts/navigation/` |
| Drawing registry | Unique internal `(map_id, floor_id, detail_id)` → stable `DrawingDocument` ID; per-detail rational density and persisted tile stride | `scripts/campaign/drawing_registry.gd` |
| Drawing document | Generic ordered groups/layers, sparse signed RGBA8 tiles, editable text and semantic elements, edit revisions/deltas | `addons/drawing/`; **no Atlas map/floor/grid subclasses** |
| Object source | Stable asset ID, independent versioned `.drawing` source, published revision | `scripts/objects/object_library.gd` and `Objects/` |
| Object instance | Independent instance ID, source asset ID, Atlas map/detail placement, transform and metadata | `scripts/objects/object_instance.gd` |
| Atlas history | Global committed operations with originating map/floor/detail, selection/mode context | `scripts/editing/history.gd` + Drawing history coordinator |

**Option B** is the accepted map model: *Map → Floor group → Detail group → Layers*. Every D-level in one map uses shared signed world coordinates but may have its own rational pixel density. One floor may have many **internal** DrawingDocuments (one per D-level); an empty higher detail has no authored D0 underlay and need not allocate any tile data. These internal documents are not user-facing files/tabs. An ordinary standalone Drawing document and an Object Editor source document use the same generic Drawing package without an Atlas campaign. Grids, entrance overlays and map links remain Atlas metadata, never painted terrain-cell or floor-specific Drawing types.

`AtlasMapDocument` and `AtlasFloor` still exist as Atlas map/navigation metadata and as legacy native scene fields. `AtlasRasterLayer`/`AtlasInkLayer` and the `AtlasCampaignStore` native `.scn` codec are compatibility and regression-test paths, **not** a claim that the canonical Painting tool writes into those legacy layers. The removed palette-cell `AtlasTerrainLayer` and `TILES` discriminator are not supported artwork authoring targets. No per-hex or recursively parent-owned drawing document graph exists.

## Current portable project format (T-066)

```text
Project/
  Campaign.atlas.json            current atomically published root pointer
  Campaign.atlas.bak.json        independently checked previous root pointer
  Drawings/
    generations/<generation-id>/generation.json   generation index
    generations/<generation-id>/campaign.scn       Atlas-native metadata, not all raster pixels
    generations/<generation-id>/registry.json      map/floor/detail -> DrawingDocument
    generations/<generation-id>/objects.json       linked instances + version refs
    manifests/<document-id>/<hash>.json            immutable sparse layer/tree manifest
    chunks/<prefix>/<digest>.zst                   compressed straight RGBA8 pixels
  Objects/<asset-id>/vNNNNNN.drawing               immutable published source versions
  Fonts/<licensed-font-id>.ttf
  Fonts/OFL-1.1.txt
```

The editor may accept a `Campaign.scn` logical path when invoking Save, but its **authoritative result** is the `.atlas.json` root and referenced versioned project directory. It validates relative paths, hashes, metadata and source/font files before promoting a root generation, retains a previous valid root for recovery and lazily decodes sparse raster tiles. Exact RGBA8 includes hidden RGB behind zero alpha; signed tile addresses are preserved even beyond JSON float precision using decimal strings. Old `.scn` single-file saves remain a historical codec; there is **no historical user-save migration requirement**. Copy the complete enclosing project directory, not only a root pointer. Atomic rename tests are not a laboratory guarantee about power failure on every filesystem.

**Unfixed optimization choices:** the existing per-document tile stride is versioned; T-067 measured 256, 512, 1024, 2048 and recommends **512 as a future default**, but current files are not automatically retiled. Per-file compressed blobs are deployed; immutable indexed packs are a recommendation, **not** a shipped writer. The optimized GDScript compositor is implemented; T-068 native backend selection remains In Progress. See [storage benchmark](DRAWING_CHUNK_GEOMETRY_BENCHMARK.md) and [CPU benchmark](DRAWING_CPU_RASTER_BENCHMARK.md).

## Runtime session and history boundaries

Viewer camera/zoom, preview-cache images, current tool/selection and navigation-only events are not canonical artwork. Atlas's global undo restores originating map/floor/detail and valid selection/mode without changing zoom; standalone Drawing has independent local undo. Selection-only history is optional and OFF by default. Object Editor drafts do not update published sources until Save; Save As from a captured instance produces a new source and a single-instance binding change, retaining the new source on undo. See [T-054](Tickets/T-054.md), [T-060](Tickets/T-060.md) and [T-062](Tickets/T-062.md).

**Pending rather than approved:** owner privacy policy T-039, independent T-038/T-056 acceptance, nested Object Assets T-064, Asset Browser T-065, and production GPU/native work T-057/T-068. Atlas-only features must not be inferred from generic `DrawingDocument` metadata.

## Historical conceptual schemas (not supported runtime formats)

The following early sketches predate current generation-based saving, the Drawing/Atlas separation, and the removal of battlemats
and palette-cell terrain artwork. They are retained for design history only.
`TILES`, `BattlemapPlacement` and other examples below must **not** be used
as current API or persistence documentation.

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

This early JSON layout and the later single-file `.scn` checkpoint are both superseded by the versioned multi-file campaign-generation contract described above.
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
with optional lossy derived thumbnails. The intermediate native scene package embedded metadata Resources and lossless WebP bytes. Current T-066 generations instead store sparse verified `.zst` chunks with manifests; the following example is not a supported layout.

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

Store deliberate persistent document metadata separately: actual raster/ink layers, floors, placements, links, tags, permission flags and chosen default previews.

## 9. Indexes, cache keys and migrations

- Maintain indices for incoming/outgoing links, source-region hits, map names/tags and descendant discovery. Indexes can be rebuilt; they should not be sole copies of user data.
- Sparse chunk addresses should use stable (x, y) chunk coordinates; define behavior for negative coordinates if supporting infinite canvases.
- Previews are derived/cache content, keyed by map revision, crop, floor, layer visibility, and authorization scope; never overwrite canonical art with a thumbnail.
- Save metadata and dirty chunks consistently (temp/write/replace or transactional manifest), supporting interruption recovery.
- Increment `schema_version` when serialized meaning changes; implement migrations and round-trip tests.
- Enforce referential integrity: missing target maps should display broken-link placeholders and repair actions, not crash or silently delete links.
- Handle orphan maps explicitly; a map without incoming links can still be found in campaign search and linked later.

## 10. Historical open questions (resolved or superseded where noted)

- Original tile-size question: T-067 benchmarked 256/512/1024/2048 and recommends 512 for **future** documents; existing manifests keep their recorded stride.
- Original codec question: T-066 now uses sparse `.zst` chunks and checked manifests. The older native WebP codec remains for compatibility/tests.
- Whether battlemap reference is live by default or a frozen snapshot.
- Which authorization metadata belongs to campaign files versus hosted-session policy.
- Assets/fonts: T-066 records Object source refs and legally redistributable font bytes/licenses in the project; broader asset governance is still a separate decision.

These are implementation experiments, not blockers for defining document and link IDs now.


## GM fog (T-042 engineering checkpoint)

A floor additionally owns `fog_enabled: bool` and ordered `fog_regions:
Array[AtlasFogRegion]`. Each region is a finite board-space `Rect2` and a
reveal/hide operation; latest covering operation wins. This state is shared by
all authored detail levels on that floor, independent of layers and tokens.
Legacy saves default to fog disabled. The native scene validator/digest checks
that the complete operation list is bounded and well-formed. The isolated
player projection removes hidden raster pixels and disallows semantic-object
grants when fog is active; this is not an approved production publication policy.
