# T-095 — Cross-batch stationary Legacy dab reuse (2026-11-11)

**Ticket:** [T-095](../Tickets/T-095.md) · **Branch:** `sprint/2026-11-11` · **Status:** In Progress · **Manual review:** required, not approved.

## Problem, change and scope

The previous fast path removed consecutive duplicate waypoints *within* a
`paint_path()` batch. Mouse-event draining commonly calls `paint_path()` with
one point per batch, so a held stationary 60px Brush/Eraser still traversed the
same 60px candidate window repeatedly, even though its once-only coverage
set rejected every previously painted pixel. This checkpoint adds a
transaction-local last-successful-stationary-dab witness. The first dab
still rasterizes; a subsequent same-position first waypoint may be skipped
only when its width, RGBA8, erase mode, null selection, clip, candidate budget,
view transform, signed anchor, source revision and preview epoch are identical.
A failed batch, mixed edit, cancellation, commit, native preset call or
NativeHard call invalidates the witness. Any real pointer motion rasterizes
normally; source-read or candidate-limit failures remain observable.
No Rust code, Hokusai pigment accumulation or other ticket state changed.

## Independent tests and negative controls

Local offline Godot `4.8.beta3.official.c51ff06e8` on Linux x86-64; no physical
display acceptance. `python3 tools/build_drawing_app.py --in-place` staged
canonical source. Each nonzero child exit or missing/incorrect pass marker is
a failure; tests use `tools/check_godot_model_log.py` and actual exit codes.

- `t095_cross_batch_dab_smoke.gd`: **663/663, exit 0**. Every one of 121
  one-point batches for Brush and Eraser is compared with an independent
  version forced to full rasterization, including signed >32-bit origins,
  irregular 30/64 storage strides, premultiplied-looking but straight RGBA8
  source bytes, clipping, selection islands/holes, color/width/eraser changes,
  candidate-limit rejection, changed world anchor/view mapping, direct mixed
  editing, moved endpoints, late injected source-tile rejection and retry,
  detached preview, before/after history, Undo and Redo.
- Negative control: in the **staged standalone copy only**, force
  `reusable_stationary_dab` false. **4/663 failures, exit 1**, all expected
  reuse-counter expectations; byte/history parity remains preserved. Restore
  the staged source, rerun: **663/663, exit 0**, strict marker accepted.
- `t095_cross_batch_dab_bench.gd`: **6 alternating-order trials, exit 0**,
  each 120 separately delivered identical 60px dab calls in a new document.
  Full-raster control median **47,487 microseconds** vs optimization median
  **11,910 microseconds**; all trials had nonzero changed-pixel counts and
  exact expected skip counters. Raw sorted controls
  `[46910, 47041, 47183, 47791, 48303, 57596]` microseconds; optimized
  `[11170, 11401, 11815, 12006, 15446, 33197]` microseconds.
  This ~75% gain is strictly a deliberately duplicate-heavy *CPU* benchmark,
  **not** a measured real-pointer/GPU/owner benefit. No timing gate added.

## Adjacent regression and compatibility matrix

These local scripts each exited 0 and passed the exact fail-closed marker:

| Script | Checked |
| --- | ---: |
| `brush_coverage_smoke.gd` | 32/32 |
| `t095_duplicate_waypoints_smoke.gd` | 276/276 |
| `t095_brush_deferred_staging_smoke.gd` | 492/492 |
| `t095_mixed_edit_rollback_smoke.gd` | 504/504 |
| `t095_brush_tile_reference_cache_smoke.gd` | 626/626 |
| `t095_noop_redraw_smoke.gd` | 24/24 |
| `t095_preview_index_reuse_smoke.gd` | 529/529 |
| `t095_native_hard_source_atomic.gd` | 113/113 |
| `t095_native_pigment_atomic.gd` | 57/57 |
| `t095_native_export_cache.gd` | 81/81 |
| `t095_native_preset_packed_output.gd` | 69/69 |
| `t095_native_hard_packed_output.gd` | 20/20 |

Xvfb/Mesa llvmpipe 25.0.7, 1280x900x24: native integration **30/30**,
native fallback **7/7 (native present)**, navigation-after-release **48/48**,
actual held-button five-stroke `brush_latency_native.gd` **exit 0**. That
pointer witness recorded stage p50/p95 **167.797/186.311 ms**, release-to-
commit p50/p95 **60.452/62.697 ms**, peak queue **19**. It is a *separate*
software-renderer correctness witness; it is not a before/after physical
latency comparison for repeated stationary dabs.

Clean `tools/build_drawing_app.py --output` standalone copy with both native
manifest and binary removed: editor import **exit 0**, new 663/663 oracle
**exit 0**, `native_brush_fallback.gd` **7/7, exit 0**, `native=false`.

## Gates, CI and delivery

The on-demand workflow runs the new correctness oracle with its exact pass
marker and retains the raw log even when later jobs fail. The optional CPU
benchmark is **not** part of required fast CI. Preserve T-094's fail-closed
logs, PR #14 signed-tile seam behavior and T-096's independent Manual Review.

**Unverified:** hosted GitHub Actions, Windows/Linux owner GPU/input-to-photon
measurements, and owner acceptance of the original approximately one-minute
60px Brush lag. Do **not** mark T-095 Done or imply this local CPU improvement
resolves the reported real-device problem.
