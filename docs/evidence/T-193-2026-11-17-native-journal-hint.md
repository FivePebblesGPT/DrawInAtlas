# T-193 — Bounded rollback-journal membership hints during native rasterization (2026-11-17)

## Reproduction, scope and fail-first evidence

T-192 removed redundant native dirty-set insertions, but the Hokusai raster callback still probes its per-batch **authoritative rollback map** on every tile request. The unchanged real 96px hard-round, 512², **100-event** software-X11 baseline passed **two cold and two warm strict source/frame/history gestures** with confirmed exits 0, a single source SHA-256 `6df89cc963368830befd8dbf061db9bb0f40060556a8dfb127cf5e9681f68ec4`, cold complete-gesture p50/p95 **254.1/269.7ms**, warm **250.7/252.0ms**, native stage CPU p50 **71.0/76.5ms**, first postdraw **26.1/22.0ms**, and release→commit **121.3/124.5ms**. Raster remained roughly 50ms, delta scan ~7–10ms, with the rest in staging and frame/input scheduling. This is a real native GDExtension and source-backed, not a native-free surrogate or physical mouse-to-photon measurement.

The T-193 native regression initially **failed at compile time** because `TrackedSurface::reference_journal_lookup`, `journal_contains_probes` and `journal_cache_hits` did not exist; the failing compiler log is preserved (`raw/fail-first-native.log`). It checks repeated signed tile requests, the same tile after alternation, fresh batch state, rollback of newly created tiles, and preservation of prior pixels on a rejected batch. A second collision test verifies that a hint replacement **never overwrites the earlier snapshot**. All retained changes leave Hokusai's raster code, actual sample count, native/Canvas batch caps, **6ms soft drain**, mask/hidden RGB, preview and release contract unchanged.

## Retained bounded change and rejected trials

`TrackedSurface` now stores **32 direct-mapped batch-local key hints**, each an `Option<(i32,i32)>`. A matching hint proves that the key was already entered into that batch's rollback journal; it can skip the expensive map membership probe. A collision is only a hint miss: the authoritative map is checked before cloning/recording the tile. Hints are cleared at **begin, successful commit and rollback**; no unsafe tile pointer, persistent per-stroke snapshot, or source authority is introduced. `DRAWING_T193_JOURNAL_LOOKUP_COUNTERFACTUAL=1` forces the original per-request membership probe **in the same release binary**. Opt-in `DRAWING_T185_PROFILE=1` exposes `t193_journal_probes` and `t193_journal_cache_hits` beside native raster/scan/stage times.

Two earlier candidates are **retained as unsuccessful experiments**: a one-entry recent-key cache passed graphical parity but recorded **0/2,134 hits** in the 100-event rapid path, making its apparent speedup non-attributable; an eight-key linear ring did make **1,889** cache hits but regressed both cold and warm p50 in the first matched pair. Neither was retained. The final **direct-mapped** candidate has **1,840 hits and 294 map probes** per 2,134 rapid tile requests in optimized mode, versus **0 hits and 2,134 probes** in the reference mode (an **86.2% reduction in the *count* of journal membership probes**). It uses a fixed 32-slot structure and no new heap growth. This is a directly measured **work-count optimization**, not a demonstrated wall-clock speedup.

## Final release binary A/B (strict rapid gesture)

Final native library SHA-256: `f6472af4aa6150db710d72da0091e5a134ccaa1d95c84ef2dc0617d54fcdf2b0`. Two pairs ran in **reference→optimized** then **optimized→reference** process order. Each mode/pair includes **two independent cold processes and two warm strokes**, and every strict benchmark and checker exited **0**. All committed source SHA-256 values match the baseline above; Undo/Redo, coverage, no holes, selection and preview oracle remain enforced. Nearest-rank p95 for **n=2** is the maximum, not a population percentile.

| Pair / mode | Cold complete p50 / p95 (ms) | Warm complete p50 / p95 (ms) | Cold stage CPU p50 (ms) | Warm stage CPU p50 (ms) |
| --- | ---: | ---: | ---: | ---: |
| 1 reference | **240.7 / 258.5** | **253.9 / 256.9** | **68.9** | **69.8** |
| 1 hint | 253.4 / 278.5 | 295.9 / 352.9 | 76.1 | 71.7 |
| 2 reference | 266.9 / 276.7 | 263.1 / 281.4 | 78.9 | **67.8** |
| 2 hint | **259.1 / 261.7** | **259.1 / 296.6** | **70.7** | 72.0 |

First postdraw p50 was **26.9→29.2ms** cold and **20.8→21.1ms** warm in pair 1; **28.9→27.0ms** cold and **20.4→29.8ms** warm in pair 2. Release→commit p50 was **123.5→134.5ms** cold and **117.0→122.8ms** warm in pair 1; **138.8→122.8ms** cold and **135.6→133.3ms** warm in pair 2. Native exported volume is about **3.4MiB per gesture**, and observed per-process peak RSS is about **269–275MiB**. The counterfactual changes no authoritative raster/source work, but results **do not demonstrate lower complete-gesture p95 or native CPU**. Notably, the optimized pair-1 warm p95 is substantially *worse*.

The baseline and both rejected candidate variants are retained under `raw/baseline`, `raw/ab1-*`, `raw/ab2-*`, `raw/ab3-*`, including all strict checks and process time/RSS. Only `raw/ab5-*` and `raw/ab6-*` describe the **final** direct-mapped source/binary; do not pool all variants into one performance comparison.

## Full workspace / frame and release tails

Two reversed-order full-Drawing-process pairs (**four processes, all confirmed exit 0**) cover 32 native Brush/warm/held/Eraser gestures at 54% and 100% zoom. Source coverage, native backend, requested upload volumes and history checks remain unchanged. At 54% zoom:

| Pair / mode | Cold stage CPU (ms) | Cold release→settled (ms) | Cold frame interval p95 (ms) | Long frames ≥83.33ms | Eraser frame p95 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 reference | 48.7 | 118.3 | 15.5 | 1 | 41.3 |
| 1 hint | 52.4 | 120.2 | 22.0 | 2 | 40.4 |
| 2 reference | 51.5 | 125.6 | 24.3 | 1 | 40.5 |
| 2 hint | 69.8 | 122.1 | 23.4 | 1 | 36.7 |

The full-workspace cold requested upload volume remains **3,473,408 bytes** per scenario at 54%, and RSS spans roughly **325,540–328,000KiB** in the four processes. The `raw/work*/summary.json` files also contain complete first-preview, input backlog/oldest pending age, raster native stage and other frame phases, 100% zoom data, and release-to-settled. There is **no consistent frame-tail or release-to-settled improvement**, and long frames persist even with the hints. All FPS estimates here are derived from virtual callback intervals on llvmpipe, not real hardware display scanout.

## Correctness and validation boundary

- **34/34 Rust tests** passed, including two new journal regression cases; real final-source **83/83 graphical checks** passed with the native addon loaded (Brush/Eraser, masked signed/hidden-alpha source, frozen queued segments, undo/redo, cancellation, and real standalone Save/Open).
- Python toolchain and profiler parser tests **18 + 5 passed**, and Ruff/ty lint passed.
- Direct zero-exit integration passed: **32 native Brush**, **312 native tiles**, **42 standalone**, **16 preset selector**, and **43 Atlas native-history** checks.
- The broad `make check` timed out during **Atlas editor asset import**, after Python/lint/native preparation; **do not count the wrapper as passed**. Its raw interrupted log is preserved. The complete **`make test-graphical` rerun exited 0** (`raw/graphical-confirmed.exit`, `raw/graphical-confirmed.log`) with all nine suites green: T-181/T-186/T-187/T-188/T-189/T-190/T-191/T-192/T-193 (19/14/99/63/77/77/77/81/83 checks). An earlier graphical wrapper emitted all nine success markers but lacked its own captured exit, so it is not counted separately. Source and test-side generated Godot `.import` sidecars are not versioned.
- The raw directory contains every baseline, negative experiment, zero-exit A/B/workspace run, partial wrapper log, and its process `.time` file. `raw/SHA256SUMS` verifies retained raw evidence. Capture complete outer exits; a passing marker by itself is insufficient evidence of a successful wrapper.

**T-193 closes only this independently verified, reversible reduction in redundant native journal probes.** It does **not** claim the **250ms p95 milestone**, **200ms stretch goal**, broad FPS, physical owner acceptance or a reliable end-to-end latency win. The remaining performance/measurement boundary is [T-194](../Tickets/T-194.md) (Ready). T-095 hardware owner review, T-151/T-152 consolidation, T-148/T-149 native transition and T-105 Windows/export gates remain open; none were approved by this engineering change.

## Reproduction

Use the pinned native toolchain and `make import-drawing TOOLCHAIN=bundle BUNDLE=...`, then run `tools/run_t146_hokusai_bench.py --cold 2 --warm 2 --godot <bundled-godot> --output <path>` twice in reversed mode order with/without `DRAWING_T193_JOURNAL_LOOKUP_COUNTERFACTUAL=1` and `DRAWING_T185_PROFILE=1`. Run `tools/run_t185_profile.py --trials 1` for each full workspace mode, and `drawing/tests/t193_native_journal_cache.gd` under X11 (not `--headless`). The reference and optimized modes use the **same final release library**, distinguished only by the diagnostic environment variable.
