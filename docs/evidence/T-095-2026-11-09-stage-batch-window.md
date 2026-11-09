# T-095 — bounded *latest* stage-batch timing profile (2026-11-09)

## Scope and status

This is a **local engineering checkpoint**, not a T-095 completion or a performance/owner acceptance. T-095 remains `In Progress` with `manual_review: true`; T-096's separate review status is untouched. The supplied branch still has not passed a physical input-to-photon test on the owner's device, and the work is not a replacement for native Windows/Linux or hosted CI.

## Problem and implementation

`DrawingCanvas._drain_segments()` already limited `stage_batches_us` to 4,096 entries, but used a one-way append until full. For a continuously captured Brush stroke, all later batch durations were silently excluded from the p50/p95 distribution. That made the retained distribution **the beginning** of a long stroke even when the worst lag occurred near the end. It also failed to expose the exact number of staged batches and exact worst individual batch duration.

The current implementation uses a 4,096-entry latest-batch ring with the chronological order restored once at commit. `stage_batch_total` and `max_stage_batch_us` are exact **lifetime** metrics; the existing `stage_cpu_us` still aggregates all batch CPU work. For up to 4,096 batches, the existing `stage_batches_us` sequence is byte-for-byte equivalent. For longer strokes, its p50/p95 are **only the most recent 4,096 batches**, not the entire stroke. Batch timing samples are nonnegative, and the recorder index, counters, and distribution reset for the next gesture. The frozen pointer queue, raster/preview, commit, transaction and history logic are otherwise unchanged.

This fixes a *profiling blind spot*, not rasterization speed or the owner's outstanding responsiveness complaint.

## Reproduction and tests

The new `drawing/tests/t095_stage_batch_window_smoke.gd` is executed by the on-demand `.github/workflows/godot-native-t095-brush.yml`, with the strict `T095_STAGE_BATCH_WINDOW_PASSED` log contract. In a pinned Godot `4.8.beta2.official.cafc17a19` local run, **29/29 checks** pass:

- Short batch histories (including negative input clamp), exact lifetime count and maximum.
- 13,001 synthetic batch timings with a 900,000 µs *early* outlier; retained sample count never exceeds 4,096, while all-time count and maximum remain exact and the newest window is ordered after multiple wraps.
- Exactly two complete ring revolutions, including the zero-rotation edge case.
- Actual 5px pointer-driven Brush capture and a single post-release commit across zoom/camera changes, all per-batch CPU measurements summing to `stage_cpu_us`, exact batch count/maximum, byte-identical independent unsliced RGBA8 source, Undo/Redo, and a second stroke resetting its metrics.

A local previous-source negative control was run by staging only the **previous committed** `canvas.gd` into an isolated Drawing project. The new test returns a nonzero exit and an explicit failed assertion for the absent bounded stage-batch recorder; the strict log checker rejects it. The fixed project passes the same strict checker. This is a local contrast, not a hosted CI result.

Selected neighboring headless checks pass, including 32/32 hard-brush coverage, 30/30 result ownership, 22/22 bounded input latency, 31/31 sustained queue compaction, 126/126 native delta staging, 422/422 signed tile arithmetic, 56/56 tile commit, 133/133 sparse preview, 4,193/4,193 signed source staging, and the blend/preview-index oracles. Xvfb/Mesa native preset integration (30/30), post-release navigation (48/48), viewport cache (153/153), signed pixel-boundary (17/17), live stroke, and native-present fallback (6/6) pass locally after a clean Godot import. A separate clean standalone import **without the native manifest/library before first import** passes 29/29 and the 6/6 Legacy fallback. `tools/validate_ticket_store.py` validates all 96 tickets.

## CPU-only timing and limitations

One same-machine **five-stroke, 120 actual InputEventMouseMotion samples each**, 60px Legacy Brush at 786% zoom, Godot 4.8b2 under Xvfb/Mesa llvmpipe control recorded:

| Metric, p95 | Previous source | Updated source |
| --- | ---: | ---: |
| Total staging CPU | 131.499 ms | 129.490 ms |
| Atomic stage batch CPU | 2.839 ms | 2.776 ms |
| Release to commit | 63.199 ms | 80.129 ms |

These small samples are sensitive to renderer scheduling and do **not** establish a performance improvement, regression, or any physical input-to-photon latency. The changed field is telemetry: the test's short gestures contain far fewer than 4,096 stage batches, so they preserve the full previous timing series. No owner hardware result, hosted GitHub Actions pass, production export package, or new approval is claimed.

## Remaining gates

Measure sustained overlapping 60px input and the dense/multilayer cases on owner hardware, including actual held-input catch-up, p50/p95 and worst queue age, native paint/export and compositor/upload/frame bottlenecks. Continue necessary full-stroke optimizations. Obtain explicit owner re-acceptance of navigation and responsiveness before moving T-095 to Manual Review/Done; preserve T-096's independent Manual Review gate and do not merge PR #16 based on these software-only tests.
