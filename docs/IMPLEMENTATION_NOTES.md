# Implementation Scaffolding Notes

**Feature branch scope:** first interactive vertical slice in GDScript. This is not a full editor.

## Technology invariants (required)

- **Language:** GDScript only for project/application code. The .NET project setting was removed.
- **Extensions:** GDExtension may be used later only if it is optional/non-limiting: the base editor and campaign format must remain usable without it, and any extension-dependent feature must have a web-compatible fallback. A native-only GDExtension must never block a Web export.
- **Engine baseline:** Godot **4.7.2 stable**, standard (non-.NET) build; the original 4.8 feature tag was from a development version.
- **Renderer:** Compatibility / WebGL 2.0, suitable for Godot 4 web export.
- **Web template:** single-thread (thread support off) and extension support off by default; no cross-origin isolation requirement for the basic application.
- **Raster storage:** **.webp**. Lossless WebP for editable raster chunks, token images requiring pixel accuracy, and other canonical raster; lossy WebP (proposed quality 0.82) only for explicitly derived previews and thumbnails. Avoid PNG/JPEG output in persistent campaign image assets. SVG is acceptable as source vector icon artwork, not as a raster map storage format.
- **Browser storage:** write to `user://` via `FileAccess` (mapped to IndexedDB in compatible browsers, subject to browser quota/persistence); never assume arbitrary native file paths. Import/export browser file workflows remain future work.
- **No mandatory native threads, external system commands, native window features or filesystem directory assumptions for core functionality.**

Sources: [Godot Image/WebP API](https://docs.godotengine.org/en/stable/classes/class_image.html), [Godot Web export limitations](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html).

## Current code layout

```text
main.tscn                       Root UI scene
scripts/domain/
  atlas_grid.gd                 Square/axial hex grid conversions, polygons
  atlas_floor.gd                Sparse single terrain layer (v1)
  atlas_map_document.gd         Independently editable map + floors + grid
  atlas_map_link.gd             Source anchor and destination camera
  atlas_placement.gd            Rotated battlemap footprint and transform
  atlas_campaign.gd             Map/link/placement graph + sample maps
scripts/services/
  atlas_zoom_gate.gd            Three additional blocked steps
  atlas_webp_store.gd           WebP encode/decode using byte buffers
  atlas_campaign_store.gd       Versioned JSON save/load to user://
scripts/ui/
  atlas_canvas.gd               Canvas renderer, picking, painting input
  atlas_editor.gd               Simple inspector/overview/navigation toolbar
tests/smoke.gd                  Geometry, graph, gate, WebP smoke tests
.github/workflows/             Headless Godot smoke and Web export checks
```

## How to try it

1. Open the project with the **Godot 4.7.2 standard** editor and run `main.tscn` / the project.
2. A sample world hexcrawl and a linked Greyhaven city are available without any files.
3. Pick **Paint cells** and click/drag cells to change terrain. Pick **Select cell** to highlight a hex and optionally enable edit restriction.
4. Double-click the city marker or hover it at max zoom and apply **three additional inward wheel steps** to enter the city.
5. Pick **Drag battlemap**, set the rotation angle (e.g. 37°), and drag over the current map. A new independent encounter map opens automatically.
6. Paint on the child. For **spatial** placements, the parent terrain appears as a translucent read-only underlay. Battlemap placements made directly on **world** maps are symbolic, so they do not show a falsely aligned parent reference.
7. Use **Back** or zoom outward at min zoom with three additional logical wheel steps.
8. Click **Save**; reload from the app's `user://drawinatlas_campaign.json` save slot.

The basic list of all maps doubles as a map index. Rich thumbnail caching, search/tag filtering, hover previews, configurable layers and floors, lasso/clipboard, multiple window projector mode, hosted permissions and painting history are **not yet implemented**.

## Deliberate MVP simplifications / next steps

- Painting writes directly to the sparse terrain dictionary; implement a command bus with undo/redo and layer/floor validation next.
- No raster paint tool yet; `AtlasWebPStore` establishes the persistence format for upcoming raster layers. WebP saving/reading is covered by a smoke test.
- Drawn battlemap rectangles use a fixed 24 parent-document-unit cell pitch for now. Add a size/scale inspector and drag handles.
- A symbolic placement is a discoverable footprint, not physical geometry. Parent reference must use an explicitly selected crop in a future milestone.
- The render loop draws a bounded cell neighborhood; replace with visible-chunk queries before scaling to huge hex worlds.
- Overview is a basic map list and canvas markers/placeable previews. Search tags, recursive navigation, permission-filtered caches and generated thumbnails are deferred.
- The wheel input normalizer accumulates fractional `factor` and emits at most one step per event. Test trackpad behavior and adjust device-specific gesture debounce before calling it production-ready.
- Native projector multi-window is deferred, and browser export requires a **single-window fallback**.
- Save/load is one JSON save slot only (no atomic writes, migration framework, autosave, or browser import/export yet).

## Validation

CI is configured to import scripts, run the domain smoke tests, launch the main scene headlessly, and export a single-threaded Web build. The Web export task requires Godot export templates. Passing an export step demonstrates **build viability**, not full runtime/browser feature parity; browser UI testing remains necessary.
