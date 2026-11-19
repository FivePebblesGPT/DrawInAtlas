# T-188 — Run-aware native staging, measured against per-pixel grouping

**Date:** 2026-11-17 · **Scope:** exactly one bounded native delta-processing
optimization after T-187's direct single-raster-layer preview. Godot
4.8.beta3, pinned Rust/Hokusai `toolchain.lock.toml` and Cargo lock, Mesa
llvmpipe/X11 via Xvfb 1280×900, `gl_compatibility`, 96px Hokusai hard-round,
100 rapid pointer events across a 512² image. This is software framebuffer
postdraw and engine input receipt, **not** device input-to-photon/FPS evidence.

## Causal profile and retained change

The T-187 direct preview removes most GDScript compositing; it does **not**
remove native staging. Fresh T-188 opt-in counters separate the unchanged
native 100-event stroke's batch cost. The instrumented baseline had ~51ms
Hokusai rasterization, ~19–21ms changed-pixel quantization/delta scan,
~36–40ms canonical Rust tile application, and ~9–10ms native required-tile
discovery, across 20 batch calls / 296 interpolated segments. The total
Canvas staging CPU is ~110–145ms, with separate release/commit/postdraw work.
The nested per-phase counters are **not** independent additive wall timings.

Both `DrawingNativeBrush.required_tiles` and
`native_tiles::TileStore::stage` previously did a `HashSet`/`HashMap` lookup
for **each quantized changed pixel**, although Hokusai emits spatially
clustered consecutive runs. Native grouping now performs those lookups on
**storage-tile run boundaries** and appends revisited runs in original pixel
order. Every delta still goes through signed-overflow, clipping and alpha
preflight, unchanged mask/source authorizations and the same atomically
rollback-able edit transaction. No source tile/preview frames are discarded,
no sample geometry or event batching changes, no new rasterizer/ABI is added,
and the 6ms soft drain budget remains unchanged. The Rust grouping test
compares exact per-storage-tile delta order, signed cross-boundary revisits,
clip filtering and Brush/erase alpha in both paths, and checks that run-aware
hash probes are fewer than pixel-by-pixel probes. Diagnostic
`DRAWING_T188_PIXEL_GROUP_COUNTERFACTUAL=1` forces the original lookup path
inside the **same binary**; it is not a native-free user fallback. Opt-in
`DRAWING_T185_PROFILE=1` enables stage and native CPU-phase observations.

A **rejected** preliminary 32-segment native batch idea reduced FFI calls but
increased peak native stage time in early X11 trials, without reliable
whole-gesture benefit. It was removed rather than combined with the retained
run-aware native change; raw `prototype/batch32/`, baseline and failed
attempts remain in [raw evidence](T-188-2026-11-17-raw/).

## Strict 100-event benchmark — repeated, same-binary per pair

`tools/run_t146_hokusai_bench.py --cold 2 --warm 2 --timeout 65` is the
**unchanged** T-146 witness. Every valid process has a confirmed zero exit,
log marker, independent 262,144-pixel coverage, framebuffer points, mask and
hidden-RGB fixture, cancel/retry, one-step history and Undo/Redo digest.
Each row below is a separate **same-Godot, same-native-binary** A/B pair, with
2 cold independent processes and a 2-gesture warm process *per mode*. p95 is
nearest rank of 2 (the maximum), **not** a confidence interval. `p50/p95`
are full `total_to_postdraw_ms`, including the actual framebuffer postdraw.
Counterfactual → run-aware:

| Matched round · native SHA prefix | Cold p50/p95, ms | Warm p50/p95, ms | Cold stage p50, ms | Warm stage p50, ms |
| --- | --- | --- | ---: | ---: |
| First complete stage+discovery A/B · `67418f8759f0` | 324.0/379.1 → **351.9/352.0** | 290.7/345.9 → **276.3/297.0** | 120.6 → **116.6** | 112.3 → **97.0** |
| Final release A/B · `7b3c291e4570` | 388.1/494.1 → **266.4/421.5** | 357.8/449.7 → **285.7/296.7** | 142.6 → **100.7** | 125.3 → **103.7** |

**Do not conceal the first round's cold median worsening.** The causal native
stage cost falls in both pairs and both modes, but the complete gesture has
large process noise. The final round's 266.4ms cold p50 is **not below 250ms**.
Across both rounds all **16 rapid strokes** returned zero, have identical
native-generated source SHA-256
`6df89cc963368830befd8db9bb0f40060556a8dfb127cf5e9681f68ec4`,
and recorded complete source/framebuffer/Undo/Redo checks. Native release
identity for the **final** A/B is
`7b3c291e4570500f2087c1a62e844cde5a7689ebdcf45fcbe12fa880260798e9`.
The preliminary `matched/` stage-only pair used a different binary and is
**not** pooled with the complete stage+discovery comparisons.

### Stage, transfer, preview and release (final pair)

| Metric · p50 | Pixel-by-pixel | Run-aware |
| --- | ---: | ---: |
| Cold native tile application | 44.1ms | **29.3ms** |
| Cold required-tile discovery | 11.6ms | **2.0ms** |
| Warm native tile application | 38.5ms | **28.0ms** |
| Warm required-tile discovery | 10.4ms | **2.0ms** |
| Cold release→commit | 253.9ms | **152.6ms** |
| Warm release→commit | 231.7ms | **162.3ms** |
| Cold first preview postdraw | 25.4ms | **33.3ms** (slower) |
| Warm first preview postdraw | 26.5ms | **23.8ms** |
| Native preview bytes exported, cold | 3,932,160 | 3,604,480 |
| Native preview bytes exported, warm | 4,259,840 | 3,932,160 |

Transfer/preview byte differences reflect actual scheduling and read-cache
behavior in the measured process; no byte-suppression or upload optimization
was implemented by this ticket. Raster and changed-pixel scan work remain
comparable. The final two counterfactual cold release values include a large
outlier, so it would be incorrect to extrapolate the release p50 improvement
to paced input or physical latency. The rapid trials' per-process peak RSS
stays in roughly **270–274 MiB** for both modes; no memory saving is claimed.

## Real full-workspace frame pacing — two matched pairs

`tools/run_t185_profile.py --trials 1 --timeout 90|95` ran **two independent
processes in each mode** (four confirmed zero exits), eight real native
Brush/held/Eraser scenarios per process, at both 54% and 100% zoom.
All source/preset/native hashes and the current code snapshot match within
each pair; the optimized binary is the final A/B SHA above. For **54% cold
Brush**, frame-postdraw callback intervals (not physical FPS) are:

| Run | Pixel-group frame p50/p95, ms; ≥83.33ms | Run-group frame p50/p95, ms; ≥83.33ms |
| --- | --- | --- |
| 1 | 8.0/19.9; **1/44** | 9.0/35.6; **1/39** |
| 2 (reverse order) | 9.5/23.4; **1/35** | 10.8/24.4; **1/30** |

The stage CPU reduces in these two scenarios from **77.8→69.1ms** and
**80.8→71.9ms**. Required-tile authorization reduces from **7.9→3.4ms**
and **8.2→2.3ms**. Requested texture upload volume remains exactly
**3,473,408 bytes** in all four cold 54% runs. Pending-input frame depth
p95 remains **1** in all four, with no dropped events; first preview
postdraw fluctuates (35.5→31.5ms and 33.5→46.1ms). Release→settled
is **109.6→135.4ms** and **108.4→107.5ms**: one run is worse. These observations are at **54% zoom** and cannot support a
claim of universally improved frame pacing or release latency. The native
stage improvement is real, but each process still has at least one
≥83.33ms frame and the frame p95 varies in both directions.
The 54% warm overlap, held Brush, Eraser, and 100% scenes are all retained in
the raw 8-scenario summaries; none is counted as a performance acceptance
substitute. Full-workspace peak RSS: counterfactual **323,968/325,424 KiB**;
run-aware **323,632/323,724 KiB**, a small, noisy comparison.

## Correctness, incomplete attempts, and gates

- Rust **28/28** tests pass (new signed/clip/revisited-run unit test, existing
  Rust tile authority and Hokusai stroke rollback/alpha tests). The new X11
  real-native graphical T-188 scenario passes **63/63** across both
  counterfactual modes, signed raster ownership, hidden RGB, a subtracted
  selection hole, queued interpolated events, native Brush/Eraser, cancellation
  and exact source/Undo/Redo parity.
- Regression suites on the final release binary: T-181 **19/19** warm tile
  retention, T-186 **14/14** dirty index, T-187 **99/99** direct preview and
  cache cap, and T-188 **63/63**. Direct native Brush integration **32**, native
  tiles **312**, preset controls **16**, Atlas history **43**, standalone
  Drawing smoke, Python packaging **18** and profiling parser **5** tests
  pass. Ruff and ty lint pass. Save/Open and frozen/queued/source contracts
  remain under the established regressions; the T-188 graphical comparison
  independently checks the two native commit/history paths.
- The first T-188 X11 fixture failed **2/63** only because the test's
  hidden-RGB integer expected the wrong byte order; the retained first log
  demonstrates that, and final test passes. A native test assertion first
  failed compilation because of an incorrect tuple destructuring, then
  separately rejected two out-of-range signed `i32` hex test literals;
  corrected test build passes 28. The broad `make check` was **not** green:
  its first attempt stopped at the test compilation failure and its second
  attempt timed out while importing the Atlas editor after Python/lint.
  Direct native, headless integration and X11 graphical suites were rerun
  with confirmed zero exits. All failing/incomplete outputs are preserved.
- The experiment does **not** meet **250ms**, nor the **200ms stretch** under
  the pinned unchanged full-gesture metric. Further single-hotspot work is
  separately [T-189](../Tickets/T-189.md) (Ready). Owner physical testing
  remains T-095; T-151/T-152 post-consolidation, T-148/T-149 universal
  native history and T-105 export gates remain open. No manual or hardware
  approval has been assumed.

[Raw source, benchmark/process logs, failed attempts, checks and SHA manifest](T-188-2026-11-17-raw/).
