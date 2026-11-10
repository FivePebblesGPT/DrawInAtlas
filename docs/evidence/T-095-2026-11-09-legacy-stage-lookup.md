# T-095 — default Legacy Brush tile lookup and staging checkpoint (2026-11-09)

**Scope:** One T-095 performance/checkpoint only, on branch
`sprint/2026-11-07`. Status remains `In Progress`, `manual_review: true`.
The 2026-11-08 owner rejection has not been rescinded. No ticket closure,
manual acceptance, native backend default change or PR merge is asserted.

## Implementation

`DrawingEditSession._stage()` computes its signed storage tile key and
integer local index once for each accepted Brush/Eraser pixel. The source
snapshot read and detached preview update share those exact coordinates.
Instead of a `DrawingRasterTile.get_rgba(x,y)` call after two `posmod`
operations, the already verified immutable source tile is read from
`_pixels[local_index]`, as used by the independent native-delta path.
For power-of-two tile strides, a precomputed per-session arithmetic shift
and mask replace floor division/modulo. Irregular strides use the original
`DrawingDocument.TILES.tile_key64()` and `posmod()` route. The source remains
detached and canonical `_before`/`_after` maps, selection, blending,
per-stroke coverage and publication remain unchanged.

A trial scalar oblique-distance predicate with a `Geometry2D` boundary
fallback showed negligible same-machine benefit (trial p95 163.395ms vs
an original 163.652ms control); **that trial was reverted**, not shipped.
The new `t095_oblique_geometry_smoke.gd` instead retains the original
`Geometry2D` predicate as an independent pixel reference.

## Controlled five-stroke Legacy pointer diagnostic

- Engine: Godot `4.8.beta2.official.cafc17a19`, bundled tooling runtime.
- Display: isolated 1280×960 Xvfb, OpenGL compatibility, Mesa llvmpipe;
  root process, Debian/Linux software rendering, no physical mouse/GPU.
- Test: `drawing/tests/brush_latency_native.gd` with
  `DRAWING_BRUSH_BACKEND=Legacy`, 512×512 image, zoom `7.86` (786%), 60px
  Brush, five strokes of 120 dispatched native mouse motion events each,
  including actual down/up, held previews and framebuffer readback.
- Comparison: same staged project, old `edit_session.gd` copied from the
  preceding local commit for the control, then restaged from the optimized
  canonical file. No application fill was substituted for Brush.
- Baseline source: `/tmp/t095-turn9-paired-base.log` (local evidence, not a
  committed binary artifact). Optimized source:
  `/tmp/t095-turn9-paired-new.log`.

| CPU timing (five strokes) | Previous | Optimized |
|---|---:|---:|
| Stage p50 | 153.981 ms | 138.376 ms |
| Stage p95 | 168.123 ms | 148.419 ms |
| Release → commit p50 | 58.204 ms | 56.496 ms |
| Release → commit p95 | 63.098 ms | 57.178 ms |
| Frame composition p95 | 12.127 ms | 11.660 ms |
| Upload p95 | 0.429 ms | 0.358 ms |
| Input → stage p95 | 81.444 ms | 63.965 ms |
| Worst queued samples | 23 | 13 |

Stage p95 is lower by **19.704ms (11.7%)** in this small paired
software-rendered sample. Release-to-commit and queue differences are not
robust acceptance evidence; they vary with VM load. A second comparison
likewise found old p95 163.652ms versus optimized 146.904ms. No throughput
budget or physical input-to-photon latency was verified.

## Correctness and test matrix

- **4,193/4,193** new independent `t095_stage_tile_lookup_smoke.gd` checks:
  seven strides (1, 2, 3, 64, 255, 256, 2048), >32-bit positive/negative
  world anchors, `read_pixel` reference source RGBA8, hidden RGB, selection
  subtraction holes, repeated brush coverage, verified-source shortcut,
  preview, canonical before/after histories, commit, Undo/Redo.
- **86/86** new `t095_oblique_geometry_smoke.gd` checks: original
  `Geometry2D` swept-circle reference for stationary/diagonal/axis paths,
  7px/29px/60px Brush, Eraser, negative/>32-bit origins, selection holes,
  preview, exact pixel histories and Undo/Redo.
- Existing headless: brush coverage **32/32**; Hokusai **126/126**;
  signed native tile **422/422**; native tile commit **56/56**; sparse preview
  **133/133**; viewport preview index **2,146/2,146**; T-096 selection
  **13,847/13,847**; T-085 live stroke **77/77**, and blend checks passed.
- Graphical Xvfb: actual native presets **30/30**; post-release navigation
  **48/48**; live stroke **125/125**; signed pixel boundary **17/17**;
  native-present fallback **6/6**; viewport cache **153/153** after a clean
  editor reimport restored generated font resources.
- Fresh no-native stage, with manifest and library removed before first
  editor import: new source oracle **4,193/4,193** and Legacy fallback
  **6/6**, without startup errors.
- On-demand CI workflow now runs both new source oracles and applies
  `tools/check_godot_model_log.py` fail-closed marker validation. Full hosted
  CI was not run. Godot's known post-exit signed-boundary texture/RID leak
  warnings persist; clean engine shutdown is **not** claimed.

## Open gates

1. Test the original ~three-second 60px UX scenario on the owner's actual
   hardware, including pointer input-to-photon, queue age and frame timing.
2. Obtain explicit owner acceptance; do not mark T-095 Done from Xvfb data.
3. Run hosted CI, export/packaging and supported-device validation separately.
4. Continue profiling sustained strokes and native Hokusai staging; native
   presets remain optional and their original-source precision contract must
   not change silently.
