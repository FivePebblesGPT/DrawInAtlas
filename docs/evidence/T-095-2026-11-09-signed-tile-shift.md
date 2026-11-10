# T-095 — exact signed power-of-two storage-tile staging (2026-11-09)

**Ticket:** T-095 · **Kanban:** In Progress · **manual_review: true (not accepted)**. This checkpoint belongs to the existing `sprint/2026-11-07` branch and PR #16. The owner rejected earlier 60px Brush latency; the physical acceptance gate remains open. Hokusai remains opt-in, Legacy the default. No new brush features or storage formats are implied.

## Changes and invariant

Before this change, every imported Hokusai delta called `DrawingSignedTiles.floor_div()` for both global coordinates and multiplied back by the storage stride to form a local offset. Those calls are correct for arbitrary strides but expensive across hundreds of thousands of changed pixels. For a positive power-of-two stride, an **arithmetic right shift** computes the mathematical floor quotient even for negative signed 64-bit coordinates, and a bitmask computes the nonnegative local remainder. `DrawingEditSession.paint_path_hokusai()` now computes the shift/mask once per incoming batch, uses them on this common path (including the default 256px storage tiles), and retains the original floor-divide/subtract path for non-power-of-two storage strides. Range preflight, clip/selection filtering, source-tile resolution, color blending, detached previews, transaction publication and history are otherwise untouched. No unsigned or floating-point coordinate conversion is introduced.

## Independent deterministic regression

New `drawing/tests/t095_tile_shift_smoke.gd` passes **422/422** checks on the supplied Godot 4.8 beta 2 runtime. It independently compares shifted quotients/masked remainders against `DrawingSignedTiles.floor_div()` and `posmod()` around signed boundaries outside 32-bit range, negative tile edges and the origin. It then compares Hokusai delta staging against the original `_stage(..., blend=true)` pixel API across storage strides **1, 2, 3, 16, 30, 64, 128, 255, 256 and 2048**; this exercises both optimized and fallback paths. For each stride it compares three overlapping native batches with color/alpha endpoints, selection holes, clipping and tile revisits, including exact detached preview bytes, changed-pixel counts, canonical before/after history, committed bytes and Undo/Redo. Rendering uses a source origin near +2^40 / −2^40. The model provider is deterministic and the oracle runs without the Rust extension.

The on-demand `.github/workflows/godot-native-t095-brush.yml` now runs the independent test using the existing fail-closed Godot log checker, retaining the output as an artifact.

## Paired real-pointer software benchmark

Godot **4.8.beta2.official.cafc17a19**, Linux Xvfb 1280×900×24, Mesa llvmpipe, standalone 512×512 Drawing image, **786% zoom**, **60px Hokusai Brush**, five approximately 3-second strokes with 120 **actual mouse-motion events** each and four events per software frame. Same native library and imported project for both versions; only `addons/drawing/edit_session.gd` was swapped. Measurements are from `drawing/tests/brush_latency_native.gd` and include Godot's CPU staging and commit counters, not physical input-to-photon timing.

| Metric (p95) | Existing floor-divide stage, first | Shift/mask first | Shift/mask confirmation | Existing stage, second control | Shift/mask final |
|---|---:|---:|---:|---:|---:|
| Whole gesture staging | 201.491 ms | 183.443 ms | 181.387 ms | **204.460 ms** | **186.535 ms** |
| Native batch p95 | 8.246 ms | 7.041 ms | 7.041 ms | **8.362 ms** | **7.310 ms** |
| Release→commit p95 | 42.422 ms | 44.358 ms | 41.815 ms | **46.643 ms** | **41.612 ms** |
| Frame composition p95 | 16.486 ms | 15.944 ms | 16.172 ms | **16.967 ms** | **16.743 ms** |
| Max queued samples | 4 | 4 | 4 | 4 | 4 |

The closest control/optimized pair shows approximately **8.8% lower staging p95** (204.460→186.535 ms). Across both control/optimized comparisons, staging improvement is consistent. A same-machine **Legacy** run staged at **167.412 ms p95**, so even after optimization Hokusai remains about **1.11× slower** in CPU staging (186.535/167.412). These runs do not prove hardware responsiveness or a release-to-commit improvement. The five-stroke sample is small, and the native brush behavior differs from the legacy hard-circle output. Do **not** infer parity, sufficient future textured-brush headroom, or acceptance on the owner's GPU/tablet from these measurements.

## Regression and limitations

Local runs after the optimization:

- `t095_tile_shift_smoke.gd`: **422/422**; `hokusai_bulk_delta_smoke.gd`: **126/126**; `t095_tile_commit_smoke.gd`: **56/56**; `t095_sparse_preview_smoke.gd`: **133/133**.
- `brush_coverage_smoke.gd`, `brush_blend_math_smoke.gd`, `selection_large_smoke.gd`, `renderer_sparse_layer_smoke.gd`, `viewport_preview_index_smoke.gd`: passed.
- Xvfb/Mesa `native_brush_integration.gd`: **30/30**; `stroke_navigation_native.gd`: **48/48**; `live_stroke_native.gd`: **125/125**; `pixel_boundary_native.gd`: **17/17**; `viewport_cache_native.gd`: **153/153**; `native_brush_fallback.gd`: **6/6**. Native-boundary tests emit known post-shutdown Godot texture/RID leak diagnostics; these are retained, not treated as clean shutdown.
- A clean editor import preceded the final regression suite. In an independently staged **fresh project with the native manifest and binary removed before first import**, the tile-shift oracle still passes **422/422** and the Legacy fallback **6/6**, without native startup errors. Physical owner device, Windows/macOS export, performance during sustained long or textured strokes, and hosted CI were **not** exercised. Manual owner review remains outstanding.

Reproduce using the pinned Godot binary (or the bundled headless wrapper):

```sh
python3 tools/build_drawing_app.py --in-place
/path/to/Godot_v4.8-beta2_linux.x86_64 --headless --editor --path drawing --import --quit
/path/to/Godot_v4.8-beta2_linux.x86_64 --headless --path drawing --script res://tests/t095_tile_shift_smoke.gd
DRAWING_BRUSH_BACKEND=Hokusai xvfb-run -a -s '-screen 0 1280x900x24' \
  /path/to/Godot_v4.8-beta2_linux.x86_64 --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy --path drawing \
  --script res://tests/brush_latency_native.gd
```

**Exit criteria remain unfulfilled:** owner hardware input-to-photon/60px catch-up and custom-brush headroom, supported export platforms and explicit owner re-acceptance. T-095 stays **In Progress**, `manual_review: true`; T-096 remains independent in **Manual Review**. Do not merge PR #16.
