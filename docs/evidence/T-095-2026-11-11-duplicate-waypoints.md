# T-095 — elide redundant stationary Legacy Brush waypoints (2026-11-11)

**Branch:** `sprint/2026-11-11`; **ticket:** T-095 remains `In Progress`, `manual_review: true`. Godot `4.8.beta3.official.c51ff06e8`. This is a **batched Legacy hard Brush/Eraser CPU** checkpoint, not owner-device latency acceptance.

## Change and correctness boundary

`DrawingEditSession.paint_path()` used to rerun the entire 60px dab geometry and once-only coverage row probes for each identical consecutive waypoint in a *single call*. When a path contains duplicate source positions, its subsequent zero-length segment cannot add any previously uncovered pixel: the first point in that batch has already rasterized that exact dab with the same width, color, clipping, selection and erase parameters. The session now skips those within-batch duplicate geometry traversals, while still validating each input coordinate. A per-session `_duplicate_waypoints_skipped` diagnostic counts elisions. Nothing changes in the NativeHard or Hokusai GDExtension, and Hokusai pigment dabs **must not** be removed.

**Critical safety limit:** the *first* point in every `paint_path()` call must still rasterize, even when it matches the previous call's endpoint. Public callers can change width, clipping, or selection between calls, exposing previously uncovered pixels. The independent test explicitly exercises that transition, plus a failed first dab followed by a valid retry. This restriction also means the optimization is not asserted to speed up the default 60px Canvas pathway, which may currently use one-segment atomic batches.

## Regression and negative control

`drawing/tests/t095_duplicate_waypoints_smoke.gd`: **276/276** checks, process exit 0, strict `T095_DUPLICATE_WAYPOINT_PASSED` verification. Eight independent paired documents compare repeated waypoints with unique-point reference paths using ordinary and 60px Brush/Eraser, signed >32-bit world anchors, 30/64px storage strides, selection holes, clipping, detached preview RGBA8, exact source pixels, commit deltas and Undo/Redo. Further checks confirm the initial failed oversized dab cannot make the retry disappear, and changing selection, clip and width between calls still paints at the same position.

The on-demand optional benchmark `drawing/tests/t095_duplicate_waypoint_bench.gd` runs seven fresh 360-waypoint 60px stationary **paint_path** batches. The final optimized local median was **11,837 µs**, while a staged-only disabled-elision control was **127,162 µs** median; all seven timings and changed-pixel checks were retained in local logs. This is a narrow Godot GDScript CPU-path comparison, **not** an interactive pointer-gesture, compositor, GPU, or physical input-to-photon benchmark. No CI performance threshold is imposed.

To prove the new check detects a missing fast path, the **staged Drawing copy only** was temporarily modified to make the duplicate branch unreachable while retaining the instrumentation. The oracle exited 1 with **10/276** failures. The canonical optimized source was re-staged and passed **276/276**. That negative control is not part of the commit.

## Local adjacent results and limits

- Exact Brush coverage **32/32**, deferred staging **492/492**, source-reference cache **626/626**, mixed-edit rollback **504/504**, Canvas unchanged redraw **24/24** and preview-index reuse **529/529**, all exit 0 with strict markers.
- A **fresh external standalone** editor import with the native extension removed exited 0; the new oracle passed **276/276** with strict marker and native-absent fallback passed **7/7** (`native=false`).
- Oblique scanline log shows **513/513**, but the *combined test runner was interrupted* while executing that test, so no complete-run pass is claimed from it.
- Real GDExtension NativeHard rollback **113/113** and pigment rollback **57/57** pass with strict log markers. Native integration **30/30**, Xvfb released-stroke navigation **48/48**, and five-stroke 60px Xvfb pointer witness exit 0; the latter's strict `T095_NATIVE_PASSED` marker passes. The integration and navigation scripts expose counts, not the incorrectly assumed markers used in the first checker invocation; their process exits and assertion counts are reported separately.

The on-demand `godot-native-t095-brush.yml` now checks the new deterministic oracle and keeps its raw log; required fast-CI IDs and T-094's fail-closed log policy are untouched. Hosted Actions and owner physical device response are **unverified**. T-096 stays in Manual Review.

## Reproduce

```sh
python3 tools/build_drawing_app.py --in-place
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t095_duplicate_waypoints_smoke.gd \
  > /tmp/t095-duplicate-waypoints.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t095-duplicate-waypoints.log \
  --marker T095_DUPLICATE_WAYPOINT_PASSED
# Optional CPU-only timing, no pass/fail latency budget:
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t095_duplicate_waypoint_bench.gd
```

Owner acceptance still requires actual 786%/60px hardware pointer input, preview and release profiling, a documented responsiveness budget, and an explicit decision. No ticket is marked Done.
