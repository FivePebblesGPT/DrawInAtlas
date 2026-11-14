# T-095 — Bounded Legacy duplicate-target drain (2026-11-11)

**Ticket:** [T-095](../Tickets/T-095.md) · **Branch:** `sprint/2026-11-11` · **State:** `In Progress` / `manual_review: true` (no approval).

## Bottleneck and change

`DrawingCanvas._drain_segments()` sets an atomic batch limit based on swept
candidate cost. At 60px the usual limit is **one** source-space segment per
`paint_path()` call. A backlog containing identical mouse positions thus makes
many separate GDScript calls even though the existing once-only Legacy
Brush/Eraser path ignores consecutive duplicate waypoints. The previous
cross-*call* stationary-dab optimization avoided rerasterization, but still
paid the dispatch, transaction and profiling overhead for each input.

In **Legacy only**, allow an atomic batch to grow past its swept-candidate
limit to at most `MAX_SEGMENTS_PER_BATCH` (**16**) **only if every extra
candidate is exactly equal to the preceding source point**. As soon as the
next candidate moves, stop before staging it; retain its already-dequeued
source target and timestamp for the next bounded batch. The regular CPU
soft deadline remains checked between atomic calls. All source samples,
`segments_staged`, `samples_received`, per-sample latency records and
released-stroke completion remain accounted for. A new bounded metric,
`duplicate_drain_batched`, counts only the extra duplicate segments.
Hokusai's accumulating pigment and NativeHard's native batch behavior are
unchanged. No input is dropped, resampled or removed from its chronological
source path.

## Independently failing regression and controls

Pinned local **Godot 4.8.beta3.official.c51ff06e8**, Linux software tests.
Staging: `python3 tools/build_drawing_app.py --in-place`.
`drawing/tests/t095_duplicate_drain_batch_smoke.gd` creates a Canvas
60px Legacy input backlog of 162 individually received source points (80
duplicates, a moving endpoint, 80 more duplicates). An independent
`DrawingEditSession` deliberately disables the prior stationary-dab witness
before **each** `paint_path()` call and rerasterizes the same chronological
source coordinates. The oracle compares exact detached RGBA8 bytes and
committed source, one-step Undo/Redo, input timestamps, segment counters,
source revision and completion after released mouse input.

- **Previous canonical Canvas negative control:** exit **1**, **3 of 195**
  assertions fail (no coalescing; 162 raster dispatches, 0 grouped extras).
  Source/preview/history parity otherwise stays correct.
- **Updated source:** **195/195**, exit **0**, strict
  `T095_DUPLICATE_DRAIN_PASSED` marker accepted by
  `tools/check_godot_model_log.py`. All 162 source segments and latency
  observations retained; **150** duplicate positions grouped; **12** atomic
  batches (versus 162 previously).
- **Paired A/B/A stage CPU witness, not a hardware result:** optimized first
  **18,076 µs**, previous control **20,742 µs**, optimized repeat
  **16,341 µs**. The initial 60px dab dominates this small test; the
  performance numbers vary by run order and do not prove whole-gesture speedup.
  Both optimized runs passed 195/195; old-source run failed its exact three
  newly added grouping assertions, not the pixel/history checks.

## Neighboring regressions

All listed headless scripts exited 0 and passed the exact fail-closed success
marker (logs stored in the local test session):

| Script | Checks |
| --- | ---: |
| `t095_cross_batch_dab_smoke.gd` | 663/663 |
| `t095_duplicate_waypoints_smoke.gd` | 276/276 |
| `t095_input_queue_compaction_smoke.gd` | 31/31 |
| `t095_latency_window_smoke.gd` | 22/22 |
| `t095_stage_batch_window_smoke.gd` | 29/29 |
| `brush_coverage_smoke.gd` | 32/32 |
| `t095_brush_deferred_staging_smoke.gd` | 492/492 |
| `t095_mixed_edit_rollback_smoke.gd` | 504/504 |
| `t095_brush_tile_reference_cache_smoke.gd` | 626/626 |
| `t095_noop_redraw_smoke.gd` | 24/24 |
| `t095_preview_index_reuse_smoke.gd` | 529/529 |
| `t095_native_hard_source_atomic.gd` | 113/113 |
| `t095_native_pigment_atomic.gd` | 57/57 |

Real Xvfb/Mesa llvmpipe 25.0.7, 1280×900×24, Godot beta 3:
`stroke_navigation_native.gd` **48/48**, exit 0; five held-button
60px/786% real mouse-event strokes (`brush_latency_native.gd`) exit 0,
`T095_NATIVE_PASSED`, staging CPU p95 **189.549 ms**, release-to-commit
p95 **78.705 ms**. This is **not** a paired before/after whole-gesture speedup
or physical input-to-photon measurement. Fresh standalone output **without**
the optional native `.gdextension` or `.so`: editor import exit 0,
new oracle **195/195**, fallback **7/7**, both exit 0.

## CI, gates and delivery

The **on-demand** `godot-native-t095-brush.yml` runs the new exact-marker
oracle and retains its raw log `if: always()`. No required fast-CI check
IDs change and T-094's fail-closed crash/log contract remains enforced.
Owner-device original 60px Brush responsiveness, hosted GitHub Actions and
physical Windows/Linux behavior are **unverified**. T-095 is **not Done**;
its manual owner acceptance gate remains open. T-096 remains independently
in **Manual Review**. The owner-verified PR #14 seam fix is untouched.
