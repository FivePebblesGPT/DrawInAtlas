# T-095 — 2026-11-11 spatial Brush tile-key reuse checkpoint

**Scope:** T-095 only. `In Progress`, `manual_review: true`; owner 60px responsiveness gate is **not** approved. T-096 remains independently `Manual Review`.

## Issue and change

`DrawingEditSession._stage_brush_tile()` runs once for each newly accepted swept Brush/Eraser pixel, and formerly allocated a new `"tile_x,tile_y"` text key on every pixel even when adjacent pixel coordinates mapped to the same storage tile. A repeated 60px path visits long horizontal runs inside one tile. This optimized the previously deferred tile-local paint path without changing its source or history semantics: keep the last tile indices and text key in the edit session, recomputing the string only on a tile transition. The source offset remains calculated per pixel. Power-of-two strides use signed shifts/masks; irregular strides compute a nonnegative signed remainder then divide the exact difference, preserving floor division for negative world positions. The cached key selects the source tile, but no pixel is staged until the source resolution succeeds. On a failed source read the cache may already reference the destination tile, which is safe because it holds only the immutable tile's address, not pixel data.

The general-purpose `_stage` path, image storage model, GDExtension ABI, selected Brush geometry, alpha blending, source identity, preview, rollback, selection and publication logic are unchanged. The last-key cache is local to each `DrawingEditSession`; there is no cross-document or cross-gesture sharing.

## Independent verification

`drawing/tests/t095_brush_tile_key_cache_smoke.gd` passed **33,037/33,037** assertions with process exit 0 under Godot `4.8.beta3.official.c51ff06e8`. Eight storage strides **1, 3, 16, 30, 64, 255, 256, 2048** each exercise Brush and Eraser with >32-bit signed anchor offsets. The test compares each accepted cached tile with `DrawingDocument.TILES.tile_key64`, and builds independent expected before/after history from `DrawingDocument.read_pixel`, including true source with transparent hidden RGB, alpha, a selection subtract hole and reverse-direction tile revisits. It compares the detached preview with committed RGBA8, validates unchanged source before commit and checks Undo/Redo. A separate source-read failure injection verifies retry on the same cached key and returning to a prior tile without altered preview/history.

Existing `t095_stage_tile_lookup_smoke.gd` **4,193/4,193**, `t095_brush_deferred_staging_smoke.gd` **492/492** and `brush_coverage_smoke.gd` **32/32** passed after restaging canonical code. All 21 named checks from the previous T-095 headless regression set ultimately passed (the first monolithic run stopped at its execution-window limit after 11; its ten remaining cases were rerun individually with exit code 0 and their expected markers, rather than counted as passing from the truncated run). NativeHard source rollback, native preflight, Hokusai rollback, real preset integration, export cache, mixed-edit retry, tile publication and 60px source geometry are among those cases. The Xvfb released-navigation regression passed **48/48** with process exit 0. A **fresh clean standalone import with the optional native extension removed** independently passed the new **33,037/33,037** oracle and the **7/7** unavailable-native fallback check, both with exit 0. Ticket store validation passed for 96 tickets. The new oracle is registered with a strict success marker in the on-demand T-095 workflow, **without** adding/changing a required 46-step fast desktop CI check ID. Hosted Actions is not tested here.

## Software-only comparison, not owner hardware approval

Harness: `drawing/tests/brush_latency_native.gd`, real `InputEventMouseButton` down/up and 120 `InputEventMouseMotion` per stroke, 5 strokes on one 512×512 document, 60px width at 786% zoom, 980×700 drawing control, Xvfb 1280×900×24, Godot `4.8.beta3.official.c51ff06e8` with `--display-driver x11 --rendering-method gl_compatibility`; Linux software-display path. Stage p50/p95 are summed GDScript paint-call CPU durations per stroke, **not input-to-photon**. Cold first stroke included and four warm strokes used; there is no hardware input replay/driver validation. All runs exited 0 with `T095_NATIVE_PASSED` and 0 failures.

| Sequence / backend | Stage p50 / p95 (ms) | Release→commit p50 / p95 (ms) | Input→stage p95 (ms) | Peak pending |
| --- | ---: | ---: | ---: | ---: |
| Original Legacy (first control) | 172.390 / 191.922 | 55.723 / 83.034 | 133.669 | 23 |
| Cached Legacy (first follow-up) | 162.126 / 171.555 | 53.464 / 58.020 | 98.886 | 17 |
| Cached NativeHard (first pass) | 110.744 / 117.474 | 59.316 / 60.991 | 43.022 | 11 |
| Original NativeHard (reversed control) | 119.404 / 127.209 | 55.865 / 58.097 | 65.710 | 13 |
| Original Legacy (reversed control) | 190.484 / 203.621 | 61.282 / 62.840 | 136.117 | 24 |
| Cached Legacy (second follow-up) | 172.976 / 189.425 | 61.459 / 65.828 | 146.032 | 25 |
| Cached NativeHard (second pass) | 113.526 / 130.279 | 56.255 / 65.539 | 81.982 | 18 |

Original controls used the exact pre-change `addons/drawing/edit_session.gd` from local HEAD, restaged into `drawing/` only; other source, native binary, pointer runner, display and settings were held constant. The optimized session was restored and restaged afterward. These are small-run comparisons with noisy frame scheduling. Both Legacy comparisons showed lower staging p95, but **NativeHard is inconclusive** and renderer/release timings did not uniformly improve. No physical pointer-to-photon measurement, sustained-device throughput guarantee or owner approval is implied.

## Reproduction

From the repository root with Godot beta3 on `PATH` and a Linux X11/Mesa test display:

```bash
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t095_brush_tile_key_cache_smoke.gd
python3 tools/check_godot_model_log.py /path/to/captured.log \
  --marker T095_BRUSH_TILE_KEY_CACHE_PASSED
DRAWING_BRUSH_BACKEND=Legacy xvfb-run -a -s '-screen 0 1280x900x24' \
  godot --display-driver x11 --rendering-method gl_compatibility \
  --path drawing --script res://tests/brush_latency_native.gd
```

Do not mark T-095 Done or infer responsive real-device Brush strokes from these software results. Needed: owner 60px ~3s physical-pointer repro, OS/GPU/window/scaling and build SHA, held-button preview and release backlog, per-phase p50/p95/worst, and explicit hands-on approval. Hosted CI/export and Windows native packaging also remain unverified.
