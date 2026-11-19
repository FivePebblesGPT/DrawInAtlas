# T-192 — Native batch write journal replaces duplicate dirty-tile hashing (2026-11-17)

## Current critical path and fail-first proof

The unchanged 96px, 512², 100-event Hokusai rapid benchmark first produced two valid cold gestures at **253.7/262.7ms**, two warm gestures at **253.7/259.7ms**, one complete native-only source digest (`6df89cc963368830befd8dbf061db9bb0f40060556a8dfb127cf5e9681f68ec4`), stage CPU **72–89ms**, first postdraw **22–30ms**, and release→commit **125–149ms**. Hokusai raster costs about **48–53ms**, fixed-point scan **7–10ms**, and native tile-stage/discovery is an additional cost. Composition CPU is about **2ms**, so this ticket does not change the display compositor or input deadlines. All observations require strict source/frame/history validation **and** process exit 0; a success marker alone is insufficient.

The new Rust regression **failed first** on missing `TrackedSurface::dirty_tiles_for_export()` (retained in `raw/fail-first-test.log`). A preliminary `make native` also failed only on formatting and is retained separately. The previous native surface inserted every raster tile request into a redundant `HashSet`, even though `before_batch` already records the exact set of requested native 64px tiles for atomic rollback. This cost is in raster callbacks, not GDScript, and does not require changing Hokusai, sample count, 6ms soft input-drain deadline, masks or undo ownership.

## Bounded code change

During a pending native batch, production `TrackedSurface` now reuses `before_batch` keys as its scan candidates. The old `changed` set remains for out-of-batch calls, and `DRAWING_T192_DIRTY_SET_COUNTERFACTUAL=1` restores the former per-request dirty-set tracking during batches **within the same native binary**. Both modes sort candidate coordinates before the existing fixed-point scan, retain the same tile snapshot and rollback semantics, and publish only quantized pixel changes. On a 100-event 96px gesture **2,134 Hokusai tile requests** were made in each mode: redundant dirty-set insertion attempts dropped **2,134→0** while the optimized path scanned **240 unique per-batch journal keys**. The gain established directly is avoiding unnecessary hash work, **not** a confirmed end-to-end latency gain.

A 32-test Rust suite includes repeated writes to existing/new *signed* tiles, exact dirty-set keys, and rejection rollback; the real 81-check T-192 graphical same-binary test checks Brush/Eraser exact source, hidden RGB, subtractive mask, signed pixels, queue/interpolation/frozen settings, cancellation, history, and portable Save/Open. It also asserts equal native tile request and batch counts and the counterfactual dirty-set operations. The first graphical instrument runs did not test the new native binary (the staged addon had not been refreshed); later a test harness typo used the wrong counterfactual variable. Their unsuccessful logs are retained, with the corrected **81/81 zero-exit** run on the matching staged binary. These are fixture/setup failures, not unexplained pixel mismatches.

## Rapid same-binary paired results

Each listed mode/pair contains **two cold processes and two warm gestures**. Every process exited **0**, strict checker exited **0**, source hashes matched, and preview/commit/Undo/Redo/mask invariants passed. Pair 2 reverses the process order. Reported p95 is nearest-rank (with n=2, simply the maximum): **not a statistical population tail**.

| Pair / mode | Cold complete p50 / p95 (ms) | Warm complete p50 / p95 (ms) | Cold stage CPU p50 (ms) | Warm stage CPU p50 (ms) |
| --- | ---: | ---: | ---: | ---: |
| 1 old dirty set | 268.3 / 370.8 | 268.5 / 408.1 | 74.9 | 75.6 |
| 1 write journal | 276.4 / 278.0 | 287.6 / 304.8 | 81.2 | 76.7 |
| 2 old dirty set | 267.9 / 268.0 | 263.8 / 281.5 | 78.7 | 78.5 |
| 2 write journal | 266.2 / 289.7 | 266.4 / 280.1 | 82.5 | 77.9 |
| Final instrumented old dirty set | 251.5 / 277.6 | **227.7 / 232.3** | 80.0 | **68.7** |
| Final instrumented write journal | **248.0 / 250.4** | 251.4 / 279.3 | **71.3** | 73.3 |

The final instrumented binary emitted identical committed source SHA-256 digests in all runs. At 96px, first postdraw p50 in the final comparison was **27.5ms old→26.8ms journal** cold and **19.1→20.4ms** warm. Release→commit p50 was **130.5→124.0ms** cold and **111.4→124.4ms** warm. Native raster stays near **48–55ms**, scan near **7–10ms**; the new operation-count change does **not** consistently reduce total stage CPU or complete-gesture time. Both modes emitted comparable native tile byte volumes (~3.6–3.9MB per rapid gesture), and process peak RSS was **269,704–272,304 KiB old** versus **270,180–275,164 KiB journal** in the final matched pair. There is no established memory improvement. Some individual medians cross 250ms, but the declared **250ms p95** and **200ms stretch** are **not reliably met**.

## Full Drawing workspace and frame pacing

Two reversed-order pairs each ran **one valid zero-exit full-workspace process per mode** (four processes, 32 complete cold/warm/held/Eraser gestures at 54%/100% zoom). All 16 paired changed-source hashes agree, with the same frozen 14-event cases, compositor path, requested upload volume and native backend. At 54% cold Brush, journal vs dirty set:

| Pair | Stage CPU (ms) | Release→settled (ms) | Postdraw interval p95 (ms) | Long ≥83.33ms frames |
| --- | ---: | ---: | ---: | ---: |
| 1 old→journal | 50.9→49.3 | 141.6→101.9 | 24.2→16.1 | 1/35→1/44 |
| 2 old→journal | 59.9→49.3 | 115.5→108.8 | 23.4→21.1 | 1/36→1/45 |

At 54% Eraser, interval p95 was **38.1→34.7ms** in pair 1 but **33.5→46.9ms (worse)** in pair 2; release→settled also varies both ways. Upload requests are **3,473,408 bytes** for each 54% cold source scenario, native exported tile bytes **4,521,984**; backlog/age, frame CPU phases, first preview, complete settled times and source hashes appear per case in `raw/work*/summary.json`. Peak RSS for four processes was **322,420–323,788 KiB dirty set** versus **323,640–325,772 KiB journal**. Every cold 54% process still has one ≥83.33ms long interval; no hardware FPS or physical scanout/input-to-photon claim follows from these software-rendered X11/llvmpipe callbacks.

## Validation boundary

The new Rust unit suite passed **32/32** and the dedicated real graphical parity suite passed **81/81** after correctly restaging the native binary. The offline **`make check` rerun exited 0** (Python toolchain/profiler tests, Ruff/ty lint, 32 Rust tests, 32 native Brush, 312 native tile, 42 standalone, 16 preset and 43 Atlas-history checks). The complete **`make test-graphical` exited 0**, including T-181/T-186/T-187/T-188/T-189/T-190/T-191/T-192 (19/14/99/63/77/77/77/81 checks). The release native library used for final rapid/full-workspace and the final graphical test is SHA-256 **`93ff1ab143150aa233058a96dd1c925b70ded5be862e8152fb079e52fafc7281`**; its build and stage logs are retained. All runs are recorded in `raw/`, with true exits distinguished from intermediate success markers. The original combined `make test` exceeded its outer timeout during native compilation and the first `make check` wrapper did not provide a captured exit despite printing native/Atlas pass markers; neither incomplete run is counted as a success.

**T-192 closes only the independently verified duplicate dirty-work reduction.** It does not close the performance targets: [T-193](../Tickets/T-193.md) is the next bounded critical-path investigation. T-095 hardware/owner approval, T-151/T-152 post-consolidation gates, T-148/T-149 native authority and T-105 Windows/export gate remain untouched. No manual review is self-approved.

## Reproduction

With the pinned bundle, build native and stage Drawing, then use `tools/run_t146_hokusai_bench.py --cold 2 --warm 2 --godot <bundled-godot> --output <folder>`, repeating with and without `DRAWING_T192_DIRTY_SET_COUNTERFACTUAL=1` in reversed process order, `DRAWING_T185_PROFILE=1` to capture phase/counter details, and `tools/run_t185_profile.py --trials 1` for full-workspace cases. Run `drawing/tests/t192_native_batch_journal.gd` under X11 with the **staged matching native library**. `raw/SHA256SUMS` pins each retained source log, JSON summary, process-time/RSS file and failed/incomplete attempt. Source-generated logs do not establish zero exit unless captured separately.
