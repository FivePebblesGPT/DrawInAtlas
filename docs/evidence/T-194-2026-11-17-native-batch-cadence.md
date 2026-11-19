# T-194 — Native stroke batch cadence / 250 ms software benchmark (2026-11-17)

**Raw evidence:** [T-194 checksummed archive directory](T-194-2026-11-17-native-batch-cadence-raw/) (called `raw/` below). It contains the original process logs, time reports, validation JSON, explicit zero/nonzero exit records, and `SHA256SUMS`.

## Scope and fail-first cause

The T-193 96 px strict 100-event benchmark has approximately **296 interpolated source-space segments**, around **50 ms native raster CPU** plus fixed-point scan, tile stage, Godot input/frame scheduling and approximately 120–140 ms release→commit in the reference path. The preview compositor is already near 2 ms. Canvas used a fixed **16-segment** Hokusai transaction cap and a **6 ms soft drain deadline checked only *between* atomic batches**. It was making **62** native stroke FFI calls per gesture; a complete 100-event gesture could wait through many frame callbacks after release even though no source samples were dropped.

The production change increases **only** the native transaction cap to **20**. It does **not** alter Hokusai preset/brush state, stroke sample retention, interpolation length, painting math, soft drain deadline, tile authority, viewport preview correctness, or commit/history logic. `DRAWING_T194_BATCH_COUNTERFACTUAL=1` selects the prior 16-segment cap in the **same script/native release build**. This is not a native-free fallback. The larger cap can make a single atomic batch longer; exceeding 6 ms in an individual soft-deadline drain is permitted by the existing contract and occurs in both modes. It is not a claim of a hard real-time bound.

The new signed/selection/hidden-RGB/frozen native Brush/Eraser graphical regression failed **2/79 assertions** with the unmodified cap: the two modes made equal native transaction counts. Its log and exit **1** are retained as `raw/fail-first-graphical.{log,exit}`. With the 20-segment default, it passed **79/79** at `raw/graphical-candidate.{log,exit}` and again on the final test source at `raw/graphical-final.{log,exit}`, comparing exact source bytes after Brush/Eraser, native history, Undo/Redo, cancellation and real standalone Save/Open. The strict T-146 checker independently verifies 512² source coverage, **100 input events**, source SHA, framebuffer points, first-preview callback, full Undo/Redo and absence of fallback for *every* benchmark run.

## Rejected cap experiments

Before selecting 20, the test-only `DRAWING_T194_EXPERIMENT_BATCH_CAP` override ran **8** and **12** segments against the unmodified 16-segment default (two cold independent processes and two warm gestures each). All source-integrity checks passed and exited **0**, but the smaller caps did **not** offer a reliable wall-clock win. Median cold total→postdraw was **247.9 ms** (16), **261.1 ms** (8), **317.5 ms** (12); warm was **250.7**, **284.0**, **243.0 ms** respectively. The 8 cap increased native stroke FFI calls **62→116**. The early 20-cap experiment yielded cold **238.1 ms**, warm **217.9 ms** in the same initial environment. Rejected transient experiment-only source is not retained as a second production switch; complete raw logs and JSON (including native source/library identities) are in `raw/baseline`, `raw/batch8`, `raw/batch12`, `raw/batch20`. Those runs are **not pooled** with the final production/reference A/B; they preceded the final unchanged-candidate script.

## Final same-source, same-native-binary, reversed-order rapid A/B

Both pairs use the final production checkout with **only the diagnostic environment variable** changing. Order: **16→20** then **20→16**. Each mode/pair has **two independent cold processes + one two-gesture warm process** (4 cold and 4 warm strict observations per mode, all process exits and all checker exits **0**). Native library SHA-256: `f6472af4aa6150db710d72da0091e5a134ccaa1d95c84ef2dc0617d54fcdf2b0`; Hokusai preset SHA-256: `d321de8649e6b5cd529d0bf739ccfa9744ead7e5454ab5744d91c21d38bff3ad`. **Every source SHA-256** is `6df89cc963368830befd8dbf061db9bb0f40060556a8dfb127cf5e9681f68ec4`. No LFS assets or native Rust implementation were changed by T-194.

| Scenario | 16-segment p50 / p95 (ms) | 20-segment p50 / p95 (ms) |
| --- | ---: | ---: |
| Pair 1 cold | 281.0 / 342.6 | **221.7 / 240.5** |
| Pair 1 warm | 263.0 / 319.7 | **235.3 / 239.6** |
| Pair 2 cold | 274.7 / 276.6 | **221.2 / 238.1** |
| Pair 2 warm | 241.4 / 251.2 | **225.8 / 229.2** |
| **Pooled cold, n=4 per mode** | **276.6 / 342.6** | **221.7 / 240.5** |
| **Pooled warm, n=4 per mode** | **251.2 / 319.7** | **229.2 / 239.6** |

Nearest-rank p95 for 2 or 4 observations is **the maximum**, not a statistical guarantee about population tails. Both measured optimized p95s are **under the 250 ms rapid software-X11 milestone**. This is an independently repeatable small-sample scripted benchmark milestone, **not** the 200 ms stretch, physical acceptance or a universal FPS claim.

| Pooled p50 measure | 16 cold → 20 cold | 16 warm → 20 warm |
| --- | --- | --- |
| Complete gesture incl. first settled postdraw | 276.6 → **221.7 ms** | 251.2 → **229.2 ms** |
| Queued release→commit | 142.7 → **110.8 ms** | 123.1 → **109.8 ms** |
| Native+stage CPU | 77.6 → **70.9 ms** | 73.4 → **71.4 ms** |
| First preview postdraw | **27.6** → 29.5 ms | **23.6** → 27.9 ms |
| Max soft-drain call time | 9.2 → 10.3 ms | 8.8 → 10.4 ms |
| Native stroke FFI calls | 62 → **50** | 62 → **50** |
| Native tile-export bytes | 3,670,016 → **3,145,728** | 3,604,480 → **3,145,728** |

A longer atomic batch sometimes worsens first preview and soft-drain duration despite reducing repeated transaction and display work; these regressions are not concealed. Individual per-process peak RSS remains approximately **268–274 MiB** and cannot establish memory improvement. All original `T146_NATIVE_PHASE`, first-visible, source digest, surface alpha, bitmap/Undo/Redo and frame oracle lines are retained under `raw/ref1`, `raw/opt1`, `raw/opt2`, `raw/ref2`; `summary.json` carries the complete p50/p95 definitions and raw inputs.

## Full workspace / frame/backlog scope

Two reversed-order pairs with **four confirmed zero-exit processes** (`raw/work-{ref,opt}{1,2}`) each exercise **eight** real Drawing workspace gestures: cold Brush, warm overlap, held input and Eraser at **54% and 100% zoom**. Strict native source, input count, native tile API, frame/preview and history checks all pass. At **54% cold Brush**:

| Pair / mode | Stage CPU | Release→settled | Frame interval p95 | Long frames ≥83.33 ms | Requested uploads |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 reference | 49.9 ms | 106.2 ms | 16.8 ms | 1 | 3,473,408 B |
| 1 optimized | 48.5 ms | 113.4 ms | 16.0 ms | 1 | 3,473,408 B |
| 2 reference | 47.3 ms | 108.2 ms | 15.2 ms | 1 | 3,473,408 B |
| 2 optimized | 56.1 ms | 112.4 ms | 18.1 ms | 1 | 3,473,408 B |

At **100% cold**, stage CPU is 51.0→52.8 ms (pair 1) and 50.5→50.9 ms (pair 2); release→settled 118.1→119.2 ms (pair 1) and 109.0→109.6 ms (pair 2), with frame p95 23.0→17.0 and 17.8→24.2 ms, respectively. The full-workspace 14-event scripts need fewer than the strict 100-event workload's native stroke calls; batch volume often remains 14 in both modes. Cold requested tile upload bytes are unchanged in all four processes per zoom. Peak full-workspace RSS: **322,216 / 326,132 KiB reference**, **325,660 / 325,604 KiB optimized**. Complete `summary.json` retains frame input-backlog p95/max, first preview, cold/warm/held/Eraser release time, raster/scan/stage phase, preview cache and upload evidence. There is **no established full-workspace frame-tail, release-to-settled or RSS win**, and every process has a long frame. Software Xvfb/llvmpipe callback intervals are not measured physical input-to-photon latency or display scanout.

## Tests, failures, artifact boundaries and outstanding gates

- `make python-test lint` **exit 0** (18 toolchain + 5 profiler/parser tests, Ruff and ty).
- Native Rust **34/34**, native Brush **32/32**, native tiles **312/312**, standalone Drawing **42/42**, preset **16/16**, Atlas native history **43/43** pass. The first broad `make check` wrapper returned no confirmed outer exit after reaching the Atlas success marker; this **incomplete wrapper** remains at `raw/make-check.log`. Its independent retry `raw/make-check-confirmed.{log,exit}` has a confirmed **exit 0**.
- `make test-graphical` **exit 0**, ten native graphical suites T-181 (19), T-186 (14), T-187 (99), T-188 (63), T-189 (77), T-190 (77), T-191 (77), T-192 (81), T-193 (83), T-194 (**79**) all pass (`raw/make-graphical.{log,exit}`).
- Generated Godot `.import` sidecars and cache are not committed. `raw/SHA256SUMS` verifies all retained raw files. The local native `.so` is build output only, not attached as an extra artifact.

**T-194 is Done for the measured 250ms scripted software-X11 milestone and a bounded, correctness-verified batch-cap optimization.** T-195 tracks the **unmet 200ms stretch and inconsistent paced full-workspace tails**. T-095 independent physical/owner acceptance, T-151/T-152 post-consolidation, T-148/T-149 native transition and T-105 Windows/export remain open; none was authorized or closed by software profiling.

## Reproduction

With the pinned bundle and native extension loaded, `make import-drawing TOOLCHAIN=bundle BUNDLE=...`, followed by `DRAWING_T185_PROFILE=1 python3 tools/run_t146_hokusai_bench.py --cold 2 --warm 2 --godot <bundled Godot> --output <path>` four times in 16→20→20→16 order. Set `DRAWING_T194_BATCH_COUNTERFACTUAL=1` for the 16-cap reference and omit it for the optimized mode. For paced full Drawing use `tools/run_t185_profile.py --trials 1` four times in the same mode order. Run the real graphical `res://tests/t194_native_batch_cadence.gd` under X11 or `make test-graphical`. The 250ms result is tied to this strict workload, software renderer, current library and current checkout, **not** generic owner hardware acceptance.
