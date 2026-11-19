# T-199 — Canvas redraw-end cadence despite missing renderer callbacks

**2026-11-19 — Done for diagnostic instrumentation only.** The source
renderer, native compositor, native input/staging, saved pixel bytes and
undo transactions are not changed. This report is not a physical FPS or
mouse-to-photon benchmark.

## Why another signal is necessary

[T-198](T-198-2026-11-19-matched-callbacks.md) established 541 consecutive
matched Canvas renderer-callback pairs across four real native profiles and
251 Canvas adjacencies without both callback timestamps. Matching callbacks
must not be imputed; but their absence does **not** remove an independently
recorded `frame_end_us` when Canvas actually draws. T-199 records adjacent
end-to-end gaps between those Canvas draws, per gesture, and includes an
explicit callback-pair coverage split.

The implementation uses **strictly increasing**, **positive** adjacent
`frame_end_us` values, rejects missing/nonmonotonic pairs, never crosses
case boundaries, reports nearest-rank p50/p95/max and exact counts crossing
33,333µs and 83,333µs. Detailed long events (current and preceding Canvas
CPU draw costs, pending input count/age, matched callback pair) retain only
the last 32; overall counts are not truncated within the existing Canvas
frame-phase window. `matched_canvas_callback_gaps` remains separate and
unchanged. The summary key is `canvas_draw_cadence`.

## Confirmed evidence: unchanged four-process A/B plus one new run

Original four logs and independent `/usr/bin/time -v` **Exit status: 0**
are preserved under [the T-197 native-display archive](T-197-2026-11-18-native-display-raw/).
The **fresh** process uses the same native Brush/Eraser source, Godot
`4.8.beta3.official.c51ff06e8`, `Xvfb` 1280×900×24, Mesa software rendering,
and the full eight-scenario Drawing workspace. Its source log, `time` exit,
runner output and complete profiler summary are retained under
[T-199-fresh-workspace](T-199-2026-11-19-fresh-workspace/); peak reported
RSS is 337,744 KiB. All five sources have eight complete real 96px
native Hokusai Brush/Eraser history transactions and corresponding source
RGBA8 `after_sha256` parity. The original R→O→O→R reference selection
is not a new performance A/B and no painting optimization was performed.

| Process | Source | Valid Canvas draw gaps | Lacking adjacent postdraw pair | ≥83.333ms | Draw-gap p95 | Max draw gap |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 0 | T-197 reference | 198 | 83 | 0 | 26.165ms | 36.092ms |
| 1 | T-197 optimized | 198 | 42 | 0 | 18.415ms | 24.731ms |
| 2 | T-197 optimized | 198 | 62 | 0 | 19.215ms | 30.964ms |
| 3 | T-197 reference | 198 | 64 | 0 | 23.209ms | 30.822ms |
| 4 | **Fresh optimized** | 198 | 92 | 0 | 22.429ms | 33.139ms |
| **Original four** | | **792** | **251** | **0** | — | 36.092ms |

No missing, zero, duplicate or backwards Canvas end stamps were found
in these five real runs. The fresh process reported 106 adjacent matched
renderer-callback pairs and 92 without; do not claim the latter as
physically smooth frames. The retained global callback series contained
19 ≥83.333ms gaps **across the original four processes**. Those remain
unattributed to active drawing by either report. This separate draw-end
witness reduces the uncertainty **only for observed Canvas draws**;
there may be unsampled redraw intervals, whole-app processing stalls or
present/scanout delays beyond this measurement.

See [compact source SHA-256 / timing report](T-199-2026-11-19-canvas-cadence.json)
for exact log/time hashes, recorded callback coverage, output counts and
canonical source RGBA8 digests; hashes are computed from the retained
raw files, not copied from an earlier prose conclusion.

## Regression and gates

- **Fail-first:** six T-199 unit cases errored on the absent diagnostic;
  all now pass. Tests exercise missing callback pairs, case boundaries,
  missing/duplicate/reversed timestamps, no invented empty sample,
  exact long-event counts with 32-detail bounded retention, and
  re-ingestion/exit/source parity across all four old real processes.
- The profiler's existing source, native Hokusai transaction, cache,
  96px, process-exit and phase-integrity checks are retained.
- The 200ms **strict 100-event p95** and 60/96px physical hardware input,
  continuous FPS, OS presentation, Windows/export and native raster
  consolidation are **not** accepted or changed. T-197 remains In Progress;
  owner/manual gates on T-095 and associated feature tickets are unchanged.

## Fresh 2026-11-19 local validation

The fresh benchmark was invoked with
`python tools/run_t185_profile.py --godot /mnt/data/toolchain/bin/godot --output /mnt/data/work/t199-fresh --trials 1 --timeout 120`
using the supplied verified offline native toolchain. The runner returned
0 and the independent `/usr/bin/time -v` witness returned exit 0, with
all eight strict native source transactions validated. The report's
raw paths and source SHA-256 are preserved in the committed evidence
folder rather than relying on the ephemeral output location.

| Check | Outcome |
| --- | --- |
| T-199 fail-first | Six missing-diagnostic errors before implementation, retained |
| `make python-test` | 36 passed: toolchain 19, profiler 5, T-198 6, T-199 6 |
| Offline pinned Ruff 0.17.5 / ty 0.0.104 | Both passed after fixing new test import order |
| Native Rust `cargo test --locked --offline` | 35/35 passed |
| Godot graphical first-preview T-197 | 9/9, exit 0 |
| Godot graphical direct-preview T-187 | 183/183, exit 0 |
| Godot graphical deferred-release T-196 | 99/99, exit 0 |
| Native Drawing headless integration | 32/32, exit 0 |
| Atlas native history | 43/43, exit 0 |
| Ticket index/manual-gate validator | 199 tickets validated |

Two older T-095 root-project smokes were also run, **but failed** with
one `RGBA8` comparison assertion each (`t095_frame_post_draw_pairing_smoke`:
23 checks, 1 failure; `t095_frame_phase_window_smoke`: 19 checks, 1 failure).
Both scripts were last modified at historical commit `40b7eb2d`; this
T-199 diff makes **zero changes** to those scripts, native source or
`addons/drawing/canvas.gd`. The old tests compare the current native
Hokusai brush path to a separately constructed legacy `paint_path`
reference; they are not evidence of T-199 profiler contamination, but
must be fixed or retired through their proper separate scope. Their
actual failing exit codes and full logs are retained; neither is
counted as passed or silently excluded from the report.

The complete validation outputs, including the original six-case
fail-first log, are in [validation](T-199-2026-11-19-validation/).
No hardware/Windows/hosted CI acceptance has been attempted or claimed.
