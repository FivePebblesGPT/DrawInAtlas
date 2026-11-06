# Atlas-owned world/detail mapping — T-061

**Implemented:** 2026-11-02. **Scope:** stable Atlas mapping and native empty-detail indication; T-055 owns integration of the shared Drawing renderer into Atlas's main canvas, and T-066 owns atomic multi-file campaign publication.

## Hierarchy and identity

`AtlasDrawingRegistry.attach_campaign(campaign)` projects **Map → Floor group → Detail group → generic Drawing layers**, preserving the campaign's ordered floor IDs and names. One detail group has **exactly one opaque DrawingDocument ID** for `(map_id, floor_id, Dn)`, with D0 initialized logically for each floor. `ensure_detail` creates additional logical groups D1–D32. Repeating resolution, renaming or reordering a floor cannot change its ID. A deleted floor's record is temporarily retained in memory for undo but is not projected or exported while absent. The `projection(map_id)` result provides floor/detail visibility, independent density, stable document identity, visible root layer IDs and a `blank` bit; callers retrieve the full nested layer tree through the generic DrawingDocument API.

`document_at(map, floor, level)` is lazy by default and returns no live document for unmaterialized groups; `document_at(..., true)` materializes the document with its registered stride and density but never allocates a raster tile. `begin_world_gesture` resolves a **captured** D-level/layer and 64-bit pixel anchor before opening a DrawingEditSession. Presentation/zoom changes cannot redirect that gesture. Hidden group edits are rejected. Atlas owns global history; materialized documents select external history. An empty layer does not make a detail authored. `render_detail` and `render_detail_at` return transparent, bounded frames for absent/hidden artwork **without loading D0 or allocating a D1 tile**. The latter accepts 64-bit signed pixel anchors plus a small camera-local viewport.

Object Assets are not map-background DrawingDocuments. `visible_placements(library, map, floor, detail)` explicitly filters linked, visible, non-NULL instances by **their own D-level**; a D0 instance does not appear at an empty D1 unless separately placed there. Object-local transforms are applied to camera-relative positions without moving the map's world frame.

## Exact world/pixel and camera rules

- The common map-world frame is signed integer **1,024 ticks/world unit**. This scale is now fixed for the T-061 mapping contract. Supported absolute tick anchors are bounded to **4,000,000,000,000,000** (about 3.9 trillion world units). There is no per-hex, per-floor, or per-detail origin reset.
- Each detail records an explicit positive rational `num/den` pixels/world unit. Engineering default Dn is `2^min(n,10)` (D0=1, D1=2, D32=1024); this is configurable **before artwork is committed** and is not a statement that all high-detail artwork must have exponential density. A density change after a content commit returns `RESAMPLE_REQUIRED` rather than silently translating pixels.
- Pixel index is `floor(world_ticks * num / (1024 * den))`; negative values floor toward negative infinity. `AtlasWorldSpace` computes this by signed integer quotient/remainder without multiplying the entire enormous world anchor. Results are bounded to ±2^60 document pixels. Chunk stride is still per-document, never frozen to 256 by this ticket (T-067 benchmarks 256/512/1024/2048).
- Camera and object-placement APIs first **subtract signed tick anchors** then convert the small offset to Vector2 for rendering/transform. The core Drawing renderer now handles 64-bit signed pixel anchors without truncating them through Vector2i. Rendering text at remote signed positions currently returns an explicit bounded `TEXT_VIEW_RANGE` error, rather than wrapping 32-bit text-layout rectangles; full far-world text shaping belongs to subsequent rendering integration.
- Grid snapping can use `AtlasWorldSpace.snap_ticks` on the same map frame; grid/entrance/navigation overlays remain Atlas-owned and render on blank detail. T-061 adds `D1 · empty`-style status to the existing native Atlas layer panel and preserves its return-to-editing affordance. This panel still displays the **legacy native artwork tree** until T-055 replaces its source with the registry projection; it must not be treated as proof that the new core is already composited in the main Atlas canvas.

## Logical persistence boundary and tests

`export_index()` is a versioned, format-neutral, JSON-safe mapping index, and `from_index(index, campaign)` validates map/floor/document uniqueness, D0 existence, ordering, per-document density, stride, IDs and visibility. It accepts only finite integral JSON numeric fields; duplicate IDs, malformed detail levels and incompatible opened documents fail closed. It is **not yet the production save format**. T-066 will publish the campaign, sibling `Drawings/` manifests/chunks, `Objects/` and fonts as one crash-safe generation. The T-061 combined save test explicitly writes a temporary campaign `.scn`, an index `.json`, an exact `.drawing` file and Object Asset data side by side, then reloads them to verify stable identities and far-world bytes. The fixture does not claim atomic publication/recovery.

Verification commands:

```bash
# Headless functional witness (125 checks at initial completion)
godot --headless --path . --script res://tests/drawing_world_mapping_smoke.gd
# Native software framebuffer witness, with grid and entrance hit-testing
xvfb-run -a godot --display-driver x11 --audio-driver Dummy \
  --rendering-method gl_compatibility --path . \
  --script res://tests/drawing_world_visual.gd
# Existing Atlas/Drawing regression suites must also stay green.
python3 tools/validate_ticket_store.py
python3 tests/check_explicit_types.py
```

**Deliberately deferred:** wiring all Atlas paint/pan/preview/entrance events into the shared Drawing viewer (T-055), data migration from the legacy native layer tree (no historical-user-save migration requirement), production layout and atomic recovery (T-066), tile benchmarking (T-067), and owner-facing UX review (T-056/T-059).
