# T-095 — 2026-11-11 stationary/axis Brush scanline pruning

**Scope:** T-095 only; status **In Progress**, `manual_review: true`. This is a targeted software CPU optimization/checkpoint, **not** a physical-GPU UX acceptance. T-096 remains independently in Manual Review.

## Reproducer and implementation

A 60px hard Brush candidate loop covered the entire padded bounding rectangle even for a stationary dab or exactly horizontal/vertical sweep. The code checked once-only coverage or pixel geometry for coordinates outside the brush's circular footprint. This is wasted CPU work during repeated overlapping dabs, straight strokes and segments, particularly for the original Legacy path.

`addons/drawing/edit_session.gd` now narrows each stationary/axis-aligned row to a **conservative** intersection span derived from the circular radius. Every surviving pixel is still accepted or rejected by its original squared-distance predicate (`Vector2.distance_squared_to` for stationary, clamped axis projection for horizontal/vertical); the bounds use an extra two-pixel margin to absorb float rounding. Huge view-relative coordinates (absolute start/finish component ≥1,000,000) use the original **Geometry2D/Vector2** full-row reference path rather than rely on that margin or on the pre-existing axis arithmetic, which can diverge from float32 Geometry2D at high magnitude. The existing max-candidate limit, clipping/splitting, oblique Geometry2D path, signed world anchors, selection masking, RGBA8 blend/erase, tile-local publication, cancellation and batch source-read rollback are unchanged.

## Independent differential and adversarial control

New `drawing/tests/t095_axis_scanline_bounds_smoke.gd` passes **278/278** checks, process exit 0, on pinned `Godot 4.8.beta3.official.c51ff06e8`. Its independent reference always enumerates the full original bounding rectangle and uses `Geometry2D.get_closest_point_to_segment` (or `Vector2.distance_squared_to` for dabs), with **no** scanline pruning. Twelve source/preview/history cases cover fractional and half-pixel stationary, forward/reverse horizontal and vertical 60px strokes, 1/2/7/31.3/61px edges, two signed world anchors outside 32-bit, irregular 30px and power-of-two 64px storage tiles, selected islands with subtract holes, partial-alpha and hidden-RGB source, 5,000-candidate recursion, clipping, exact detached preview, canonical before/after delta and Undo/Redo. Three additional large view-relative coordinate cases (~10 million) verify the Geometry2D fallback and exact source/preview/history bytes at signed world anchors. These three **fail four checks** against the original pre-change session due to an existing high-coordinate axis-shortcut mismatch; the corrected implementation passes all checks. The test runs with native extension present but does not depend on native brushes.

A temporary, **uncommitted staging-only** negative control changed the horizontal scanline's left bound from `min_x - reach` to `min_x + reach + 10`. The independent oracle returned exit 1 with **22 failed checks**, including preview, pixel count, history and Redo. The correct implementation was restored byte-for-byte; the source checkout was never modified by that negative control.

After canonical restaging, these strict-marker model checks passed with exit 0: `t095_axis_scanline_bounds_smoke` **278/278**, `t095_oblique_geometry_smoke` **86/86**, `brush_coverage_smoke` **32/32**, `brush_blend_math_smoke`, `t095_stage_tile_lookup_smoke` **4193/4193**, `t095_brush_tile_key_cache_smoke` **33037/33037**, `t095_brush_deferred_staging_smoke` **492/492**, `t095_mixed_edit_rollback_smoke` **504/504**, `t095_tile_commit_smoke` **56/56**, `t095_legacy_tile_commit_smoke` **519/519**, `hokusai_bulk_delta_smoke`, `t095_native_hard_atomic`, `t095_native_hard_source_atomic`, `t095_native_pigment_atomic`, and `t095_native_export_cache`. A fresh standalone `--output` package with
its optional native extension deleted imported cleanly (exit 0), then passed
the same **278/278** scanline oracle and the native-absent fallback **7/7**,
both with exit 0. The first combined headless shell sweep reached its outer execution timeout after recording its initial checks; the remaining native/model checks were executed **separately** and passed, rather than treating the timed-out sweep as a successful CI job. Real Xvfb `stroke_navigation_native` **48/48** and `native_brush_integration` **30/30** passed. On-demand T-095 CI now runs the new strict-marker oracle and uploads its log; hosted CI is **unverified**, and no required fast-CI check ID changed.

## Isolated software cost comparison

A temporary, non-committed Godot `SceneTree` microbenchmark timed `DrawingEditSession.paint_path` with 61 repeated 60px positions/segments and four new-document trials per kind. It used identical source/engine across **optimized → original → optimized** staging swaps, with medians from the two middle values. The original source is the exact pre-change session file, swapped **only** into the generated Drawing addon and restored after measuring. Headless CPU timings do not include a real compositor, display, physical pointer delivery or photon latency.

| Repeated gesture shape | Optimized first (median ms) | Original control (median ms) | Optimized second (median ms) |
| --- | ---: | ---: | ---: |
| Stationary dab | 31.282 | 36.892 | 32.657 |
| Horizontal | 66.471 | 68.358 | 62.729 |
| Vertical | 67.398 | 67.100 | 66.226 |

Dab and horizontal isolated timings improved in both runs; vertical readings are overlapping/noisy. This is **not** evidence that every Brush gesture accelerates.

## Real pointer simulation and open gate

The existing Xvfb/Mesa Linux `brush_latency_native.gd` test used five complete 60px, 786% zoom strokes × 120 real `InputEventMouseMotion`s with button events and held preview assertions. The three-run **optimized → original → optimized** staging swap kept native binary, display/engine and mouse harness the same. Every run exited 0 with `T095_NATIVE_PASSED`, but Legacy stage CPU p95 values were **171.916 / 170.275 / 175.490ms**, respectively: **no credible total-gesture speedup**. Release-to-commit p95 values were **57.628 / 60.633 / 59.427ms**, also not owner-hardware performance data. Do not infer release responsiveness or input-to-photon acceptance from these Xvfb measurements.

Owner's originally rejected ~3-second/one-minute stroke must still be repeated on the actual GPU/OS/driver with real 60px mouse input, live preview and p50/p95/worst-stage/queue/compose/upload/release backlog, followed by explicit hands-on approval. Hosted Actions and actual Windows/Linux native export behavior remain unverified. **T-095 must stay In Progress**, and T-096 retains its separate manual gate.
