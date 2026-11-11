# T-098 — exact detached preview display-tile invalidation (2026-11-11)

**Scope:** only T-098, child of T-095. Independent `manual_review: false`.
The parent T-095 remains `In Progress`, requiring owner's physical-device
60px/96px Brush responsiveness and explicit acceptance. No 100ms performance
claim, PhotoCraft timing equivalence or hosted Actions pass is inferred.

## Identified cause and changed implementation

The existing Canvas retained 128×128 RGBA8 GPU textures, but
`DrawingEditSession.preview_stamps_for_display_tiles()` projected one changed
**256px storage chunk** onto all four 128px display quadrants. When an ordinary
hard Brush changed only one quadrant, a render-frame stamp incorrectly
invalidated the other three textures, invoking `DrawingRenderer._composite_raster()`
for each untouched region. This is a renderer CPU issue separate from T-099's
input draining and T-100's atomic document publication.

The new Canvas-private `preview_display_stamps_for_canvas()` uses precise
changed 128px display keys for ordinary pixel-authored Brush/Eraser edits.
Each changed pixel updates one generation, including negative signed world
coordinates (`global_x >> 7`, arithmetic floor shift). A one-key scanline
cache avoids formatting a string when successive pixels share a display
tile. Previous textures are reused if their exact display stamp is unchanged.
The public storage-tile index and source pixel dictionary formats are
unchanged. Preview patches remain entirely detached until atomic commit.

A missing, stale or incomplete exact index, batch rollback, reconstructed
preview, bulk Hokusai staging, non-128 display stride or more than **4096**
distinct display keys falls back to the conservative original stamp path.
No partial index is returned after overflow. Both the exact key dictionary
and its cached key are released on commit/cancel; the frame display texture
retention still uses the previous `MAX_DISPLAY_TILES=144` limit
(144 × 128 × 128 × 4 = 9 MiB upper bound). The existing 6ms soft drain budget,
color model, selection authorization and edit publication are unchanged.

## Negative control and correctness

In a staged-only copy, changing **only** the Canvas call from
`preview_display_stamps_for_canvas` back to the prior
`preview_stamps_for_display_tiles` produces an intentional **exit 1** with
three failed T098 checks: first-dab redundant quadrant compositing,
second-dab redundant compositing and lost unchanged-texture cache hits.
Restoring the optimized call passes **27/27** headless checks and **29/29**
X11/llvmpipe checks, exit 0 and one strict `T098_PREVIEW_DISPLAY_PASSED`.
The test stages an actual Canvas Brush pointer-down and changes a different
128px quadrant of the *same* 256px source chunk, checking exact generations,
Canvas `tiles_composited`, original GPU texture identity, framebuffer pixel
stability/new pixel visibility, two-layer alpha preview/committed-byte
identity, signed Eraser/cancel, late staging rollback with conservative
fallback, the 4096-key cap and one Undo/Redo publication.

Regression neighbors on Godot `4.8.beta3.official.c51ff06e8` (exit 0):
`brush_coverage_smoke.gd` (T095 independent 32-check RGBA8/selection/layer
oracle); `viewport_preview_index_smoke.gd`; `t095_preview_index_reuse_smoke.gd`;
`viewport_cache_smoke.gd`; `t095_noop_redraw_smoke.gd`;
`t095_frame_phase_window_smoke.gd`; `t095_frame_input_backlog_smoke.gd`;
`native_brush_fallback.gd` (native absent: 7/7; native present: 7/7);
`stroke_navigation_native.gd` (48/48 wheel, toolbar-pan, camera-after-up);
`viewport_cache_native.gd` (real GPU texture, alpha and text); and
`pixel_boundary_native.gd` (signed frame/pixel boundary). An initial isolated
Xvfb viewport-cache failure was traced to Git LFS font pointers; hydrating
the authentic local Lato fonts plus their import metadata made the identical
test pass. The native-present pinned GDExtension also passed
`t095_native_hard_source_atomic.gd` **113/113** and
`t095_native_pigment_atomic.gd` **57/57**. The separate pixel-boundary native
run exits zero but Godot emits shutdown GPU-RID leak diagnostics; it is not
claimed as a strict clean-log pass. The new T-098 graphical log and actual
NativeHard full-canvas log have **no `SCRIPT ERROR:` or leading `ERROR:`**
and pass the T-094 checker.

## Paired 96px × 512×512 real graphical pointer witness

Both variants were staged from canonical source through
`python3 tools/build_drawing_app.py --in-place`. Godot 4.8 beta3,
Xvfb 1280×900×24, Mesa llvmpipe, `--display-driver x11
--rendering-method gl_compatibility --audio-driver Dummy`, one continuous
nine-sweep / 100-input-event 96px red Brush; **two consecutive strokes each
on fresh documents** per candidate, cold then warm in the same engine.
Only the Canvas/edit-session implementation was swapped for the paired
baseline; instrumented test, machine and engine were identical. Engine
input-to-postdraw is *not* a monitor's physical input-to-photon latency.

| Metric | Original cold | Original warm | T-098 cold | T-098 warm |
| --- | ---: | ---: | ---: | ---: |
| Whole stroke → engine post-draw (ms) | 8361.647 | 7747.403 | 6163.965 | 5265.069 |
| Release → document commit (ms) | 8214.627 | 7600.693 | 6004.999 | 5102.345 |
| Preview composite total CPU (ms) | 4428.781 | 4392.962 | 1769.864 | 1699.376 |
| Per-frame compositor CPU p95 (ms) | 54.004 | 51.786 | 19.123 | 18.642 |
| Worst compositor frame CPU (ms) | 93.802 | 81.814 | 23.738 | 28.581 |
| Worst full Canvas draw CPU (ms) | 94.973 | 82.755 | 24.526 | 29.576 |
| Brush staging CPU (ms) | 1277.692 | 1202.429 | 1488.551 | 1335.277 |
| Commit/publication CPU (ms) | 1443.229 | 999.933 | 1711.029 | 1056.223 |
| Preview frames | 158 | 159 | 163 | 160 |
| Drain calls | 160 | 161 | 165 | 162 |
| Retained RGBA texture bytes | 1,048,576 | 1,048,576 | 1,048,576 | 1,048,576 |

All four runs produced four full, byte-exact SHA-256 red 256×256 tiles,
actual framebuffer red center/corners, one canonical stroke/Undo transaction,
valid Redo and exact input accounting; the strict test marker appeared once.
**The composite CPU reduction is ~60%** for both cold and warm runs, although
staging CPU increased slightly from per-pixel stamp tracking and total latency
remains seconds, not 100ms. A real NativeHard 96px run after the change was
5,796.351ms total and 1,700.826ms compositor CPU, exact-red source/framebuffer
and strict marker, exit 0. These are separate backend observations, not a
paired NativeHard speedup claim.

## Reproduce and remaining work

```sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t098_preview_display_cache_smoke.gd
xvfb-run -a -s '-screen 0 1280x900x24' godot --audio-driver Dummy \
  --display-driver x11 --rendering-method gl_compatibility --path drawing \
  --script res://tests/t098_preview_display_cache_smoke.gd
xvfb-run -a -s '-screen 0 1280x900x24' env T095_FULL_CANVAS_RUNS=2 \
  godot --audio-driver Dummy --display-driver x11 \
  --rendering-method gl_compatibility --path drawing \
  --script res://tests/t095_full_canvas_brush_native.gd
python3 tools/check_godot_model_log.py /tmp/t098-preview-display.log \
  --marker T098_PREVIEW_DISPLAY_PASSED
python3 tools/validate_ticket_store.py
```

The non-gating on-demand `.github/workflows/godot-native-t095-brush.yml`
retains the raw regression output and exact marker; required fast CI check
IDs remain 46. Hosted CI is not verified here. Remaining tasks belong to
T-099 (responsive input draining), T-100 (publication throughput), T-101
(optional native backend throughput), and the parent T-095 physical reference
device/owner gate. No manual approval was fabricated.
