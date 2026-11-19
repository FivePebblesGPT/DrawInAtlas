# T-185 — Current full Drawing workspace profiling (2026-11-17)

## Scope and provenance

This is a **fresh after-T-181/T-183/T-184** native Drawing profile, not the
future T-151 post-consolidation gate. It measures the actual standalone
`main.tscn` workspace, including the Brushes panel, document/layer model,
Godot viewport/Canvas compositor and Rust Hokusai Brush/Eraser. The owner
*estimated* ~12 FPS; no hardware measurements or owner review are imputed.

The raw data and machine/source identity are in
[`T-185-2026-11-17-raw/workspace/summary.json`](T-185-2026-11-17-raw/workspace/summary.json),
with **six complete stdout logs**, six process-time files, and a classification
for each trial (four zero-exit successes; two **not counted** because exit was
not confirmed). The original log lines contain every per-frame/FFI counter.
[`t146-matrix.json`](T-185-2026-11-17-raw/t146-matrix.json) and the
[`t146-a/`](T-185-2026-11-17-raw/t146-a/summary.json) /
[`t146-b/`](T-185-2026-11-17-raw/t146-b/summary.json) process summaries retain
the separate 96 px full-canvas fill measurements and checks, with all six
source/redo/coverage witnesses in the respective raw `.log` files.

- **Code identity:** parent checkout `0d8090b53537070f053374bad15ad477e522f215`
  (after T-184), plus the T-185 *instrumentation and harness* committed by this
  ticket. `summary.json` contains SHA-256 of the actual profiled canonical
  `canvas.gd`/`edit_session.gd`/`workspace.gd`, both harnesses and all four
  `.myb` presets. The loaded native library SHA-256 is
  `07f91f19efa67b42517d8efcee1fc67ae7d8e0cbe67123519a323e592adc8b9c`.
  `hard_round.myb` is the T-183 corrected preset (SHA-256 in raw metadata).
- **Environment:** Linux x86-64 6.18.57/glibc 2.41, virtual AMD EPYC 9V74,
  Python 3.13.5, bundled Godot 4.8 beta3 (official `c51ff06e8`), Mesa
  llvmpipe software GL compatibility, Xvfb 1280×900×24, native GDExtension
  registered, no CPU hardware `perf`/native OS sampler available. Recorded
  peak resident memory for complete full-workspace processes was about
  325–327 MiB (see individual `.time` files).
- **Document:** fresh blank 512×512 clipped frame at signed `(-256,-256)`,
  root → Group 1 → one raster Layer 1; width 96 px, hard preset, 100% base
  opacity, default hardness, foreground pigment from the real workspace.
  Full workspace Canvas is about 1030×800 screen pixels; camera centered at
  zero, zoom **0.54** and **1.0**. For each zoom, the first Brush stroke starts
  with zero populated display textures; three following strokes reuse warm
  display tiles, including overlapping Brush, held stationary Brush, and Eraser.
- **Input:** 14 injected chronological *Godot mouse events* (down, 12 moves,
  up) along a signed serpentine with 16 ms **requested** inter-motion timers,
  followed by eight 16 ms *requested* held intervals. Actual delivery is
  scheduled by the same busy engine: cold 54%-zoom observed motion delivery
  interval p50/p95 = **69.645/120.376 ms**. Timers are not independent device
  interrupts; there is no claim of 60 Hz delivery while the main thread stalls.
  Per-stroke document revision, source RGBA8 SHA-256, native tile ownership,
  nonzero source coverage and Eraser alpha decrease are asserted.

**Repeat/validity:** two separate captures each attempted three fresh Xvfb
processes. In *each* capture, the first two processes exited zero with all
8/8 scenarios and complete native evidence, giving **4 valid processes × 8
scenarios = 32 native gesture observations**. In each capture the third
process printed all eight pass markers but did not provide a confirmed exit
before the outer execution timeout. These **two unverified exits** are retained
as invalid (`exit=124`, zero-length `.time` records) and are *not* silently
included in the statistics. `run_t185_profile.py` rejects missing/false
metadata, non-native strokes, bad frame samples, source mismatch and a success
marker without an independently recorded zero exit. Thus the sample is small;
pooled per-frame p95s below are descriptive, not owner-hardware acceptance.

## Frame cadence: the reported ~12 FPS is plausible, not proven physical

Each value is from the **actual `RenderingServer.frame_post_draw` interval**
trace, inclusive of delayed renderer callbacks, across the four accepted
processes. Pooled interval p50/p95/max and long-frame counts are measured;
these are not `1 / Canvas._draw()` and not display-scanout timings.

| Case | 54% frame intervals p50 / p95 / max (ms) | Frames ≥83.333 ms | 100% p50 / p95 (ms) | Frames ≥83.333 ms |
| --- | ---: | ---: | ---: | ---: |
| First cold Brush | 25.546 / **118.473** / 127.427 | **28 / 111** | 29.192 / **115.996** | **28 / 105** |
| Warm overlap Brush | 12.633 / **94.507** / 105.388 | 19 / 115 | 52.990 / **100.333** | 23 / 101 |
| Held/stationary Brush | 15.752 / **88.280** / 97.792 | 12 / 107 | 13.399 / **88.448** | 12 / 110 |
| Warm Eraser | 17.729 / **121.636** / 140.357 | **29 / 106** | 48.343 / **109.585** | **28 / 102** |

For example, an 83.33 ms interval corresponds to **12 rendered frames per
second over that interval**, whereas 118.47 ms corresponds to ~8.44 FPS.
Other intervals are much shorter. The owner's ~12 FPS impression is therefore
*compatible* with measured intermittent stalls, but cannot be independently
confirmed as a physical FPS value on the owner's device. Sampling both
`SceneTree.process_frame` and renderer callbacks exposes similar stalls; the
raw traces and threshold counts are preserved separately.

## First preview, backlog and release boundaries

The complete full-workspace gesture deliberately includes paced movement and
a stationary hold. It is **not** the same duration metric as the rapid T-146
serpentine below. All numbers here are median / p95 **over four complete
processes per scenario**, in milliseconds.

| 54%-zoom gesture | Down→first preview **submit** | Down→first `frame_post_draw` | Release→commit | Release→settled postdraw | Down→settled total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Cold Brush | 41.395 / 44.433 | 49.682 / 54.154 | 7.662 / 14.332 | 109.471 / 123.499 | 1229.597 / 1301.045 |
| Warm overlap | 63.334 / 68.796 | 72.072 / 78.179 | 7.664 / 9.400 | 82.808 / 98.736 | 1151.309 / 1164.244 |
| Held Brush | 50.716 / 58.879 | 58.370 / 72.300 | 7.622 / 8.079 | 82.390 / 83.652 | 996.993 / 1029.213 |
| Eraser | 52.932 / 61.218 | 61.454 / 70.721 | 7.298 / 8.749 | 106.617 / 121.656 | 1234.326 / 1356.982 |

The earliest post-draw callback is a renderer-side acknowledgment, **not a
verified visible pixel on a physical screen**. Settlement requires the edit
queue to finish, the cold-tile queue to empty and a post-commit `post_draw`
callback. At 54% cold Brush, observed Canvas frame backlog **max=1** and
oldest pending input age **p95≈11.1 ms**; a producer constrained by slow engine
frame/timer delivery can show *small queue depth alongside poor responsiveness*.
`Input.use_accumulated_input` and T-181's framebuffer-retention correctness
are independently tested; neither is bypassed here.

## The separate, comparable T-146 96 px / 512² rapid benchmark

Actual `drawing/tests/t146_hokusai_full_canvas_native.gd` through
`tools/run_t146_hokusai_bench.py`, **100 chronological injected pointer
events**, one continuous 96 px Hard Round serpentine, 262,144/262,144 source
pixels covered, checked alpha/source digest, five framebuffer points,
one-step native Undo/Redo, mask, hidden RGB and cancel/retry. Four **zero-exit
processes**: two cold single-gesture runs and two warm two-gesture runs.

| Metric | Cold n=2 p50 / p95 (ms) | Warm n=4 p50 / p95 (ms) |
| --- | ---: | ---: |
| **`total_to_postdraw_ms` (declared target metric)** | **653.897 / 674.544** | **680.492 / 831.954** |
| Release→commit | 603.443 / 621.737 | 631.060 / 772.114 |
| Down→first preview submit | 18.495 / 23.499 | 18.396 / 22.077 |
| Down→first postdraw callback | 48.680 / 54.786 | 53.276 / 58.132 |
| Cumulative stage CPU | 138.773 / 144.616 | 143.230 / 179.533 |
| Cumulative compose CPU | 308.754 / 381.918 | 377.101 / 450.195 |

**Target pinned for T-186:** `total_to_postdraw_ms` for this fixed 100-event
96 px/512² **rapid T-146 workload**, using this after-T-183 preset identity,
with separate cold and warm **p50 and p95**. The requested **≤250 ms**
near-term / **≤200 ms** stretch targets are **not achieved** by this baseline.
The historical 529.487 ms result was a different single run in a preceding
snapshot; neither it nor the owner's subjective ~12 FPS is identical to
this reproducible end-to-end gesture measurement.

## Stage attribution and repeatable first-change hypothesis

Existing `canvas.gd` engine function instrumentation already measures frame
`full_draw_cpu_us`, `compose_cpu_us`, texture create/update `texture_cpu_us`,
preview indexing and input ages, together with stage and commit. This ticket
adds an **opt-in**, zero-pixel-change `DRAWING_T185_PROFILE=1` split of the
native session's tile-batch stage: source authorization, Rust `apply_tile_batch`
FFI, cumulative `dirty_tiles` query, stamp/cache invalidation and index
invalidation. All split costs are **nested inside** the broad Canvas stage;
compose/texture/index are **nested inside** `full_draw_cpu_us`. Never add
inclusive totals as disjoint elapsed wall time. These are GDScript wall-clock
function timings around native calls; native Rust internal CPU instructions,
GPU uploads and physical scanout are *not* independently sampled (`perf` was
unavailable in this sandbox).

At **54% zoom**, p50 per *complete gesture* (four processes):

| Stage or copy path | Cold Brush | Warm overlap | Interpretation |
| --- | ---: | ---: | --- |
| Canvas **compose CPU** | **751.551 ms** | **671.437 ms** | Largest measured CPU hotspot; p95 **frame** compose 91.794 / 71.930 ms |
| Canvas native stage CPU (inclusive) | 81.893 ms | 88.783 ms | Includes many native stages + authorization and GDScript overhead |
| **inside** stage: native `apply_tile_batch` FFI | 29.325 ms | 36.427 ms | Native raster/transaction work bounded by the FFI call |
| **inside** stage: authorize source tiles | 7.770 ms | 7.600 ms | Lookup/import/preflight work |
| **inside** stage: cumulative dirty query + stamp | 0.593 ms | 0.629 ms | Not enough CPU to explain stalling by itself |
| **inside** stage: index invalidation | 0.034 ms | 0.032 ms | Tiny direct overhead; downstream redraw is the concern |
| Canvas texture create/update CPU | 6.751 ms | 6.371 ms | Time on Godot API, not independently measured GPU transfer completion |
| Canvas preview-index CPU | 0.610 ms | 0.616 ms | Small; already nested in draw |
| Commit/history CPU | ~7.7 ms | ~7.7 ms | Includes native publication/history and source bridge |
| Canvas `bytes_uploaded` | **9.63 MB** | **9.70 MB** | Accumulated RGBA8 upload requests in one gesture |
| Native tile `bytes_exported` **per-gesture delta** | **10.75 MB** | **10.75 MB** | The Rust tile-store stat is lifetime cumulative: delta it per document/stroke, **do not** report the raw cumulative 2nd/3rd values as single-stroke transfers |

Across **14 native batches**, the dirty-descriptor loop processed **41
entries for just four unique native source tiles** (37 key revisits); this
repeat pattern appears in every measured scenario. These are cumulative
*transaction* dirty descriptors, not proof that every repeated tile was
unchanged. The direct dirty-loop cost is below 1 ms, so optimizing its loop
in isolation would be a poor first choice. Its repeated stamp increments,
cache erasure and subsequent valid-but-costly warm texture recompositions
are a **plausible secondary cause** of the much larger Canvas compose and
RGBA-copy totals. The layer/tree composition body, internal native raster
micro-ops and renderer driver costs were not decomposed further; do not claim
all 751 ms is definitively redundant.

**Ranked critical-path hypotheses:**

1. **Frame compositor + repeated RGBA tile refreshes**: 563–776 ms median
   cumulative composition across 54%-zoom case types, up to ~100 ms CPU in
   individual draws; 9.6–9.7 MB requested texture uploads. This path is
   first in cumulative CPU, tail frame duration and potential rework.
2. **Synchronous native staging and its ~10.75 MB tile exports/stroke**:
   ~82–91 ms inclusive; native apply about 29–37 ms, authorization ~8 ms.
   The remaining stage time includes queue/GDScript and FFI wrapper overhead,
   not yet broken out by a native instruction-level profiler.
3. **Renderer callbacks/commit/history and queue bookkeeping**: release→commit
   ~7–14 ms, indexing/stamp below 1 ms per whole gesture. A delayed
   postdraw callback may still extend release→settled despite fast commit.

**One bounded, falsifiable T-186 first change:** track *actually modified*
native tile generations on each `apply_tile_batch` and only invalidate/recompose
**those** preview/display tiles, while **still drawing and refreshing any warm
tile whose pixels genuinely changed**. Avoid regressing T-181 by treating
previously visible tiles as "cold", hiding them, or skipping valid refresh.
Run the same two suites with identical source/preset/native inputs, same
cold/warm classification and no opacity/coverage changes. *Reject* this
hypothesis if a matched implementation does not lower per-gesture Canvas
`compose_cpu_us`, texture-upload bytes and the ≥83.33 ms frame fraction
consistently, or if framebuffer/source/Undo/Redo/mask/hidden-RGB evidence
changes. Compare T-146 **total-to-postdraw p50/p95** independently; the
250/200 ms target remains open until directly demonstrated. Merely removing
the tiny stamp loop is explicitly *not* accepted as proof of improvement.

## Reproduce and retained correctness checks

```sh
make check TOOLCHAIN=bundle BUNDLE=/mnt/data/drawing-toolchain-linux-x86_64-2026-11-17.tar.zst
python3 -m unittest discover -s tests -p test_t185_profile.py -v
# After make import-drawing and native registration:
python3 tools/run_t185_profile.py --godot /absolute/path/to/godot \
  --output /tmp/t185-profile --trials 2 --timeout 45
python3 tools/run_t146_hokusai_bench.py --godot /absolute/path/to/godot \
  --output /tmp/t185-rapid --cold 1 --warm 2 --timeout 45
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s '-screen 0 1280x900x24' godot \
  --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy \
  --path drawing --script res://tests/t181_native_preview_retention.gd
```

For the saved six-attempt workbook, `run_t185_profile.py --ingest` reads the
copied raw `.log` + `.time` pairs and exits **1 intentionally** because two
attempts lack a confirmed zero exit; `summary.json` still includes four valid
runs and explicitly classifies the invalid attempts. Do **not** suppress that
signal to assert six successful processes.

- **Full `make check`: exit 0** (25 Rust unit tests, native tiles 312/312,
  native brush 32/32, standalone smoke 42/42, preset 16/16 and Atlas native
  history 43/43, plus Python/lint and native registration). The local
  verified raw log is `.build/evidence/T-185/make-check-confirmed.log`.
- **T-181 graphical warm-tile framebuffer retention:** 19/19 pass, actual
  llvmpipe Xvfb frame readback. Other source, history, mask, hidden RGB,
  cancel/retry and full-coverage checks pass in the rapid T-146 harness.
- **New strict profiler parser:** 4/4 focused unit tests, including incomplete
  and falsely labelled metrics; Ruff clean. All **four** counted workspace
  processes pass the runtime witness 8/8 scenarios.

This completes **T-185 research/diagnostic acceptance only**. T-186 becomes
Ready for a profile-led optimization, while T-095's actual device comfort,
T-151's eventual consolidation gate, T-148/T-149 broader native authority,
Windows/export, and owner manual UX reviews all remain open.
