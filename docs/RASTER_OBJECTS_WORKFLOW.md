# Raster drawing and Objects

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
