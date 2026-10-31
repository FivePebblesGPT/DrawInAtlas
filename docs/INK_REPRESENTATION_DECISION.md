# T-028 — Ink representation audit and approved decision

**Status:** owner decision **approved on 2026-10-31**. This comparison records the decision; editor defaults and UI changes are separate implementation work under [[T-049]]. See [[T-028]] and [[Index]].

## Question and what the code actually owns

The question in [[ManualReview_2026-10-30#Code review|Code review, item 1]] is why `AtlasInkLayer` holds `Array[AtlasStroke]` instead of a raster image. This was not simply a legacy serialization convenience:

| Component / path | Current responsibility and observable cost |
| --- | --- |
| `scripts/artwork/ink_layer.gd`, `stroke.gd` | Each ink object stores board-space `PackedVector2Array` control/sample points, RGBA, width, and metadata for solid polygon, editable wall path, or editable text. Sparse marks need no raster extent. Every object is a `Resource`; object count and samples have allocation/serialization costs. `to_dict` materializes all points for validation/digests/clipboard-related paths. |
| `scripts/interface/canvas.gd` (`_draw_content_layer`, `_draw_stroke`) | Iterates the visible detail group's strokes and issues Godot draw primitives. Round-ended vector strokes may require a generated polygon silhouette; text is drawn from font metadata; filled polygons are shapes. The current path has **no per-object spatial index or viewport culling** beyond layer/detail visibility and text readability. High object/point counts may make redraws expensive. GPU/render time was not measured in this audit. |
| `scripts/interface/artwork_editor.gd`, `editing/commands/stroke_edit.gd` | Adding a stroke clones the *whole* current ink-object array; a guarded edit command retains complete before and after copies; applying/reverting clones again. One gesture is one undo, but cost scales with all strokes and vertices in the target layer, not merely newly changed geometry. Long histories can retain multiple full snapshots. |
| `scripts/editing/stroke_eraser.gd` | An eraser sweep intersects every relevant centerline and cuts it into editable stroke fragments. This is vector-geometry work (path/eraser segment tests and clipping), not alpha subtraction from pixels. Editable wall paths, text and solid polygons are instead removed as whole objects when touched, preserving semantics. Cost grows with geometry and sweep complexity. |
| `scripts/editing/selection_geometry.gd`, `selection.gd` | Selects ink **objects by index**, hit-tests shapes/bounds, and transforms their points/width with a uniform scale. A selection's snapshot is a whole-layer dictionary. The raster branch selects **the entire raster layer**, with an affine transform that leaves pixel bytes unchanged. Pixel-local raster selections do not exist yet. |
| `scripts/artwork/raster_layer.gd`, `raster_chunk.gd`; `editing/raster_brush.gd`, `fill.gd` | Raster is **already a separate first-class artwork layer**: signed 256×256 RGBA8 chunks, resolution in pixels per board unit, and affine placement. A full chunk is 256 KiB of raw RGBA8 before overhead; a partial chunk stores only its valid pixels. Brush visits candidate pixel centers in its bounded footprint, composites once over the pre-gesture image and returns a detached replacement. Fill traverses connected or all *existing* pixels with tolerance and mask checks. These operations quantize to RGBA8 and can be costly for large pixel areas. |
| `scripts/persistence/native_scene.gd`, `layer_codec.gd`; `scripts/artwork/raster_chunk.gd` | Both layer kinds save through the **single-file native PackedScene/Resource** campaign store, not a JSON primary file. Ink objects retain typed Resource fields. Raster chunks retain lossless WebP plus verified RGBA8 hashes; decoded `Image` caches are separate. `to_dict`/`from_dict` still serve snapshot validation, cloning and semantic digests; their cleanup belongs to [[T-029]], not this representation decision. Full-file save rewrites and snapshot validation have costs for either representation. |

`AtlasFloor.strokes` is only a compatibility accessor for its first ink layer; ordered `floor.layers` own artwork. D0–D32 authored-detail groups apply to **both** kinds. Conversion is not required for a continuous board or for zoom/LOD.

## Comparison against actual editor requirements

| Requirement | All-raster | All-vector | Existing typed hybrid |
| --- | --- | --- | --- |
| Brush appearance / transparency | Native pixel compositing; edge quality depends on resolution and brush sampling | Scalable smooth stroke geometry, precise centers and styles; no hardness/texture model | Vector ink for scalable objects and raster painting for alpha-blended pixels. Requires users to understand which layer is active. |
| Eraser | Exact pixel alpha clearing, including soft erasing if later implemented; cannot inherently restore original object topology | Can cut centerlines; editable text/filled shapes/path semantics require special handling | Both supported; their **different semantics must be visible in UI**, not quietly homogenized. |
| Selection / transforms | Pixel regions can be manipulated *if* marquee/mask/copy support is implemented; current code selects entire raster layer and affine-transforms it | Whole-object selection, point changes, scale and text/path editing; expensive without indexing for many objects | Current implementation supports object selection for ink and whole-layer raster placement; pixel-region editing is a future feature, not an existing benefit. |
| Bucket / regions | Contiguous and global RGBA tolerance fill are natural and implemented | Filling arbitrary enclosed paths requires robust planar-topology/region construction, absent here | Raster Bucket + terrain fill already work; vector fill requires discrete authored polygon shapes. |
| Memory | Scales with allocated pixel chunks and any decoded/encoded caches, not object count; each full RGBA8 chunk ~256 KiB before extra copies/textures | Scales with number of objects/points/styles and duplicated history snapshots; sparse marks can be compact | Pays some overhead for both subsystems when used, but does not force pixel allocation for sparse vector maps or force rasterization of editable labels/paths. |
| Undo | Existing raster `AtlasLayerEdit` duplicates the layer collection and chunk images; cost can scale with stored pixels, not just changed tiles | Existing `AtlasStrokeEdit` duplicates full stroke arrays before/after; cost grows with all layer objects/points | Both currently need **incremental delta/snapshot optimization** before claiming memory efficiency for large campaigns. This issue is independent of choosing the representation. |
| Native saving / fidelity | Lossless chunk WebP can preserve exact RGBA8, but cannot recover vector control points or editable text after flattening | Typed objects preserve text and path handles and subpixel positions; rendered pixels depend on zoom/fonts/renderer | Existing native single-file format retains both kinds without re-encoding ink as pixels. Migration to only one kind would be lossy for some capabilities, even if an image appears similar. |

### Real prior size/memory evidence — not a fresh benchmark

`[[Archive/2026-10-30/NATIVE_SAVE_BENCHMARKS]]` measured **Godot 4.8 beta1** synthetic native-save fixtures on a different workstation: the **ink-only** fixture with 2,048 two-point strokes across 32 layers produced a ~38.7 KB compressed production save; save was ~151 ms and load ~42 ms. A **raster-detail** fixture with 2049×1537 RGBA8 pixels, 63 chunks and 40 strokes produced a ~6.89 MB production file; initial save was ~1.07 s and load ~160 ms. They are *different workloads*; those numbers **do not** establish vector-versus-raster speed or quality at equal appearance. The earlier report also notes extra memory for simultaneously encoded and decoded raster payloads, full-file rewrites and independent-content duplication. Do **not** use those beta1 figures as beta2 or browser performance claims.

### Reproducible contract witness

`godot --headless --path . --script res://tests/ink_representation_smoke.gd` verifies the current ownership differences and defensive copies: editable vector object kinds, per-object selection, geometry erasing, separate history snapshots, raster partial chunks, premultiplied-alpha brush, transparent erasing, whole-layer raster selection and independent decoded pixel copies. It is a **semantic test, not a timing/memory benchmark**. Existing `brush_smoke`, `eraser_smoke`, `selection_interactions_smoke`, `storage_smoke`, `text_smoke`, `wall_paths_smoke` and historical benchmark fixtures provide further regression evidence. These tests do not replace human judgment about stroke feel or representative real-map profiling.

## Approved decision — raster-dominant, semantic vector

**Owner approval (2026-10-31):** Raster is the **primary type for ordinary freehand artwork**. Vector is retained primarily for **specialized, individually editable semantic objects**, including wall paths, polygons/shapes, lines, and text. This is **not** an all-raster conversion or a ban on the existing ink representation: the runtime remains typed and supports both `AtlasRasterLayer` and `AtlasInkLayer` on the same board and at every authored detail level.

The policy establishes:

1. **Raster-first authoring:** new boards and normal painting flows should lead to a raster editing target. Pen/brush, pixel eraser and RGBA Bucket should have discoverable raster paths; grid terrain remains its own separate layer type. Where raster chunks do not yet exist, painting must create them safely and the Bucket's finite/eligible area must be clear to users.
2. **Semantic vector objects:** editable paths/walls, line and shape geometry, and text retain their typed control points or metadata. They must not be silently flattened into pixels merely because raster is primary. Existing vector freehand strokes remain supported in stored fixtures and explicitly selected ink layers, but are not the normal suggested authoring route.
3. **Explicit target and visible tool semantics:** switching tools or zoom/LOD must not silently overwrite the user's explicitly selected layer or convert representation. If a tool requires another layer type, make the need clear, offer an understandable path to that layer and preserve the previous editing context. The raster versus vector eraser, fill, selection and transform differences must be discoverable.
4. **No representation migration:** no real user artwork exists to migrate, and this approval does not authorize a legacy-data conversion workflow. Retired battlemat migration work is likewise unnecessary by separate owner direction. Keep native save fidelity and existing regression fixtures intact while changing defaults; do not rewrite saved pixels, vector metadata, or edit history on load.
5. **Performance and fidelity:** raster chunk storage, pixel resolution, alpha, undo memory and browser performance still require measurement on representative content. Raster is the preferred user experience **by design**, not because unmeasured performance superiority has been established. Pixel-region selection is currently missing and should not be claimed as implemented.

### Current implementation versus approved target

The repository already has separately typed lossless chunked raster layers, raster brush/erase/fill, vector semantic objects and native persistence. However, `scripts/campaign/floor.gd` currently constructs terrain + ink for a new floor, `scripts/interface/canvas.gd` starts with `active_layer_id = "ink"`, `scripts/interface/editor.gd::_refresh_layers()` prefers ink as a fallback, and `scripts/interface/artwork_editor.gd::choose_tool()` falls back to ink for Pen/Eraser. These are **implementation gaps**, not evidence that the approval has already been applied.

### Work following this decision

- [[T-049]]: implement and verify raster-first defaults and tool/layer affordances while retaining explicit layer choice, semantic-vector workflows, undo and native saves.
- [[T-018]]: align the layer hierarchy and its user-facing labels/actions with raster as the ordinary painting target; owner usability acceptance stays separate.
- [[T-023]]–[[T-027]]: check the approved raster/semantic-vector separation against Bucket, shapes, paths and text interaction policies before closing those tickets.
- [[T-038]]: continue independent source-only review and owner acceptance; tests cannot substitute for that review.
- Defer any delta-undo, spatial indexing, raster-region selection, or performance optimization to measured, scoped work; none is silently approved as part of the representation decision.

**T-028 acceptance is complete as an architecture decision.** No runtime behavior, persisted schema, or user artwork has been changed by recording it. T-049 and the separate usability reviews remain open.
