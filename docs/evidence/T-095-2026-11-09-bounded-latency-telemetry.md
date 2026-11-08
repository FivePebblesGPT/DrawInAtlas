# T-095 — bounded input-to-stage telemetry during sustained Brush strokes

**Date:** 2026-11-09
**Ticket:** T-095 (`In Progress`, `manual_review: true`)
**Environment:** Godot `4.8.beta2.official.cafc17a19`, Linux Xvfb 1280×900×24 / Mesa software GL for pointer timings, and headless Godot for the source-pixel model. This is not owner-device input-to-photon evidence.

## Defect and scope

The previous sustained-input fix bounded the retained `_samples` and `_sample_times_us` queues. However, `_drain_segments()` still appended one input-to-stage latency per completed source waypoint to `_metrics["sample_to_stage_us"]`. The list was unbounded; `_commit_stroke()` then deep-copied it into `last_gesture_metrics`. Therefore a long uninterrupted Brush stroke still retained an amount of profiling memory and performed a final metrics copy proportional to the *total* input count, even after all source waypoints were consumed.

`DrawingCanvas` now retains **all** latencies for strokes of at most **4,096 samples** (the existing standard 122-sample profiling API is unchanged). For longer gestures, the oldest values are replaced by the newest values in a fixed 4,096-element ring. Only at successful commit is this window rotated to chronological order for `last_gesture_metrics`. The new `sample_to_stage_total` field counts every completed source sample, and `max_sample_to_stage_us` retains the **exact lifetime worst age**, even when its individual sample falls out of the retained window. Negative timing deltas clamp to zero as before. Because the retained distribution is now only the latest 4,096 arrivals for long gestures, its p50/p95 are **window statistics**; do not mislabel them whole-stroke percentiles. The lifetime maximum and count stay exact. Existing capped `stage_batches_us`, queue metrics and frozen source coordinates are unchanged.

This is **a profiling-memory/copy bound**, not a new rasterizer or a claim of improved input-to-photon latency. It does not change Brush/Eraser geometry, native Hokusai output, selection masks, source/preview pixels, camera policy or document history.

## Independent oracle and negative control

`drawing/tests/t095_latency_window_smoke.gd` passes **22/22** checks with the strict `T095_LATENCY_WINDOW_PASSED` marker. It verifies:

- A five-sample gesture retains every timing value in original order, including zero clamping.
- A synthetic 15,000-completion stream never exceeds 4,096 entries; after rollover, the retained samples are the exact newest 4,096 in chronological order. The earliest sample is deliberately the slowest and remains in the exact lifetime maximum after eviction.
- An exact multiple of the ring capacity wraps without incorrectly rotating an already ordered full window.
- A real **4,602-sample**, 3px Brush capture at 786% zoom drains after mouse-up and zoom/camera/toolbar Pan changes, publishes once, retains only 4,096 latency samples with an exact 4,602 completion count, and matches an independent unsliced edit's canonical RGBA8 image and Undo/Redo bytes.

For a controlled negative run, only the standalone staged canvas was temporarily replaced by the previous committed source, keeping the same 4,602-event witness. It returned **4,602 retained latencies** and no lifetime count/max, failing two checks and the strict log validator. Restoring the optimized canvas returned **4,096 retained**, exact `sample_to_stage_total=4602`, and a strict pass. Canonical addon source remained unchanged during that negative control. Raw logs: `t095-turn11-negative-control-original.log`, `t095-turn11-negative-control-fixed.log`, `t095-turn11-latency-window-final.log` (local evidence, not GitHub Actions artifacts).

The new test is added to the **on-demand** `godot-native-t095-brush.yml`, not the required fast-CI inventory. Both test execution and post-exit diagnostics must pass the shared fail-closed validator.

## Neighboring tests and software timing

Selected local regressions passed: queue compaction **31/31**, independent hard-brush coverage **32/32**, Hokusai delta oracle **126/126**, signed native tile oracle **422/422**, T-085 headless live-stroke, Xvfb native preset integration **30/30**, post-release navigation **48/48**, native live stroke **125/125**, signed-pixel boundary **17/17**, and viewport cache **153/153 after regenerating missing Godot font imports**. The signed-boundary and native display logs still have previously observed engine shutdown/leak or audio fallback diagnostics; do not label them clean-shutdown evidence.

Two order-swapped five-stroke, 120-motions-per-stroke, **60px Legacy Brush / 786% zoom** Xvfb/Mesa comparisons passed the original pointer/framebuffer correctness witness:

| Run order | Previous staging p95 | Bounded-telemetry staging p95 | Previous release p95 | Bounded release p95 |
| --- | ---: | ---: | ---: | ---: |
| Previous → bounded | 134.327 ms | 144.872 ms | 59.941 ms | 62.316 ms |
| Bounded → previous | 141.887 ms | 162.502 ms | 68.885 ms | 70.488 ms |

This **does not demonstrate a speedup**; the updated runs were slower on these short controls, and staging CPU times are not materially affected by the recorder's work after each atomic batch. Do not infer that the difference is causal from five samples, or claim owner latency acceptance. The principal demonstrated benefit is the fixed upper bound on the long-gesture latency-history array and the bounded final deep-copy size.

## Remaining gates

T-095 remains **In Progress**, `manual_review: true`. Hosted on-demand CI, actual physical mouse-to-display response, export packaging and explicit owner re-acceptance remain outstanding. The unchanged legacy fallback remains default and T-096's independent Manual Review remains open. PR #16 is not to be merged by this checkpoint.
