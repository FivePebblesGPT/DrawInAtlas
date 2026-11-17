# T-189 — Hoist immutable native source lookups per storage tile

**Date:** 2026-11-17. **Scope:** one bounded Rust native-stage change after
T-188's run-aware delta grouping, not completion of the 250ms/200ms latency
milestones. Godot 4.8.beta3, pinned Rust/Hokusai and native `DrawingNativeBrush`
/ `DrawingNativeTiles`, Mesa llvmpipe/X11 via 1280×900 Xvfb. These are Godot
software-framebuffer/input-receipt measurements, **not** physical device FPS,
input-to-photon or owner acceptance.

## Measured cause and implementation

T-188's native-stage traces leave Hokusai raster at roughly 50ms and changed
pixel scanning at roughly 20ms; tile application still costs around 30–50ms
for the rapid 96px stroke. In `TileStore::stage`, every grouped Hokusai pixel
was rehashing the immutable `TileId` to read the *same* canonical source RGBA8
for blending or erasing. T-189 resolves that source slice **once per authorized
storage tile**, rather than again for each of its pigment pixels. It does not
change the sorted source delta stream, blend/erase rounding, sample count,
run grouping, soft 6ms drain budget, dirty bounds, visibility, source preflight
or atomic staged-draft/rollback/commit/history behavior. Non-pigment staging is
unchanged. The source remains immutable during the entire stroke; the drafted
preview is still separate and never used as the blend source.

A diagnostic **same-binary** switch
`DRAWING_T189_SOURCE_PER_PIXEL_COUNTERFACTUAL=1` restores the old hash lookup
per pigment pixel. Normal production behavior always uses the per-tile source
read. `DrawingNativeTiles.stats().source_lookups` and the committed stroke's
`native_ffi_stats.tile_source_lookups` report cumulative *successful-stage*
source-map lookups for attribution (not transferred bytes or per-stroke
quantities). In the signed/masked graphical Brush trial the optimized source
path performed **15** lookups versus **95,225**; after the Eraser trial the
cumulative counts were **30** versus **190,450**. These counts are not CPU
latency or full-gesture speedups by themselves.

## Strict rapid 100-event A/B, one binary and reversed order

Unmodified `tools/run_t146_hokusai_bench.py --cold 2 --warm 2 --timeout 65`,
96px Hokusai Hard Round, 512² full source, 100 input events and 296
interpolated segments, with independent cold processes and a two-gesture warm
process *per mode*. Both runs use the same compiled native library SHA-256
`cad9b15b8e1c84e03c866ec0b098cb56752466a2135dce5143557cf2e7379160`.
Round 1 ran reference then optimized; round 2 reversed the order. Every one
of **12 processes / 16 complete gestures** exited zero and passed the strict
native/coverage/first-preview/framebuffer, mask/hidden-RGB, cancel and
Undo/Redo oracle. All gesture sources and redo outputs have SHA-256
`6df89cc963368830befd8db9bb0f40060556a8dfb127cf5e9681f68ec4`.

`p50/p95` below are nearest-rank (so, for two samples, p50 is the lower and
p95 the higher), in **milliseconds**. Reference → optimized. These are the
unchanged `total_to_postdraw_ms` **complete** gesture measurements, not stage
CPU, frame p50, or release-only substitutes.

| Pair | Cold full gesture p50/p95 | Warm full gesture p50/p95 | Cold staging CPU p50 | Warm staging CPU p50 |
| --- | --- | --- | ---: | ---: |
| Round 1 · reference first | 310.1/344.0 → **257.4/389.5** | 297.4/308.5 → **243.6/273.2** | 106.9 → **87.6** | 103.9 → **80.1** |
| Round 2 · optimized first | 338.7/364.2 → **281.8/311.6** | 293.3/337.3 → **274.4/280.7** | 112.1 → **93.2** | 98.5 → **88.4** |
| Pooled (4 cold, 4 warm per mode) | 338.7/364.2 → **281.8/389.5** | 297.4/337.3 → **273.2/280.7** | 112.1 → **93.2** | 103.9 → **88.4** |

**Do not conceal the worse round-1 cold p95** (344.0→389.5ms) or treat the
round-1 warm p50 below 250ms as sustained acceptance: the pooled cold/warm
p50 is **281.8/273.2ms**, above 250ms, and the 200ms stretch is also unmet.
A single process can still have a 390ms cold gesture. Software timing varies
substantially across independent processes.

Across all eight rapid strokes per mode, the native tile-application phase
p50 fell **31.0→14.4ms cold** and **29.0→9.6ms warm**, while native raster
stayed roughly 52.8→52.1ms cold and 50.0→50.3ms warm. Changed-pixel scan
was about 19.7→19.5ms cold and **18.2→20.5ms warm** (warm scan got slower).
Total stage includes these nested phases; do not add CPU phase measurements
to total wall time. The full-gesture release→commit p50 was
**209.9→155.2ms cold**, **170.2→149.2ms warm**, but cold p95 **worsened
235.4→275.9ms**. The first preview postdraw p50 was **30.4→30.5ms cold**
(slightly worse) and **26.6→23.7ms warm**. Per-process peak RSS across
rapid trials ranged **269,508–273,816 KiB (roughly 263–267 MiB)**; there is no
memory reduction claim. Cold native preview bytes exported p50 were **3,866,624→3,670,016**;
warm **3,801,088→3,604,480**. Those counts follow input scheduling: T-189
did not change the texture-upload or transfer policy.

The strict fixture's input backlog still reached **99** queued engine-received
events in every process, with no lost samples. Rendering of all 262,144
source pixels, five framebuffer points, one native history command and
source/redo digests passed in each gesture. The measured apparent image may
look smoother; no FPS claim follows from this virtual benchmark.

## Full-workspace paced input and tails

`tools/run_t185_profile.py --trials 1 --timeout 85` was repeated twice per
mode with order reversed (optimized/reference, reference/optimized): **four
confirmed zero-exit processes**, each checking all eight Brush, overlapping
warm Brush, held Brush and Eraser scenarios at **54% and 100% zoom**. These
have *14 real engine-received scripted inputs per scenario*, not the rapid
100-event fixture. All 32 scenarios pass the separate native-source and frame
trace validator. For the **54% zoom cold Brush** case:

| Pair | Reference vs optimized native stage CPU | Postdraw callback interval p95 | Long frames ≥83.33ms | Release→settled display |
| --- | ---: | --- | --- | --- |
| 1 | 83.1 → **52.4ms** | 30.2 → **19.9ms** | 1/26 → 1/39 | 139.7 → 139.3ms |
| 2 (reversed) | 62.5 → **55.2ms** | **17.7 → 19.4ms (worse)** | 1/44 → 1/40 | **119.4 → 131.4ms (worse)** |

54% held Brush and Eraser retain valid source, queue, release and history
assertions; both zoom levels and all scenarios are in the raw 8-scenario
summaries. At 100% cold Brush, frame-postdraw p95 was 29.9→24.1ms then
23.4→22.6ms. For the 54% cold scene, requested upload bytes are exactly
**3,473,408 in all four runs**. The outstanding input depth p95 is **1** in
all four runs; no suppression of updates or shifted input backlog explains
the lower CPU stage. Both cold runs still contain a ≥83.33ms long frame.
Full-workspace peak process RSS was **324,264 / 326,636 KiB optimized** and
**326,188 / 327,040 KiB reference**; no stable memory change is established.
The software-rendered frame p95 and release→settled are **mixed**, not a
universal frame-time or physical acceptance improvement.

## Regression and failure accounting

- **Fail-first:** the initial real graphical fixture failed 4/69 assertions
  because lookup attribution was unavailable and no per-tile reduction
  existed. The initial Rust regression failed to compile due to the absent
  `stage_with_source_mode` helper and counter. Both raw logs are preserved.
- **Green:** Rust **29/29**, including same-byte masked signed source,
  Brush/Eraser blending and source-based Undo/Redo; real X11 T-189 **77/77**
  comparing both modes and partial-alpha source, hidden RGB, selection hole,
  queued interpolation, cancellation, actual portable Save/Open, full source
  and history parity. The independent same-binary graphical counter count is
  reported above.
- Full offline `make check` **exit 0**: Python packaging 18,
  profiler-parser 5, Ruff/ty, Rust 29, native Brush 32, native tile 312,
  standalone 42, preset controls 16 and Atlas native-history 43.
  Full `make test-graphical` **exit 0**: T-181 19, T-186 14, T-187 99,
  T-188 63 and T-189 77. A first graphical command printed all pass markers
  but did not produce a confirmed outer shell exit; its log is retained,
  followed by a separate confirmed-zero full rerun.
- Raw benchmark process logs, resource time/RSS files, strict parsed
  `summary.json`, fail-first and regression logs and their SHA-256 hashes are
  committed in [T-189 raw evidence](T-189-2026-11-17-raw/).
  Replaying the same mode requires no different native binary; reference
  environment is diagnostic only. Do not infer this test has exercised
  Windows, GPU devices or the owner's physical workflow.

**Outcome:** close T-189 *only for this measured bounded source-map lookup
optimization*. The unchanged 250ms milestone and 200ms stretch remain
**open** as [T-190](../Tickets/T-190.md), including the next ~50ms Hokusai
raster/~20ms scan and total queued/release/postdraw cost. Keep T-095 owner
physical review, T-151/T-152 post-consolidation gates, T-148/T-149 native
ownership and T-105 portability/exports open; no approvals were granted.
