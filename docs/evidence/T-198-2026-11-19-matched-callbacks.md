# T-198 — Gesture-local Canvas callback periods, not global frame-rate claims

**2026-11-19 · Done (diagnostic-only bounded child of T-197).** No painting,
rendering, input scheduling, native layout, persistence or source logic changed.

## Problem and change

The full-workspace profiler already recorded *global* Godot
`RenderingServer.frame_post_draw` callback gaps and separate, limited Canvas
`frame_phases_us` records. The global series contains callbacks unrelated to
an in-progress stroke, and gaps at gesture boundaries. It cannot independently
establish that those gaps are live-painting frame stalls. Conversely, a Canvas
frame without a matched callback cannot be assumed fast.

`tools/run_t185_profile.py` now adds a `matched_canvas_callback_gaps`
summary per scenario. It measures intervals only between **consecutive**
`frame_phases_us` records with strictly increasing matched callback stamps,
never across gesture boundaries; the earlier raw global series is retained
unchanged. Missing and nonmonotonic pairs are counted separately. The
summary records nearest-rank p50/p95/max, exact ≥33.333ms / ≥83.333ms counts
and up to the latest 32 long-event annotations with that frame's Canvas
CPU draw duration, renderer-callback delay and input backlog. The outlier
sample is explicitly bounded and counts cover the complete retained
frame-phase window, which itself is bounded by the Canvas recorder.

Callback intervals are **engine callback periods, not physical scanout or
mouse-to-photon latencies**. A matched interval does not imply that its
current Canvas draw caused a delay. A missing callback prevents attribution.

## Retained source and independent process proof

Re-ingested, without rerunning the renderer, the four successful X11
reference/optimized/optimized/reference full-workspace profiles from
[T-197 native display evidence](T-197-2026-11-18-native-display.md).
Each process has a preserved log, `/usr/bin/time -v` `Exit status: 0`, the
T-185 strict success marker, all eight real 96px native Hokusai transactions,
and matching canonical after-source RGBA8 hashes across all processes.
Inputs remain the already-recorded current 54% / 100% cold/warm/held Brush
and Eraser cases, 32 completed gestures total. The original incomplete-exit
attempt is retained in T-197 evidence, **not** counted here.

| Process | Mode | Global intervals ≥83.333ms | Matched adjacent Canvas pairs | Adjacent pairs without callbacks | Long matched ≥83.333ms | Max matched interval |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 0 | Reference | 5 | 115 | 83 | 0 | 37.531ms |
| 1 | Optimized | 5 | 156 | 42 | 0 | 23.602ms |
| 2 | Optimized | 5 | 136 | 62 | 0 | 22.130ms |
| 3 | Reference | 4 | 134 | 64 | 0 | 34.495ms |
| **Total** | | **19** | **541** | **251** | **0** | |

The 19 long *global* callbacks are therefore not 19 **verified** painting
frame gaps. But 251 unmatched adjacencies preclude concluding that all live
painting frames stayed under 83.333ms. The underlying report also includes
per-gesture distributions and the source-log/time SHA-256 fingerprints:
[`T-198-2026-11-19-matched-callbacks.json`](T-198-2026-11-19-matched-callbacks.json).

## Tests and acceptance boundary

- Fail-first: five new unit cases errored because the diagnostic did not
  exist. After the implementation, they pass, covering unmatched callbacks,
  out-of-order/duplicate times, no cross-gesture joins, absent timestamps,
  and a 99-event sample whose exact counts outlive bounded detail retention.
  A sixth integration test reparses all four retained source logs, requires
  independent successful process exits, matching canonical source hashes,
  and asserts the complete 541/251/19 count tuple.
- Existing T-185 parser tests remain authoritative for completed native
  transactions, source hashes and confirmed process exits; preserved tests
  still pass. Each of the four retained raw logs was reparsed under the
  new implementation before computing the table.
- The 200ms strict complete-gesture p95, frame pacing under real hardware,
  actual mouse-to-photon latency, native consolidation, Windows export and
  owner signoff are **not** completed. Keep T-197 In Progress and T-095 and
  all native/portability gates unchanged. No same-binary performance claim:
  this milestone changes report interpretation, not rendering.

## Fresh local validation (2026-11-19)

The supplied offline native toolchain rebuilt successfully, with **35/35
Rust tests**. Python `make python-test` passed **30 tests** (toolchain 19,
existing profiler 5, T-198 6); pinned Ruff and ty passed and the ticket
validator accepted **198 tickets** and unchanged manual-review gates.
After native staging, graphical T-197 first-preview **9/9**, T-187
source-exact display parity **183/183** and T-196 release/preview **99/99**
all exited 0. Individual Drawing native/headless suites also exited 0:
Brush 32/32, tile contract 312/312, standalone smoke and preset controls
16/16. Atlas history first failed to parse because the root project was
not imported; a subsequent explicit root editor import exited 0, and the
retry passed 43/43. The aggregate `make test` was **terminated by execution
timeout during the Drawing editor import** and is **not counted as passed**.
The complete validation outputs and both failed attempts are retained in
[`T-198-2026-11-19-validation/`](T-198-2026-11-19-validation/).
No hardware acceptance, hosted CI or Windows export has been performed.
