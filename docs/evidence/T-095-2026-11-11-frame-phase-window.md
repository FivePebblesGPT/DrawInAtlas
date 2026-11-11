# T-095 — Bounded Canvas render-frame phase history (2026-11-11)

**Ticket:** [T-095](../Tickets/T-095.md) · **Branch:** `sprint/2026-11-11` · **State:** `In Progress`, `manual_review: true` (owner acceptance not recorded).

## Motivation and behavior

Existing gesture telemetry retained chronological stage-batch and sample-age
windows, but render-side telemetry exposed mostly **cumulative** compositor,
preview-index and texture-upload CPU sums. Consequently a long 60px stroke
could hide a single late frame stall in the total, and an owner-device run
could not calculate render-phase p50/p95 or correlate the latest frame spikes
with the retained input backlog.

`DrawingCanvas._draw()` now records a per-preview-frame, time-aligned dictionary
of **full draw CPU** (including overlays), **tile-compositor CPU**, **texture
creation/update CPU**, **preview-index CPU** and **selection-outline CPU**.
The current frame is captured after its overlays are issued. Each phase is
nonnegative and expressed in microseconds. The last **1,024** frames are
retained in a chronological ring; `frame_phase_total` and five
`max_frame_*_cpu_us` fields retain all-time count and maxima even after the
ring overwrites old samples. The completed gesture stores an independent deep
copy in `last_gesture_metrics` alongside existing sums. `preview_frames`,
`draw_cpu_us` (legacy pre-overlay timing), `bytes_uploaded`, input receipt,
queue and stage metrics retain their previous semantics.

The record is created **only while a detached stroke session is active**.
Idle/post-commit draws do not change its completed history. Rendering,
source-pixel blending, commit, rollback and transaction gates are untouched.
The per-frame fields can be summarized into p50/p95 distributions on a real
display, but **Godot callback/CPU timestamps are not physical input-to-photon
measurements**; there is no GPU fence or external high-speed camera signal.

## Red/green test and independent pixel oracle

Test: `drawing/tests/t095_frame_phase_window_smoke.gd`, pinned local Godot
`4.8.beta3.official.c51ff06e8`, Linux headless/Mesa.

- Current canonical code: **19/19** checks, exit **0**, exact
  `T095_FRAME_PHASE_PASSED` accepted by the fail-closed log checker.
- Staged-only negative control suppressing **actual Canvas** phase recording
  without changing rendering: exit **1**, **2/19 failures** (no live-frame
  samples and incomplete real-frame phase reporting). Canonical source was
  restaged and the oracle rerun with a clean exit.
- Deterministic synthetic frames cover negative-value clamping, short-frame
  retention, 3 complete ring wraps plus 71 late samples, exact five-phase
  chronological pairing, lifetime count and an early 990,000 µs compositor
  outlier surviving eviction, and exact full ring rotation.
- The real Canvas portion records two active-preview draw callbacks in a
  representative run, with full-draw maximum **5,398 µs**, compositor maximum
  **5,277 µs**, and texture-upload maximum **16 µs**. These values are
  environment-specific samples, not performance targets. It checks frame
  cardinality, nonnegative fields, committed RGBA8 pixels against an
  independent `DrawingEditSession.paint_path()` control, and Undo/Redo.

## Neighbor checks and reproducibility

Local stage command: `python3 tools/build_drawing_app.py --in-place`.
Run the oracle with the pinned Godot 4.8 beta 3 binary:

```sh
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t095_frame_phase_window_smoke.gd \
  > /tmp/t095-frame-phase.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t095-frame-phase.log \
  --marker T095_FRAME_PHASE_PASSED
```

All these neighboring **headless** scripts exited 0 with their expected
markers: no-op redraw 24/24, preview index reuse 529/529, stage-batch window
29/29, deferred Brush staging 492/492, duplicate-target drain 195/195,
Brush coverage 32/32. The strict log checker also accepted the new oracle.

Xvfb/Mesa llvmpipe (1280×900×24) runs: native Brush integration **30/30**;
native fallback **7/7** with a native binary; released-stroke navigation
**48/48**; five-stroke 60px/786% pointer witness passed with stage p95
**174.645 ms**, release-to-commit p95 **63.141 ms**, and compositor p95
**18.357 ms**. The two native result scripts use `*_RESULT checks=N
failures=0` rather than a separate `_PASSED` marker; their processes exited
0. These numbers are **not** controlled before/after latency comparisons.

A **fresh standalone editor import with the native extension removed** exited
0; the 19-check oracle and native-absent fallback 7/7 both passed on that
project. The on-demand `godot-native-t095-brush.yml` workflow now requires
`T095_FRAME_PHASE_PASSED` via the strict T-094 checker and uploads the raw
log. Workflow YAML and `tools/validate_ticket_store.py` locally validate.
The required fast desktop CI matrix is unchanged.

## Open acceptance

This is instrumentation, **not a 60px Brush speedup**. The owner's reported
roughly one-minute catch-up has not been reproduced or rechecked on their
physical GPU/driver. Real input-to-photon measurements, a documented accepted
budget, owner approval, and hosted GitHub Actions remain unverified. T-095
stays **In Progress** and `manual_review: true`; T-096 remains independently
in **Manual Review**.
