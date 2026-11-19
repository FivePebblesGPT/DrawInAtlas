# T-195 — Bounded post-release native drain / remaining 200ms stretch (2026-11-17)

**Evidence:** [checksummed raw data](T-195-2026-11-17-release-catchup-raw/),
including `analysis.json`, the original strict X11 process logs, validation
reports, process exit codes, per-process `/usr/bin/time -v`, rejected variants,
fail-first failures and final Make outputs. This report is a source-pinned
small-sample engineering experiment, **not** physical mouse-to-photon or
population FPS acceptance.

## Baseline and measured culprit

The unmodified T-194 20-segment native production path passed the strict
native **96px Hard Round, 512² full-coverage, 100-event** 100%-source benchmark
(two independent cold processes, two warm gestures, confirmed exit 0 and
checker 0). Cold `total_to_postdraw_ms` was **231.4/238.0 p50/p95**; warm
**245.2/266.5**. Reference native stage CPU is roughly **72–79ms**, but queued
release→commit is typically **110–130ms**, suggesting release-frame scheduling
costs beyond Hokusai raster/preview composition. The ordinary live capture
retains a **20-segment** atomic cap and **6ms soft deadline checked between**
completed native batch calls, *not* inside a transaction or as a hard frame
limit.

Two candidate larger post-release caps were measured and **rejected**:
`28` segments (50→38 native stroke FFI calls) and `24` (50→44), each in
reversed-order same-binary A/B rounds. Both preserved exact source/historical
checks, yet cold/warm whole-gesture timing regressed or varied substantially.
Their raw `ref1/opt1/opt2/ref2` and `ref24a/opt24a/opt24b/ref24b`
logs/JSON are retained; no larger-cap candidate remains in production.

## Retained release-only scheduling change

After a released gesture's normal `_process()` drain, **at most one more**
`_drain_segments(MAX_SEGMENTS_PER_FRAME)` runs if unconsumed source samples
remain. This second call independently obeys the unchanged **6000µs soft
per-drain deadline**. The cap stays at **20 native segments** per atomic call,
input queues preserve every source sample and interpolation point, and capture
(before button release) never uses catch-up. Since a frame may now do two soft
bounded drains, this is **not** a claim that total `_process` CPU is under 6ms,
or that no longer frame can occur. A single extra bounded drain avoids waiting
for one more ~16ms callback per drain group, at the expense of potentially
longer individual frame callbacks. `DRAWING_T195_RELEASE_CATCHUP_COUNTERFACTUAL=1`
turns off only the extra drain using the **same release/native binaries**.
The prior T-194 16-vs-20 diagnostic remains independent and green.

The new real X11 T-195 regression intentionally failed **2/81** checks before
implementation (`raw/catchup-fail-first.{log,exit}`), then passed **81/81** after
implementation and **85/85** on its final source, including two explicit
capture-only checks per comparison mode. It compares signed tile RGBA8,
subtracted mask holes, partial alpha/hidden RGB, Brush, Eraser, full native
history/Undo/Redo, cancelled changes and real standalone Save/Open. The
independent strict 100-event witness additionally checks all 100 input events,
512² coverage, first submitted/post-draw preview callbacks, framebuffer
points, exact native source SHA, Undo/Redo, native tile APIs and no fallback.

## Final same-source, same-native-binary reversed-order rapid A/B

Order: **reference→optimized→optimized→reference**, each **two independent
cold processes and one two-gesture warm process**; 4 cold and 4 warm
observations per mode. All subprocess and checker exits are **0**. Native
release `.so` SHA-256:
`f6472af4aa6150db710d72da0091e5a134ccaa1d95c84ef2dc0617d54fcdf2b0`.
Every committed native source digest is
`6df89cc963368830befd8dbf061db9bb0f40060556a8dfb127cf5e9681f68ec4`.
The source Canvas SHA-256 is recorded in `analysis.json`; neither the native
Rust implementation nor brush preset files changed. Raw measurements and
identities are in `raw/refcatch1`, `raw/optcatch1`, `raw/optcatch2`,
`raw/refcatch2` and `raw/analysis.json`.

| Metric | Reference p50/p95 | Optimized p50/p95 |
| --- | ---: | ---: |
| Cold complete gesture + first settled postdraw | 239.2 / **303.5ms** | **214.5 / 252.6ms** |
| Warm complete gesture + first settled postdraw | 228.0 / **277.9ms** | **200.8 / 209.4ms** |
| Cold queued release→commit | 117.0 / 156.7ms | **101.9 / 141.4ms** |
| Warm queued release→commit | 107.4 / 144.3ms | **90.0 / 98.4ms** |
| Cold native/staging CPU | **75.1** / 91.0ms | 75.3 / 97.6ms |
| Warm native/staging CPU | 70.4 / 83.5ms | **67.1 / 72.9ms** |
| Cold first preview postdraw | **30.5** / 32.1ms | 39.6 / 44.3ms |
| Warm first preview postdraw | **26.0** / 37.0ms | 33.4 / 44.1ms |
| Native stroke FFI calls per gesture | 50 / 50 | 50 / 50 |

`p50` and `p95` are **nearest-rank** over four observations: the reported
`p95` is therefore the **worst measured observation**, not a population-tail
estimate. Release scheduling rather than reduced FFI transaction counts is
consistent with the improvement; native staging CPU is almost unchanged in
cold runs. First-preview timing was **worse in these samples**, though the
changed behavior is enabled only after release and this is not proof of a
causal preview regression. Some warm observations fall below 200ms, but
neither cold nor warm **p95** reaches the **200ms stretch**. The cold p95 of
252.6ms also exceeds the earlier T-194 **250ms** small-sample milestone by
2.6ms in this capture, so its achievement must not be generalized.

## Full Drawing workspace: two zoom levels and four gestures

The same 20-segment native binary was tested in two reversed-order full-workspace
pairs, all **four processes exited 0** and passed the eight-case oracle per
process (cold/warm Brush, held input, Eraser at **54%** and **100%**). Source
SHA, native APIs, full history, input count, native tile export and frame/first
preview assertions all pass. All eight cases and per-frame backlog traces are
in `raw/work-{ref,opt}{1,2}/summary.json` and their original logs.

| Cold Brush metric | Pair 1 ref→opt | Pair 2 ref→opt |
| --- | ---: | ---: |
| 54% release→settled | 107.0→107.5ms | 117.0→101.8ms |
| 54% process-frame interval p95 | 14.9→14.3ms | 15.6→17.2ms |
| 100% release→settled | 117.9→103.9ms | 130.7→114.0ms |
| 100% process-frame interval p95 | 21.7→15.6ms | 19.7→19.7ms |
| 54% Eraser release→settled | 115.1→107.7ms | 114.8→111.4ms |
| 100% Eraser process-frame interval p95 | 39.7→43.4ms | 32.3→34.7ms |

At least one ≥83.33ms frame interval still occurs in each full-workspace
process. Held-input, overlap and Eraser frame/release tails are not uniformly
better; in particular Eraser frame-tail p95 worsened in both 100% comparisons.
Full-workspace peak RSS is **322,220–325,120 KiB** over the four processes,
without a proven memory gain. These are virtual X11/llvmpipe callback periods,
not a user's physical FPS, OS pointer receipt, compositor scanout, or photons.

## Final checks and remaining gates

- `make check TOOLCHAIN=bundle` **confirmed exit 0** in `raw/make-check.{log,exit}`:
  Python toolchain/profiler checks, Ruff and ty, **34 Rust** native tests,
  **312 native tile**, native Brush, **42 standalone**, **16 preset** and
  **43 Atlas history** checks, including fail-fast native extension registration.
- `make test-graphical TOOLCHAIN=bundle` **confirmed exit 0** in
  `raw/make-graphical.{log,exit}`: **11 suites**, T-181 (19), T-186 (14),
  T-187 (99), T-188 (63), T-189 (77), T-190 (77), T-191 (77),
  T-192 (81), T-193 (83), T-194 (79), and T-195 (**85**).
- The raw archive retains candidate logs even when they rejected the change;
  earlier test-control failures with the wrong diagnostic variable are not
  counted as implementation failures or successful test runs. The genuine
  catch-up fail-first regression is retained separately. `raw/SHA256SUMS`
  covers every raw file other than the manifest itself.

**T-195 is Done** for one bounded, reversible, pixel-faithful release scheduling
improvement, the complete evidence and the test coverage. The **200ms stretch**,
consistent frame tails and hardware mouse-to-photon acceptance remain **open**
under T-196 and T-095. Post-consolidation T-151/T-152, native-transition
T-148/T-149 and Windows/export T-105 remain open and unapproved. No owner or
independent-review decision was inferred from the software tests.
