# T-095 — direct native tile publication (2026-11-09)

**Ticket:** T-095 · **Status:** In Progress · **Manual review:** required and **not approved**.  The owner rejected earlier 60px Brush catch-up. This is a local engineering checkpoint on `sprint/2026-11-07`, not final physical-device acceptance. It does not change the default Legacy Brush or T-096's separate gate.

## Bottleneck and change

Before this patch, native Hokusai pigment export had already been staged as `DrawingEditSession._preview_tiles[tile_key][local_index] = rgba8`, using integer local offsets and original-source compositing. `commit()` still invoked `_materialize_hokusai_preview()`, building *two global* signed-coordinate string-keyed dictionaries (`_before`, `_after`). `DrawingDocument._publish_edit()` then parsed the newly created `"x,y"` strings back to tile coordinates, resolved tiles, cloned their bytes and created the final `DrawingDelta` history. This duplicate coordinate conversion was on the mouse-release critical path.

The new `DrawingDocument._publish_tile_edit()` keeps Hokusai-only batches in signed storage-tile / local-offset form until document publication. It validates every tile key, RGBA8 value, local offset, source tile identity and expected revision; assembles **private detached copies** and exact canonical before/after history maps; only then calls the existing publication/historian routine, now factored as `_install_prepared_edit()`. Both the old global-pixel path and the new native-tile path share the **same** atomic install, dirty regions, save-dirty tracking, revision increment and one Undo/Redo event. The ordinary `_stage` API and all sessions mixing Hokusai with a region/fill/other pixel edit still use the preexisting `_publish_edit()` validation and history semantics. No document schema or native ABI changes.

Failure during preparation publishes nothing. In addition to revision and layer checks, the tile-direct path detects an unexpected source tile *identity* replacement before publication. The session closes on commit success or failure, matching the old path's lifecycle. Neither this check nor the tests can guarantee external modifications through unsupported direct mutation of a live raster tile's internal `_pixels` map.

## Independent correctness evidence

New `drawing/tests/t095_tile_commit_smoke.gd` passes **56/56** assertions on Godot `4.8.beta2.official.cafc17a19`. The original independent `_stage(..., blend=true)` + `_publish_edit` path is the oracle. Three large intersecting batches cover 64px storage tiles, signed anchors outside 32-bit range, overlapping pigments, alpha/hidden RGB, a selection hole and repeat updates. It compares canonical `DrawingDelta.before/after` maps exactly, dirty-region rectangles, preview/commit bytes and Undo/Redo. It also injects a bad offset into a *later* source tile after preflight, a stale revision before commit and a source-tile replacement without revision; every failure keeps the document pixels and history untouched. The earlier 126/126 Hokusai batch/source oracle remains green.

Other selected local runs:

| Test | Result |
|---|---|
| `brush_coverage_smoke.gd` | pass (32-check oracle) |
| `brush_blend_math_smoke.gd` | pass (114,688 RGBA8 comparisons) |
| `hokusai_bulk_delta_smoke.gd` | **126/126** |
| `t095_tile_commit_smoke.gd` | **56/56** |
| `t095_sparse_preview_smoke.gd` | **133/133** |
| `t095_native_export_cache.gd` (pinned native library) | **81/81** |
| `native_brush_integration.gd` | **30/30** |
| `stroke_navigation_native.gd` | **48/48** |
| `live_stroke_native.gd` | **125/125** |
| `pixel_boundary_native.gd` | **17/17** (known post-exit Godot RID/texture leaks remain) |
| `viewport_cache_native.gd` | **153/153**, after clean editor reimport to regenerate fonts' `.ttf.import` sidecars |
| New standalone stage, native manifest & binary removed **before first import** | **56/56** direct-commit source oracle and **6/6** missing-native fallback; no startup errors |
| `tools/validate_ticket_store.py` | 96 valid tickets and manual gates |

The existing **on-demand** `godot-native-t095-brush.yml` now runs the 56-check oracle with `set -euo pipefail` and `check_godot_model_log.py`, and uploads its log. This model test requires **no native binary**, because it uses a deterministic delta provider. No new required fast-CI check ID was added; hosted CI did not run.

## Same-machine software timing (not physical input-to-photon)

Godot 4.8 beta 2, Mesa llvmpipe on Xvfb 1280×900×24, 512×512 Drawing image, **786% zoom, 60px Hokusai**, five strokes with 120 **actual pointer motions** per stroke and four motions between software frames. Source differs only in the two edited GDScript files; unchanged native library and Godot project import are used for both. The old publication path was restored from the prior local commit for the baseline and the optimized sources then restaged and imported. Timings include drawing and document publication as observed by `drawing/tests/brush_latency_native.gd`; `release→commit` here is **CPU/Godot event time**, not photon delivery.

| Metric (p95, 5 strokes unless otherwise noted) | Previous global-key publication | Direct native tile publication | Optimized confirmation |
|---|---:|---:|---:|
| Release → commit | **75.081 ms** | **43.258 ms** | **42.107 ms** |
| Commit CPU | **75.021 ms** | **43.182 ms** | **42.044 ms** |
| Whole gesture staging | **204.169 ms** | **209.405 ms** | **206.029 ms** |
| Per-frame compositor CPU | **16.726 ms** | **17.090 ms** | **16.069 ms** |
| Worst queued input samples | 4 | 4 | 4 |

Release-to-commit p95 improved **42.4%** in the paired baseline/optimized run (75.081→43.258 ms), and the confirmation run was similar (~44% below baseline). Full gesture staging **did not measurably improve**. A separate Legacy control on optimized code measured staging p95 **155.529 ms** and release→commit p95 **60.945 ms**; Hokusai remains ~**1.32× slower** in total CPU staging (206.029/155.529). Software frame submission and cache/upload timing are **not** physical input-to-photon measurements. The five-stroke sample and different brush semantics limit conclusions about sustained strokes, textured brushes and perceived latency.

## Reproduce

```sh
python3 tools/build_drawing_app.py --in-place
/path/to/Godot_v4.8-beta2_linux.x86_64 --headless --editor --path drawing --import --quit
/path/to/Godot_v4.8-beta2_linux.x86_64 --headless --path drawing --script res://tests/t095_tile_commit_smoke.gd
DRAWING_BRUSH_BACKEND=Hokusai xvfb-run -a -s '-screen 0 1280x900x24' \
  /path/to/Godot_v4.8-beta2_linux.x86_64 --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy --path drawing \
  --script res://tests/brush_latency_native.gd
```

For missing-native verification, create a **fresh** standalone `--output` stage, remove `addons/drawing/native/drawing_brush.gdextension` and its binary **before editor import**, then run `t095_tile_commit_smoke.gd` and `native_brush_fallback.gd`. Removing the manifest from an already imported Godot project is not the same test and may leave cached class-registry warnings.

## Remaining blockers

Hokusai's held-stroke staging remains slower than Legacy, and real owner hardware input-to-photon latency, long queued strokes, sustained memory headroom, Windows/Linux native packaging, and hosted CI have not been accepted. The 2026-11-08 owner usability rejection controls; **T-095 stays In Progress, `manual_review: true`**, Legacy remains default, PR #16 stays unmerged, and T-096's separate Manual Review is unchanged.
