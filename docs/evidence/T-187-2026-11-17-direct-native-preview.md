# T-187 — Native single-layer preview, measured against the original compositor

**Date:** 2026-11-17 · **Environment:** same pinned offline Godot 4.8.beta3,
Hokusai/libmypaint and Rust GDExtension, Xvfb 1280×900, Mesa llvmpipe,
`gl_compatibility`, virtual input. Not monitor scanout or owner-device
performance. **Base:** T-186 at `cd50daf`; this ticket adds no other pipeline
rewrite. The acceptance metric remains the T-146 **100-event, 96 px, 512²**
`total_to_postdraw_ms`, including real framebuffer postdraw.

## Why this candidate

- T-186's exact dirty stamps reduce unnecessary uploads but still spend roughly
  **183–231 ms cumulative CPU** compositing rapid single-layer previews in
  GDScript, versus **115–139 ms native staging** (snapshot-dependent).
- An **initial rejected approach** copied a cropped native tile then still
  blended every destination pixel in GDScript. Exports fell from about
  **5.77–6.29 MB** to **3.08–3.21 MB** per rapid gesture, but the matched cold
  p50 moved **496.9→597.9 ms**. The prior native binary for this preliminary
  experiment is not pooled with the final same-binary counterfactual.
- The retained change uses Rust's *bounded, row-cropped RGBA8 read* directly
  **only** when one visible raster layer exactly supplies the view within one
  256 px storage tile. The fast path first resolves the lazy source and checks
  its revision. If native data is unavailable, any alpha-zero pixel contains
  hidden RGB, the view crosses a storage-tile boundary, or text/multiple
  layers are visible, the existing compositing behavior runs unchanged.
  This is an optimization, not an alternative Brush/Eraser backend.
- Preview crops have an **eight-entry per-storage-tile cache cap**, cleared on
  each changed native batch, commit, and cancel; canonical tile/history data
  remain full RGBA8 and Rust-owned. The 128 px visible warm-tile stamp index
  and T-181/T-186 invalidation behavior are unchanged.

## Strict, repeated same-source/native-binary A/B

`DRAWING_T187_FULL_TILE_COUNTERFACTUAL=1` forces the original compositor in
**the same checkout and native binary** as the default direct path. This switch
is off by default and is diagnostic-only. Both A/B pairs used native library
SHA-256 **`217c0b28f4e4f360e29dac80dea5b566cb2483139d1b7437321ea60cc63b8741`**.
Their full-workspace source/preset hash lists and Godot identity match exactly
in `matched/direct/workspace/summary.json` and
`matched/direct-full-fallback/workspace/summary.json`. All rapid runs returned
zero, passed their independent log validators, verified 262,144 covered source
pixels, native mask/hidden RGB, five framebuffer points, cancel/retry,
Undo/Redo, and retained the same committed source digest
`6df89cc963368830befd8db9bb0f40060556a8dfb127cf5e9681f68ec4`.

Rapid values are p50 / nearest-rank p95 in **milliseconds**; each mode has
*two cold gestures in fresh processes and two warm gestures in one process*,
per comparator and per repetition. Do not misread the tiny-sample p95 as a
confidence bound. Complete raw logs, `/usr/bin/time -v` RSS/exit records and
parser summaries are under [the raw directory](T-187-2026-11-17-raw/).

| Run pair, unchanged full metric | Fallback cold p50 / p95 | Direct cold p50 / p95 | Fallback warm p50 / p95 | Direct warm p50 / p95 |
| --- | ---: | ---: | ---: | ---: |
| First same-binary A/B | 742.2 / 742.3 | **312.4 / 383.3** | 586.1 / 598.3 | **337.5 / 357.8** |
| Independently repeated A/B | 520.6 / 582.2 | **341.6 / 345.0** | 479.8 / 520.1 | **303.7 / 351.3** |

| First A/B 96 px metric (p50 / p95) | Fallback cold → direct cold | Fallback warm → direct warm |
| --- | ---: | ---: |
| Release→commit (ms) | 602.1 / 609.9 → **186.1 / 264.9** | 460.1 / 480.6 → **214.0 / 236.4** |
| Cumulative composition CPU (ms) | 242.7 / 265.6 → **1.9 / 2.6** | 222.0 / 232.0 → **2.3 / 2.3** |
| Native stage CPU (ms) | 174.1 / 198.2 → 114.6 / 131.4 | 132.7 / 132.8 → 128.4 / 130.9 |
| First preview postdraw (ms) | 47.8 / 50.8 → **32.1 / 32.6** | 41.1 / 41.2 → **20.1 / 28.7** |
| Native exported bytes (MB, p50) | 6.55 → **3.74** | 6.55 → **3.74** |

Repeated A/B confirms composition CPU around **1.6–2.3 ms p50** with direct
previews versus **170–178 ms** with fallback. Rapid RSS for the first A/B
peaked at **269,428–273,696 KiB** direct and **271,136–275,056 KiB** fallback
across fresh/cold and same-process/warm trials. Neither mode moves its gain
into a longer post-release commit; the complete metric and release→commit
both improve. Results vary between processes, so individual ms differences
outside the compositor are not a reliable causal claim.

**Target gate remains open:** neither repeated *cold nor warm* p50/p95 meets
**≤250 ms**, much less **≤200 ms**. These thresholds are **not** replaced by
composition CPU or by the full-workspace paced gesture. Remaining typical
staging CPU is ~113–137 ms per rapid gesture, alongside main-thread/native
FFI, event delivery and post-release/commit/settled display work. Further
independently measured work is tracked in **T-188**, not hidden in T-187.

## Full real workspace, same native and source snapshot

`tools/run_t185_profile.py` captured eight independent scenarios *per
process*, with one confirmed zero-exit process per A/B mode. The table gives
**frame-postdraw callback interval** p50 / p95, *not physical FPS*. The
first-process p95 has limited repeatability; all eight rows and their
frame arrays, stage timing, RSS and source/oracle identity are preserved.

| Scenario | Compose CPU fallback → direct (ms, cumulative) | Frame interval fallback → direct (ms, p50 / p95) | ≥83.33 ms intervals fallback → direct |
| --- | ---: | ---: | ---: |
| 54% cold Brush | 299.4 → **2.8** | 10.5 / 75.4 → **11.4 / 26.6** | 1/29 → 1/29 |
| 54% warm Brush | 262.7 → **3.3** | 11.9 / 75.9 → **8.9 / 21.6** | 1/27 → 1/39 |
| 54% held Brush | 208.4 → **2.3** | 12.8 / 62.4 → **11.8 / 24.7** | 0/29 → 0/37 |
| 54% Eraser | 287.6 → **85.0** | 13.4 / 70.1 → **11.4 / 35.0** | 1/30 → 1/29 |
| 100% cold Brush | 268.2 → **2.9** | 9.5 / 72.7 → **11.1 / 21.6** | 1/31 → 1/38 |
| 100% warm Brush | 239.7 → **2.7** | 11.5 / 59.8 → **9.0 / 23.1** | 1/29 → **0/41** |
| 100% held Brush | 190.5 → **2.6** | 10.7 / 55.1 → **10.1 / 30.1** | 0/28 → 0/36 |
| 100% Eraser | 271.4 → **82.5** | 9.1 / 63.7 → **15.5 / 41.5** | 1/30 → 1/26 |

For 54% cold Brush: first postdraw **62.1→36.7 ms**, oldest pending input age
p95 **16.7→0.8 ms** (peak queued count 1), release→settled postdraw
**113.3→112.3 ms**, full paced down→settled **782.7→496.1 ms**.
Requested texture uploads remain **3.47 MB** (same visible pixels), while
native preview/export deltas fall **6.82→4.52 MB**. One-process workspace
peak RSS **326,196→326,544 KiB** (a small increase, not a claimed memory
reduction). Eraser retains the compositor on some transparent pixels with
hidden RGB: it improves less and is intentionally not falsely called a
full fast-path case. The long-frame fraction does not uniformly fall, even
though p95 improves: the retained single long interval matters.

## Correctness and unsuccessful attempts

- Native Rust crop test compares every row against the full canonical tile,
  tests signed origins, invalid/boundary rectangles and post-commit pixels.
  The native API is only a read: it does not modify source, committed masks,
  selection, stroke timing or history.
- The real X11 T-187 test forces the compositor in the same session and
  compares the complete resulting renderer `Image.get_data()` byte arrays for partial alpha,
  hidden alpha-zero RGB, signed source tile, and two visible layers; also
  checks native byte counters, exact crop lengths and Undo/Redo. Its initial
  five assertion failures resulted from prewarmed tile caches when the test
  expected uncached export counts; **the first failed log is retained**.
  After explicitly clearing read caches the original test passed 36/36.
  A final cache-bound test initially failed 3 checks because Drawing's staged
  copy had not been refreshed, rather than a source bug; the failed log is
  likewise retained. After staging, the expanded test passes **99/99**.
- Native release build and **27 Rust unit tests**, full Python/lint/native,
  standalone and Atlas integration `make check` pass with zero exit. A
  separate `make test-graphical` passes T-181 **19/19**, T-186 **14/14** and
  the initial T-187 **36/36**. The final expanded T-187 runs independently
  **99/99** after restaging. This bounded-cache-only source change followed
  the matched performance captures; it does not change the ordinary 128px
  source-to-display fast-path decision, and the exact-byte graphical oracle
  was rerun on the resulting code. See raw `checks/` for both passes and failures.
  `make check` covers 312 native tile assertions, 32 native Brush assertions,
  42 standalone, 16 presets and 43 Atlas history checks, including real
  Save/Open and Undo/Redo paths.
- A separate rejected crop-only variant, its zero-exit logs, and the
  initial pre-change rapid baseline are retained in `matched/cropped/` and
  `baseline/`. The old mode is available only as an explicit diagnostic flag;
  it is **not a native-free Brush fallback**.

**Unclosed gates:** T-188 owns the residual 250/200 ms target. T-095 retains
physical owner review; T-151/T-152 remain post-consolidation; T-148/T-149,
T-105 and other broader native/export acceptance are not inferred from this
software-X11 result. T-187's bounded engineering change can be Done without
claiming those independent gates are approved.
