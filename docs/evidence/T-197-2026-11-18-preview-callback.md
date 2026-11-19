# T-197 — First-preview callback attribution and fresh Drawing profile

**Date:** 2026-11-18. **Baseline:** archived PR #21 head `9aa1cbe0`, pinned Godot 4.8.beta3, Rust Hokusai native Brush, virtual X11/Mesa llvmpipe, 1280×900. **Evidence:** [raw logs, independent process-exit/RSS records and machine-readable report](T-197-2026-11-18-preview-callback-raw/). These are virtual Godot callback measurements, not hardware FPS, scanout or pointer-to-photon timings.

## Fail-first diagnostic correction

`Canvas._on_frame_post_draw` used to stamp `first_frame_post_draw_us` on *any* renderer callback after the first Canvas preview submit, even if no frame-phase sample belonged to the current stroke. This can report misleading first-preview timing when a non-preview frame is delivered after submission or when another session has superseded the frame. The correction credits the first eligible renderer callback only through `_finish_pending_frame_post_draw`, with a matched live `DrawingEditSession` and a Canvas sample whose end is no earlier than preview submission. The per-frame callback count and staging/cancellation/commit paths are unchanged.

- **Fail-first:** the graphical fixture initially ran against the pre-fix staged Canvas and returned **3 failures / 6 checks**, confirming unmatched and pre-preview callbacks could be miscredited. The original log is `fail-first-pre-fix.log` (the first attempt before project import could not load global classes and is not claimed as fail-first evidence).
- **After staging fixed canonical addon:** the isolated Godot headless script returned **6/6**; real software-X11 graphical execution returned **9/9**, including an actual native Hokusai preview submission/callback and a stale-session rejection, a cancelled diagnostic stroke with no publication, and one committed native history event. Logs: `post-fix-headless.log`, `post-fix-x11.log`.
- **Other existing graphical regressions:** a broad `make test-graphical` run printed the passing markers of **all 12 preexisting graphical suites (T-181 through T-196)**, with no test failures. Its outer invocation exceeded the orchestration timeout, so **no confirmed aggregate zero exit is claimed**; the full original log is retained at `graphical-suite-incomplete-exit.log`. A focused independent zero-exit T-197 graphical run is recorded above. A new T-197 target is added to `make test-graphical`.

## Fresh real-workspace 96px Hokusai observations

`tools/run_t185_profile.py --trials 2` ran **two independent confirmed zero-exit processes**, with two 54%/100% × four cold/warm/held Brush/Eraser cases (16 scenarios). Each process recorded native transactions, first preview submission, matched postdraw, release→commit, frame phases, real native staging and source SHA, and `/usr/bin/time -v` RSS. Every corresponding scenario has **exactly the same committed RGBA8 SHA across both runs**. Both processes passed the strict full-workspace log validator. Native library SHA-256 `08ed18318d1819f07345c9924539f7578b28c412d8a069e785a55689148d5941`.

| Scenario | First matched preview callback, trials 1 / 2 (ms) | Cumulative Canvas composition CPU, trials 1 / 2 (ms) |
| --- | ---: | ---: |
| 54% cold Brush | 32.2 / 28.1 | 3.3 / 5.3 |
| 54% warm Brush | 23.1 / 23.8 | 3.6 / 3.2 |
| 54% held Brush | 22.8 / 27.2 | 2.6 / 2.7 |
| 54% Eraser | 35.0 / 38.4 | **85.3 / 89.6** |
| 100% cold Brush | 22.2 / 21.7 | 3.1 / 3.4 |
| 100% warm Brush | 28.1 / 24.7 | 4.3 / 3.0 |
| 100% held Brush | 27.8 / 24.9 | 3.2 / 2.7 |
| 100% Eraser | 38.8 / 39.9 | **92.4 / 79.3** |

Across these 16 scenarios, **9 post-draw intervals ≥83.33ms** are still present; multiple cases, including both Eraser zooms, retain a long interval. The two full-process maximum RSS figures are **332,512 and 322,412 KiB**. No released gesture had a pending input sample at mouse-up; the T-196 deferred catch-up path did not participate. Composition is not generally dominant for Brush, but Eraser still spends ~79–92ms compositing because hidden RGB / transparent pixels prevent the T-187 cropped direct preview. The source-preserving potential improvement needs an independently tested compositor/native display conversion, not a speculative reduced batching threshold.

The old and new callback implementations were **not** compared as a performance A/B. This checkpoint fixes metric attribution and isolates a repeatable work hotspot; it does not prove any decrease in frame time, p50/p95, whole-gesture or mouse-to-photon latency. Do not label the two-process p95 a reliable population estimate. T-197 stays **In Progress**. T-095 owner hardware, T-105 Windows, and T-148/T-149/T-151/T-152 native-transition/consolidation gates all remain open.

## Independently confirmed checks

After the broad graphical run, independent one-process software-X11 invocations returned **exit 0** for: T-197 first-preview regression (**9/9**), T-187 direct-preview parity (**99/99**) and T-196 release-deferred parity (**99/99**); the original logs are retained above. The pinned Rust `build_native_brush.sh --test` returned **exit 0, 34 tests**. Python unittest modules returned **exit 0, 5 profiler tests and 19 toolchain tests**; bundled pinned Ruff/ty lint and ticket-store validator likewise returned **exit 0**, with `git diff --check` clean. These targeted, independently verified exits must not be conflated with the interrupted aggregate `make test-graphical` runner.
