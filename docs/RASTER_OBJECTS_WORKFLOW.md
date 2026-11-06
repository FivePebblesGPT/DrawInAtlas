# Raster drawing and reusable Object Assets

## Current Drawing/Atlas boundary — T-074 (2026-11-02)

**Authority:** the [owner-approved Drawing/Atlas decisions](DECISIONS_DRAWING_ATLAS_2026-11-01.md), the [Object Assets workflow](OBJECT_ASSETS_WORKFLOW.md), the [portable campaign storage contract](DRAWING_STORAGE_CONTRACT.md), and the tested implementation in `addons/drawing/` and `scripts/objects/`. The material under **Historical raster/Objects prototype** below describes the former single-project editor; it is not the canonical model for new authored content.

- **Background artwork:** Atlas owns an *internal* `DrawingDocument` for each `(map_id, floor_id, detail_id)`. Those documents are represented by sparse manifests/chunks beneath sibling `Drawings/` and the Layers hierarchy; they are **not** independently opened user tabs or Object Assets. Missing higher-detail artwork stays blank rather than inheriting D0 pixels ([T-061](Tickets/T-061.md), [T-066](Tickets/T-066.md)).
- **Reusable source artwork:** `AtlasObjectLibrary` publishes **versioned Object Assets** under sibling `Objects/<asset-id>/vNNNNNN.drawing`. Each source is edited using the **same canonical Drawing engine** through a dedicated Object Editor tab; there is no duplicate raster engine or whole-map source link ([T-060](Tickets/T-060.md), [T-062](Tickets/T-062.md)).
- **Placements:** each `AtlasObjectInstance` has its own immutable `instance_id` and generation token, a `source_id`, target map/floor/detail, affine transform, visibility and revision. Moving or rotating an instance changes its placement **without editing its source**. Multiple instances can link to one published source across maps/details ([T-055](Tickets/T-055.md)).
- **Publication:** Object Editor changes are **private drafts** until **Save** publishes a new immutable version of the same source. Linked instances show the last published revision during edits and refresh **only after Save**. **Save As through an Atlas instance** creates a fresh source Variant B and rebinds **only the captured originating instance**; independent Save As creates B with no Atlas rebind. Undo of the bound Save As restores the old link **but leaves B saved**; redo uses B's existing ID. See the [worked lifecycle](OBJECT_ASSETS_WORKFLOW.md#worked-example-castle-a-variant-b-and-broken-links).
- **Deletion / broken references:** the registry implements `delete_asset(asset_id, "cancel" | "remove" | "null")`. `"remove"` deletes linked placement records, `"null"` retains stable placement IDs/transforms/source keys as **selectable, bounded `NULL` placeholders**, and `"cancel"` makes no change. A missing or corrupt source also resolves to NULL, never an arbitrary same-named replacement. The **three-choice dialog, visible repair/relink affordances, and Asset Browser dock are not implemented**; they are T-065 ([Object Assets workflow](OBJECT_ASSETS_WORKFLOW.md#deletion-null-and-explicit-repair)).
- **Not yet implemented:** nested Object Asset references (parent/child transforms, direct/indirect cycle rejection and transitive cache invalidation) belong to **T-064**. UI completion and owner hands-on acceptance remain **T-065 / T-059**, respectively. Neither the existence of a generic `OBJECTS` layer nor legacy embedded image props proves nested linking is implemented.

**Portable project layout:** Atlas's logical campaign path `Campaign.scn` is a compatibility input, *not* the authoritative saved file. `Campaign.atlas.json` points to immutable generations, which include the Object Asset/instance snapshot. Sibling `Drawings/`, `Objects/` and licensed `Fonts/` travel with the campaign; the old `.scn` single-file invariant no longer applies. Consult [T-066's storage format](DRAWING_STORAGE_CONTRACT.md) before hand-editing files.

## Historical raster/Objects prototype — not the current Drawing engine

The following October-era rules and legacy resources remain useful for old tests and the former editor. They must **not** be used to infer support in standalone Drawing or the canonical Atlas main canvas. The first section's tool routing/density assertions describe design intent from the earlier prototype, not blanket acceptance of the new program's feature inventory.


The owner's 2026-10-31 clarification supersedes the former mixed Ink drawing
workflow: ordinary artwork is raster, including lines and shapes. Independently
editable/movable semantic items belong to designated Objects layers.

| Tools | Target | Stored result |
| --- | --- | --- |
| Brush, Eraser, Fill | Raster | RGBA pixels |
| Line, Rectangle, Ellipse, Polygon | Raster | Outlined or filled pixels |
| Wall Path, Text | Objects | Editable geometry/text |
| Select, Move | Objects | Whole-object selection/transforms |
| Place image / native image paste | Objects | Independently placed lossless image prop |
| Select grid cell | Grid | Session-only edit mask |

Choosing a tool preserves a compatible editable target in the displayed detail
group, otherwise chooses one of that type or creates it through history. It does
not depend on remembering which layer type supports a tool. Selecting a layer
also switches an incompatible tool to Brush or Select Objects. Zoom alone never
redirects an in-progress gesture.

A new floor/board starts with an empty, **allocated-on-first-stroke** raster
layer and a separate Objects layer; the default editing target is Raster.
Bucket matches pixels **inside already allocated raster chunks only**. It
cannot create a region from an otherwise blank canvas or fill the infinite
transparent background. Transparent pixels *inside* allocated chunks remain
eligible. The inspector explains this when Fill is selected.

## Resolution and edges

Painting layers start at **4 px per board unit**, quadrupling width and height
relative to the former 1 px/unit default. The grid and brush widths remain in
board units. Low-density rasters selected for painting are upgraded through an
undoable layer snapshot: pixels are replicated with nearest-neighbor sampling,
chunk coordinates/density increase together, and document size/transform stay
unchanged. Imported images retain their original encoded image pixels; props
are initially placed at the same 4 px/unit density.

Artwork textures use nearest filtering. A hard source-pixel edge consequently
stays sharp when enlarged instead of becoming a bilinear fade across several
screen pixels. Source transparency and layer opacity remain separate.

## Object storage and persistence

`AtlasObjectsLayer` is the current layer Resource and uses the `OBJECTS`
discriminator. Its ordered object records reuse the existing `AtlasStroke`
geometry/text resource. Image props add embedded lossless WebP, original image
dimensions and rotation; their anchor and display width are in board units.
Move/scale/rotate changes placement, not the embedded pixel bytes. Clipboard,
cell-mask eligibility and native saves preserve these fields.

`AtlasInkLayer` is a deprecated subclass retained solely to deserialize prototype
resources and exercise legacy storage fixtures. New UI layers and drawing tools
never create it. Prototype vector records remain readable; they are not a second
freehand authoring workflow.

## Transparency on focus loss

The retained-rendering optimization originally released cached `ImageTexture`s
on cancellation without invalidating the draw commands that referenced their
GPU RIDs. Losing focus calls cancellation and exposed missing/wrong alpha.
Cache release now invalidates affected drawers, and preview textures use a
separate short-lived cache. Cancelling/focus loss keeps committed textures alive;
only transient preview textures are discarded. Focus changes do not alter stored
alpha or layer opacity.

## Regression checks

- `tests/raster_objects_smoke.gd`: tool routing, all raster shapes, walls/text,
  image props, transforms, native roundtrip and density upgrades.
- `tests/raster_rendering_visual.gd`: exact enlarged hard edges and pixel-stable
  raster/Objects transparency through focus-exit and focus-enter callbacks.
- `tests/drawing_performance_visual.gd`: high-density one-cell scribble, every
  between-frame sample, stable incremental preview cost and source-over alpha.
- Brush, layer UI and hierarchy suites cover surrounding editing/history flows.
