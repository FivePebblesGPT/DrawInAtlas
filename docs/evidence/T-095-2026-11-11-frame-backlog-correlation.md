# T-095 — Per-frame pending input age correlated with draw CPU (2026-11-11)

**Ticket:** [T-095](../Tickets/T-095.md) · **Branch:** `sprint/2026-11-11` · **State:** `In Progress`, `manual_review: true` (owner did not approve).

## Scope and reason

The previously retained 1,024 actual Canvas render-frame CPU samples had no
matching input-backlog timestamp or depth. An owner-device draw spike could not
be related to an aged, unprocessed pointer waypoint. On each active-stroke
draw, the Canvas now records `frame_end_us` (monotonic engine clock),
`pending_input_count` and `oldest_pending_age_us` in that same bounded
`frame_phases_us` record. The age includes an already-dequeued interpolation
target and otherwise uses the oldest unconsumed timestamp. A consumed prefix,
including a compacted one, does not inflate pending counts. No pending sample
means age and count both zero; negative ages are clamped. All-time maxima
`max_frame_pending_input_count` and `max_frame_oldest_pending_age_us` survive
retention-window eviction. Existing five render CPU fields and their maxima
are unchanged.

The pointer-event `brush_latency_native.gd` witness prints the aggregate
`T095_NATIVE_FRAME_BACKLOG_SUMMARY` with frame draw p50/p95, pending-input
age p50/p95/max, pending-depth p95/max and exact total vs retained frame
counts. The detailed frame records remain in `last_gesture_metrics` for owner
review. The aggregate is over the bounded retained latest-frame windows per
stroke; it is **not** necessarily an all-time percentile for extremely long
strokes. Godot receipt/Canvas callbacks are **not physical input-to-photon
measurements** or OS input hardware timestamps.

## Red/green and checks

Pinned local Godot: `4.8.beta3.official.c51ff06e8`, Linux/Mesa. With the
previous canonical Canvas staged only into the local Drawing test copy,
`drawing/tests/t095_frame_input_backlog_smoke.gd` exited **1** and failed
**4/5** checks: missing sampler, missing lifetime backlog maxima, absent
aligned frame fields, and no live sampler. Restaging current canonical code
passed **24/24**, exit **0**, with one exact `T095_FRAME_BACKLOG_PASSED` marker
accepted by `tools/check_godot_model_log.py`. The test checks:

- Empty backlog, consumed prefix, oldest pending queued sample, in-flight
  interpolated target, target-only queue, future timestamps and zero-after-drain.
- A real `DrawingCanvas._compact_sample_queue()` preserving pending count and
  oldest age across prefix removal.
- More than two full retention-window rotations, aligned render clock/queue
  age/depth/CPU fields, all-time maxima from evicted old frames.
- Actual active-stroke Canvas redraw samples, one 60px detached Brush commit,
  RGBA8 byte identity against an independent `DrawingEditSession.paint_path`
  control, and one-step Undo/Redo.

Strict-marker neighboring **headless** checks all exited zero: render-frame
phase history **19/19**, bounded input-age history **22/22**, stage-batch
history **29/29**, sustained queue compaction **31/31**, duplicate-target
drain **195/195**, no-op redraw **24/24**, preview-index reuse **529/529**,
deferred Brush staging **492/492**, original 60px Brush pixel coverage
**32/32**, NativeHard source rollback **113/113**, Hokusai rollback
**57/57**. All eleven were verified individually with the fail-closed
model-log checker.

Graphical Linux Xvfb/Mesa (1280×900×24) checks exited **0**: native Brush
integration **30/30**, released-stroke navigation **48/48**, native fallback
**7/7**, and the real mouse-event five-stroke `brush_latency_native.gd`
witness. That run reported staging p95 **184.423 ms** and release-to-commit
p95 **65.956 ms**; the *new* frame-aligned diagnostic reported **274**
retained of **274** total frames, full-draw CPU p95 **20.098 ms**, pending
receipt-to-draw age p95 **113.596 ms**, maximum pending age **151.176 ms**,
and pending count p95 **14** (maximum **17**). These are environment-specific
software-rendered observations, not baseline-vs-change speedups.

A fresh standalone editor import **without the native extension** exited 0;
the new **24/24** oracle and native-absent fallback **7/7** both exited 0.
The on-demand `godot-native-t095-brush.yml` workflow uses the exact
`T095_FRAME_BACKLOG_PASSED` marker and retains the raw test log. The required
fast-CI check IDs and T-094 strict logging policy are unchanged.

## Open acceptance

**No 60px responsiveness speedup or owner acceptance is claimed.** The
original ~one-minute lag remains unverified on the owner's GPU/driver. A
reference-device check must distinguish UI draw CPU, queued sample age,
actual OS pointer delivery, GPU submission/display and observed
input-to-photon. Hosted CI was not run here. T-095 stays **In Progress**,
`manual_review: true`; T-096 stays independently in **Manual Review**.
