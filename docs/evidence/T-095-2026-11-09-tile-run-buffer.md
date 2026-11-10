# T-095 — buffered signed-tile native delta preflight (2026-11-09)

**Engineering checkpoint only.** `docs/Tickets/T-095.md` remains `In Progress`,
`manual_review: true`; the owner rejected the earlier responsiveness result.
The target is the existing `sprint/2026-11-07` branch and PR #16. This
change does not supply owner acceptance, a complete native brush editor,
or complete MyPaint parity.

## Bottleneck and implementation

Hokusai's `preset_segments` yields quantized `[x, y, rgba]` triples in
mostly clustered native surface-tile runs. `DrawingEditSession.paint_path_hokusai`
then builds a `Dictionary[String, PackedInt32Array]` of local-offset/pigment
pairs by **Drawing storage tile**, which is a different grid from Hokusai's
64px internal surface. Previously every accepted triple did all of:

1. Fetch the packed array from the Dictionary, returning a packed value.
2. Append the local offset and quantized pigment.
3. Write the packed value back into the Dictionary.

Repeated packed-value retrieval and mutation can trigger copy-on-write
buffer detaches and repeated Dictionary traffic. The new path keeps a single
`PackedInt32Array` for the **current consecutive storage-tile run** and
flushes it only on a tile switch and at the end of preflight. If the native
stream revisits a tile after intervening runs, the already grouped array is
retrieved once and extended in the same input order. This is distinct from
the earlier *tile-key formatting cache*: it avoids copies and lookups for
every `push_back`, not just repeated `"x,y"` formatting.

The native output is still checked for malformed length and safe signed
coordinates. Rectangular clipping, selection holes, opacity scaling, and
overflow-safe local-offset derivation run before any preview writes. Every
required original source tile is resolved before detached staging begins;
failed late lazy reads cannot partially publish the batch. Deferred global
keys, immutable source-alpha blending, per-tile preview generations, single
commit and Undo/Redo are unchanged. No binary/format changes.

## Software-rendered pointer profile

**Test machine**: this Linux container, Godot
`4.8.beta2.official.cafc17a19`, Godot-rust `0.5.5` compiled for 4.7 stable
API, Hokusai `0.3.0`; Xvfb 1280×900×24, OpenGL compatibility, Mesa
software rendering, dummy audio. Headless Godot alone cannot record the
framebuffer. Godot detects a root-run environment warning; the test
still executes normally. GPU/model and physical monitor latency were not
measured.

**Reproduction**: freshly staged standalone `drawing/`, one freshly
launched Godot process per backend, 512×512 image, zoom 7.86, 60px Brush,
five strokes with 120 real synthetic `InputEventMouseMotion` samples each.
The test records changed pixels while the mouse is held, verifies receipt of
every sample, releases, waits for queue drain, checks one document revision
and Undo/Redo, and records per-stroke staging/commit as well as per-frame
CPU compositor/upload work. p95 is nearest-rank over the five strokes;
run 0 is cold and runs 1–4 are warm.

Run order: previous committed `24a2f73` source temporarily in the **staged
project only**, then the new tile-run source re-staged, then Legacy. Canonical
tracked sources were not modified during the control run. An earlier
optimized run gave 208.607ms stage p95 versus the first previous-source run's
240.128ms; the values below are from the later adjacent paired control.

| Metric | Previous | Tile-run buffered | Legacy backend |
|---|---:|---:|---:|
| Stage CPU p50 (ms) | 228.236 | 201.273 | 161.858 |
| **Stage CPU p95 (ms)** | **235.533** | **215.324** | **172.477** |
| Batch CPU p95 (ms) | 9.549 | 8.276 | 4.138 |
| Sample receipt→stage p95 (ms) | 13.455 | 11.906 | 80.352 |
| Frame compositor CPU p95 (ms) | 17.569 | 16.981 | 12.851 |
| Texture upload CPU p95 (ms) | 0.486 | 0.448 | 0.315 |
| Release→commit p95 (ms) | 87.582 | 72.120 | 73.647 |
| Commit CPU p95 (ms) | 87.523 | 72.059 | 73.196 |
| Maximum pending samples | 4 | 4 | 20 |

The paired software stage p95 reduction is **8.58%**, with a 10%–12%
range across the observed medians and early confirmation runs. The apparent
release→commit difference in just five strokes cannot establish a stable
release-latency improvement. Hokusai remains **~1.25× slower** than the
same-run Legacy source stage p95; their pixel output intentionally differs.
A single 60px case does not measure pressure, custom/bitmap brush masks,
long-running sessions, actual input-to-photon timing, or the owner's machine.

### Raw per-stroke witness (CPU ms)

| Backend | Stroke | Stage | Release→commit | Commit | Total compositor CPU | Max queue |
|---|---:|---:|---:|---:|---:|---:|
| Previous 24a2f73 | 0 | 190.261 | 77.743 | 77.474 | 364.484 | 4 |
| Previous 24a2f73 | 1 | 226.482 | 80.523 | 80.437 | 399.467 | 4 |
| Previous 24a2f73 | 2 | 228.236 | 70.728 | 70.665 | 381.019 | 4 |
| Previous 24a2f73 | 3 | 235.533 | 71.222 | 71.163 | 398.513 | 4 |
| Previous 24a2f73 | 4 | 235.228 | 87.582 | 87.523 | 366.905 | 4 |
| Tile-run buffer | 0 | 157.684 | 58.706 | 58.641 | 346.915 | 4 |
| Tile-run buffer | 1 | 199.388 | 70.000 | 69.936 | 389.764 | 4 |
| Tile-run buffer | 2 | 209.636 | 64.718 | 64.657 | 395.944 | 4 |
| Tile-run buffer | 3 | 201.273 | 70.960 | 70.889 | 376.416 | 4 |
| Tile-run buffer | 4 | 215.324 | 72.120 | 72.059 | 362.015 | 4 |
| Legacy control | 0 | 141.648 | 54.598 | 54.257 | 147.808 | 12 |
| Legacy control | 1 | 161.858 | 59.814 | 59.374 | 191.943 | 12 |
| Legacy control | 2 | 158.404 | 63.046 | 62.604 | 182.821 | 12 |
| Legacy control | 3 | 166.266 | 73.647 | 73.196 | 215.415 | 17 |
| Legacy control | 4 | 172.477 | 62.424 | 61.897 | 197.127 | 20 |

## Regression evidence and limitations

- **126/126** `hokusai_bulk_delta_smoke.gd`: independent old per-pixel
  `_stage()` oracle, mixed APIs and rollback, signed >32-bit/negative source
  anchors, selection holes, hidden RGB, repeated/out-of-order native pigment
  changes, preview parity, one atomic commit and Undo/Redo. New case includes
  **4,096** pixels in one 64px source tile plus a later return after visiting
  a second tile, and compares complete source and preview bytes.
- **32/32** `brush_coverage_smoke.gd`; **114,688 RGBA8 comparisons** in
  `brush_blend_math_smoke.gd` (passing standalone blend marker).
- Native-present `native_brush_integration.gd` **30/30** (four real `.myb`
  presets), `stroke_navigation_native.gd` **48/48** (post-release pan/zoom),
  `native_brush_fallback.gd` **6/6**; native-absent clean standalone stage
  and import **6/6**.
- `live_stroke_smoke.gd`, `selection_large_smoke.gd`, `renderer_sparse_layer_smoke.gd`
  **74/74**, and `viewport_preview_index_smoke.gd` pass. Xvfb
  `live_stroke_native.gd` **125/125**, `pixel_boundary_native.gd` **17/17**
  and `viewport_cache_native.gd` **153/153** also pass. The viewport test
  initially failed font-related assertions with stale Godot import state;
  a clean `--editor --import` of the staged real Lato fonts restored 153/153.
  This is not a source-code regression fix. The boundary test emits known
  Godot resource-leak and GL shutdown diagnostics despite zero assertion
  failures; keep that evidence distinct from a clean shutdown claim.
- `python3 -m unittest discover -s tests -p test_t094_godot_model_log.py`
  **24/24**, and fail-closed `check_godot_model_log.py` verification of the
  T-095 source, blend, batch and pointer-run success logs pass.
- `python3 tools/validate_ticket_store.py` validates **96 tickets** and
  review gates. `git diff --check` passes. Hosted CI and the owner's physical
  Windows/Linux display checks have **not** run.

### Still open

- T-095 60px owner-device latency, responsiveness while held, and headroom
  for texture/opacity/pressure brushes. No owner acceptance or approval.
- Compositor/preview texture submission, canonical pixel-key materialization
  during commit and physical input-to-photon measurement remain profile
  targets. Do not silently enable the native backend or reclassify the ticket.
- T-096's separate Manual Review gate is unaffected.
