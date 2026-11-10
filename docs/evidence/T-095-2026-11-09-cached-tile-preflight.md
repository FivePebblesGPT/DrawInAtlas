# T-095 — cached signed-tile preflight and transparent/opaque RGBA8 fast paths (2026-11-09)

**Scope:** another **engineering checkpoint**, not an owner usability pass or
closure. Target branch `sprint/2026-11-07`, existing PR #16. Canonical ticket
frontmatter remains `status: "In Progress"`, `manual_review: true`.

## Problem and change

After tile-local history staging (`10b64fa`) and allocation-free blending
(`a7896d1`), the 60px Hokusai path still formatted the *same* 64-bit storage
key for every changed pigment pixel. A 120-motion stroke reported roughly
115,000 native pigment updates, even though neighboring updates often lie in
one document storage tile. Preflight also allocated `Vector2i(x,y)` for the
ordinary rectangular clip check.

`DrawingEditSession.paint_path_hokusai()` now calculates signed integer tile
coordinates, reuses the last formatted tile key while the coordinates are
unchanged, and obtains local offsets by subtracting the signed tile origin.
The clip check compares primitive x/y coordinates against the same half-open
`Rect2i` bounds without allocating a `Vector2i`; selection masks still use
`selection.allows(Vector2i(...))`. Preflight **continues to validate every
native coordinate before mutating any preview**; failed lazy source reads
still reject the entire batch, and canonical document/history storage is
unchanged. Cache hits do not bypass the signed tile-coordinate calculation,
so a return to a previous tile cannot be misclassified as part of the last
one. Native Hokusai's 64px raster tiles are distinct from Drawing's (normally
256px) sparse storage tiles.

The shared RGBA8 source-over blend now also returns normalized source bytes
early when source alpha is fully opaque or destination alpha is zero. Source
alpha zero still returns the destination, **including hidden RGB**. Partial
alpha-over-partial-alpha retains the previous scalar float arithmetic and
rounding. Negative signed `PackedInt32` pigments are masked to RGBA8 in the
fast path. This optimization is shared by raster editing and rendering; it
must be guarded by the independent old-equation oracle.

## Same-machine real Brush pointer witness

Godot `4.8.beta2.official.cafc17a19` with godot-rust 0.5.5/Hokusai 0.3.0,
Debian Linux, Xvfb `1280x900x24`, Mesa software GL compatibility renderer,
Dummy audio. Fresh Godot process per run; unmodified `brush_latency_native.gd`
feeds **five 60px strokes**, 120 actual `InputEventMouseMotion`s per stroke,
786% zoom, a 512×512 image, four samples per frame. A held-button framebuffer
change, every sample, single document commit and Undo/Redo are asserted. First
stroke is cold; remaining four are warm. Timings are CPU/frame callbacks,
**not** physical input-to-photon latency.

The control run temporarily used the *previous committed*
`addons/drawing/edit_session.gd` (`a7896d1`) in the standalone staged project
without changing other sources. Run order: optimized initial → previous
control → optimized confirmation → optimized Legacy. The previous file was
restored after control. Nearest-rank p95s for the five strokes:

| Metric | Previous `a7896d1` | Optimized confirmation | Optimized Legacy |
|---|---:|---:|---:|
| Gesture staging CPU p50 (ms) | 272.787 | 225.041 | 155.076 |
| **Gesture staging CPU p95 (ms)** | **275.158** | **239.448** | **162.737** |
| Batch CPU p95 (ms) | 11.262 | 9.152 | 4.036 |
| Frame compositor CPU p95 (ms) | 21.848 | 16.808 | 12.790 |
| Release→commit p95 (ms) | 97.831 | 75.785 | 66.027 |
| Commit CPU p95 (ms) | 97.715 | 75.726 | 65.613 |
| Max queued motions | 4 | 4 | 19 |
| Native pigment pixels per stroke | ~115k–118k | same | n/a |

The optimization reduces measured Hokusai stage p95 **~13.0%** and frame
compositor CPU p95 **~23.1%** in this paired run. The release difference is
not a demonstrated systemic improvement; five samples are insufficient to
separate commit variation from scheduling effects. Despite this, optimized
Hokusai remains **~1.47×** the same-run Legacy staging p95, and those two
backends intentionally use different brush output. It would be misleading to
claim that the owner-observed severe input lag is fixed. Hardware drivers,
pressure/stylus input, textured stamp throughput and Windows/macOS export
remain unverified.

### Per-stroke timing (ms)

| Backend | Stroke | Stage CPU | Release→commit | Frame compositor CPU sum |
|---|---:|---:|---:|---:|
| Previous Hokusai | 0 | 271.887 | 60.113 | 436.877 |
| Previous Hokusai | 1 | 261.843 | 68.236 | 495.914 |
| Previous Hokusai | 2 | 275.158 | 73.760 | 497.070 |
| Previous Hokusai | 3 | 272.787 | 97.831 | 512.145 |
| Previous Hokusai | 4 | 273.449 | 84.073 | 459.591 |
| Optimized Hokusai | 0 | 175.461 | 59.464 | 332.023 |
| Optimized Hokusai | 1 | 234.707 | 75.785 | 398.889 |
| Optimized Hokusai | 2 | 239.448 | 74.256 | 390.181 |
| Optimized Hokusai | 3 | 223.427 | 68.992 | 386.699 |
| Optimized Hokusai | 4 | 225.041 | 67.976 | 353.093 |
| Optimized Legacy | 0 | 142.601 | 52.516 | 147.985 |
| Optimized Legacy | 1 | 154.897 | 63.477 | 182.108 |
| Optimized Legacy | 2 | 162.737 | 66.027 | 194.324 |
| Optimized Legacy | 3 | 155.076 | 65.246 | 200.289 |
| Optimized Legacy | 4 | 162.302 | 58.211 | 206.556 |

An earlier optimized run reported stage p95 233.782ms, composition p95
17.632ms and passed all pointer assertions. The confirmation above is the
comparison used for the percentage change.

## Regression matrix and outstanding gates

- `brush_blend_math_smoke.gd`: **4/4 checks, 114,688 exact old-formula RGBA8
  comparisons** including all 256×256 alpha pairs, randomized signed pigments
  and 16,384 explicit opaque/transparent endpoint cases. The benchmark is
  informational, not a CI performance ceiling.
- `hokusai_bulk_delta_smoke.gd`: **119/119** checks. New dense, multi-batch
  signed-64-bit source-coordinate oracle spans multiple 32px storage tiles,
  recrosses tile boundaries, and verifies clipped/off-selection pixels,
  selection holes, hidden RGB, preview parity, one commit and Undo/Redo against
  independent per-pixel staging. Earlier atomic lazy-load failure/retry and
  mixed-edit rollback tests remain active.
- `brush_coverage_smoke.gd` **32/32**; native preset integration **30/30**;
  released-stroke pan/zoom/navigation **48/48**; signed-border framebuffer
  regression **17/17**; viewport-cache **153/153**; live-stroke native
  **125/125** (all local Godot 4.8b2). Native and no-binary fallback each
  passed **6/6**.
- Renderer sparse-layer, live-stroke model, preview-index model and selection
  large-mask model pass; clean staged standalone import passed. The
  T-094 fail-closed log checker accepts the named headless markers; Godot
  known post-exit graphics leak diagnostics are retained in the native logs.
- The remote PR #16 has **not** been merged; previous checkpoints also exist
  only in local commits and cumulative mailbox. No owner recheck or
  acceptance is recorded. **T-095 remains `In Progress`, `manual_review:
  true`; T-096's separate manual gate remains untouched.**

## Reproduce

With the pinned tooling, from the repository root:

```bash
python3 tools/build_drawing_app.py --in-place
/path/to/Godot_4.8_beta2 --headless --editor --path drawing --import --quit
/path/to/Godot_4.8_beta2 --headless --path drawing \
  --script res://tests/brush_blend_math_smoke.gd
/path/to/Godot_4.8_beta2 --headless --path drawing \
  --script res://tests/hokusai_bulk_delta_smoke.gd
xvfb-run -a -s '-screen 0 1280x900x24' env DRAWING_BRUSH_BACKEND=Hokusai \
  /path/to/Godot_4.8_beta2 --display-driver x11 --rendering-method gl_compatibility \
  --path drawing --script res://tests/brush_latency_native.gd
```

Owner device testing with continuous input-to-photon/catch-up measurements,
pressure, brush headroom, compositor validation, and explicit owner approval
remain prerequisites for changing status to Done.
