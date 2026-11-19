# T-196 — Deep-backlog idle release drain vs 200 ms stretch (2026-11-17)

**Evidence:** [original raw process logs and SHA-256 manifest](T-196-2026-11-17-deferred-backlog-drain-raw/), with each benchmark's `summary.json`, original `/usr/bin/time -v` output and process exit/checker code, phase counters, rejected variants, fail-first tests and final integration checks. These are software-X11/Godot engine callback measures, **not** physical pointer-to-photon, population p95 or general device FPS acceptance.

## Baseline and wall-clock attribution

The unmodified T-195 branch passed two cold standalone native Hokusai 96px/512²/100-event full-canvas gestures (216.6 and 241.2ms) and one two-gesture warm process (253.3 and 192.5ms), all process and log-checker exits 0. The native stage CPU was about 66–93ms, first post-draw 33–62ms, and queued release→commit 88–142ms. Composition is already small after T-187, making a further tile-compositor rewrite a poor first target. A repeatable frame-wait component remains beyond the actual native raster stage; neither a frame callback nor the `6ms` *soft* between-transaction deadline guarantees physical frame pacing.

## Rejected experiments and regression controls

A **second synchronous `_drain_segments()` inside `finish_gesture()`** passed the initial 85-check pixel/history/Save/Open comparison and sometimes shortened total gesture time, but an independently instrumented 100-event mouse-up duration increased from approximately **6–10ms** (reference) to **19–36ms** (candidate). This can degrade input responsiveness even when a whole-gesture number looks better. It was **rejected**; `ref1/opt1/opt2/ref2`, `refmouse/optmouse`, `fail-first`, `frontend-parity` and related raw attempts are preserved.

The next candidate queued one extra soft-deadline drain via Godot `call_deferred`, checked against the original `DrawingEditSession` identity and document revision. It did not lengthen mouse-up in the independent instrumented run (approximately **7–11ms** vs **6–10ms**) and preserved native source identity. However an **ungated** deferred callback worsened held-input/Eraser frame p95 in some full-workspace scenes; the `refdefwork/optdefwork` and `refdefer/optdefer` A/B logs retain this negative evidence. An initial graphical Save/Open test failed because the test fixture accidentally put spaces into its file path; that fixture bug was corrected. The earlier native-staging test failure resulted from not restaging the canonical addon and is likewise preserved.

## Retained bounded implementation

After the ordinary **20-segment/6ms-soft-deadline mouse-up drain**, count only truly outstanding source input samples (including the current interpolated target). If at least **32 input samples** remain, enqueue **at most one** idle-deferred drain. Never perform it inside the mouse-up callback; ordinary short/held gestures retain T-195's proven per-frame cadence. The queued call verifies `session == expected`, `_finish_requested`, the expected document revision and remaining work before touching native data; stale/cancelled/replaced callbacks are inert. It uses the same `MAX_SEGMENTS_PER_FRAME`, 20-segment atomic staging limit and separately checked `6ms` soft deadline. `DRAWING_T196_DEFERRED_CATCHUP_COUNTERFACTUAL=1` disables only this drain in the **same release binary**.

A strict **100-event** fill had **86 pending samples** after mouse-up. Conversely all eight measured full-workspace gestures (cold/warm/held Brush and Eraser at 54%/100% zoom) had zero pending samples at release, so none enabled the new callback. This threshold is grounded in actual queue depth rather than assuming native FFI count or user device FPS is the cause. Source/transaction outcomes are unchanged.

## Final same-binary reverse-order strict 100-event A/B

Two matched rounds in `ref-final1/opt-final1/opt-final2/ref-final2`, each with two fresh cold processes and a valid two-stroke warm process per mode: **4 cold and 4 warm gestures per mode**, 0 process exits, 0 checker exits and all strict source/preview/coverage/history checks passed. The release binary is SHA-256 `f6472af4aa6150db710d72da0091e5a134ccaa1d95c84ef2dc0617d54fcdf2b0` in *every* run. Every native source digest is `6df89cc963368830befd8dbf061db9bb0f40060556a8dfb127cf5e9681f68ec4` with all 262,144 source pixels covered, 100 pointer input events, 50 native stage FFI calls and native history parity.

| Metric | T-195 reference p50 / p95 | T-196 deep-backlog deferred p50 / p95 |
| --- | ---: | ---: |
| Cold whole gesture to settled postdraw | 204.2 / **215.2ms** | **182.8** / 227.4ms |
| Warm whole gesture to settled postdraw | 192.8 / **217.3ms** | 192.3 / **205.4ms** |
| Cold queued release→commit | 96.8 / 113.9ms | **87.9** / 117.7ms |
| Warm queued release→commit | 87.6 / 96.2ms | **80.1** / 93.2ms |
| Cold first-preview postdraw | **41.1** / **43.4ms** | 47.9 / 49.2ms |
| Warm first-preview postdraw | **32.2** / **39.4ms** | 44.3 / 50.7ms |

These p95s are the **maximum of four samples** (nearest rank), not population tails. Warm p95 and cold median improve, but cold p95 **regresses**, and first preview is later in the optimized samples despite the code being release-only. Process variability prevents causal attribution for pre-release first-preview timing. **The 200ms p95 stretch is not achieved or declared.** The previous 250ms milestone from T-194 remains a small-sample software-X11 observation rather than universal acceptance.

## Final full-workspace comparison and integrity

`ref-gated-work1/opt-gated-work1/opt-gated-work2/ref-gated-work2` are **four confirmed zero-exit full Drawing workspace processes**, 8 checked scenarios each, at 54% and 100% zoom. Every corresponding native source RGBA SHA-256 across the four runs matches exactly. Their 32 scenarios had `release_pending_samples=0` and `post_release_deferred_calls=0`; consequently the new path does **not** alter the ordinary/held/Eraser workload and observed frame and release differences are unrelated run variance, not evidence of a causal speedup. All processes retain long (≥83.33ms) intervals on some cases, and p95 and release-to-settled remain mixed. Peak RSS across those four is **324,860–325,708 KiB** (virtual X11/llvmpipe), without evidence of a memory improvement.

The new graphical T-196 regression checks signed coordinates, subtracted selection masks, hidden RGB at alpha zero, Brush/Eraser, Undo/Redo, cancelled edits, exact standalone Save/Open, capture-only/no-extra scheduling, **a short release below the queue threshold**, and cancelling a gesture before its deferred callback. It passes **99/99** against both modes. The T-195 isolated counterfactual test explicitly disables T-196's newer release path so its own 85-check release-frame scheduling comparison remains independent; no painting behavior was weakened to make an old assertion pass. Both are exercised by `make test-graphical`.

## Validation and unchanged gates

- Baseline, candidate and final strict process/checker exit codes, source SHA and native extension identity are recorded per original `summary.json`; all reported successful benchmark processes have confirmed exits 0. Earlier failed/incomplete attempts are not silently promoted.
- The final [graphical target log](T-196-2026-11-17-deferred-backlog-drain-raw/make-graphical.log) has a confirmed **exit 0**, covering **12 suites**: T-181 (19), T-186 (14), T-187 (99), T-188 (63), T-189 (77), T-190 (77), T-191 (77), T-192 (81), T-193 (83), T-194 (79), T-195 (85), and T-196 (99).
- The first broad `make check` returned no confirmed exit after printing success markers and is retained as **incomplete evidence**. A subsequent complete `make check TOOLCHAIN=bundle` had a confirmed **exit 0** in `make-check-final.{log,exit}`, including Python tests, Ruff/ty lint, **34 Rust**, **312 native-tile**, **32 native-Brush**, **42 standalone**, **16 preset**, and **43 Atlas-history** checks.
- `python3 tools/validate_ticket_store.py` validates **197** tickets and dependency/manual-review gates. Source and documentation changes respect the canonical `addons/drawing/` path, not generated staging artifacts.

**T-196 Done is the bounded deep-backlog release scheduling change**, not a claim of meeting the 200ms stretch, consistently improving frame pacing, physical mouse-to-photon, or T-095 owner signoff. **T-197 Ready** continues first-preview, 200ms p95 and hardware pacing work. T-151/T-152 consolidation, T-148/T-149 native transition, T-105 Windows/export and all manual gates remain open.
