# T-300 — exact bounded selection-overlap preflight (2026-11-24)

**Checkout:** PR #23 `sprint/2026-11-23-godot-beta4` based on remote `main`
`bbae76c33a6066582b2cd89e07cc3246fef942ce`. Godot `4.8.beta4` with
compiled Rust `DrawingNativeTiles` loaded for every native witness.

## Reproduced defect and failing control

- [Untouched edit-session/selection source](T-300-2026-11-24-masked-overlap/fail-first.txt):
  **13 failures / 59 checks**, including 12 failed deferred-Brush preservation
  checks in three overlapping sparse/boolean masks × four bulk APIs, and the
  missing bounded overlap method.
- [Negative control](T-300-2026-11-24-masked-overlap/negative-control.txt):
  with the guard deliberately modified to treat all masked intersections as
  eligible, **13 failures / 62 checks**. This mutation was restored before
  the final passing run and is **not** committed.

## Corrected behavior

[Final native witness](T-300-2026-11-24-masked-overlap/passing-final.txt):
**T300_MASK_OVERLAP_PASSED checks=62 failures=0**.

- Sparse pixel mask, Subtract and chained Subtract/Intersect leave no eligible
  pixels inside a 2×2 bulk area **despite its overlapping conservative bounds**.
  All four operations preserve an accepted deferred Brush, epoch, revision and
  lazy-source count across the twelve no-ops.
- The accepted Brush publishes exact RGBA8 after the no-ops. Undo/Redo leave
  the original transparent hidden RGB byte sequence unchanged.
- A truly allowed sparse-mask pixel still triggers an unavailable lazy
  provider, can retry after restoration, and roundtrips exact bytes and
  native history. Additive and inverted selections remain eligible.
- Complex candidate regions exceeding the **4,096-pixel** probe budget are
  deliberately treated as uncertain, not silently skipped; plain rectangle
  overlap remains constant-time.

## Neighboring Godot beta4 native/Atlas checks

| Witness | Result |
| --- | ---: |
| [T-299 masked bulk](T-300-2026-11-24-masked-overlap/t299_masked_bulk_noop.txt) | 40/40 |
| [T-290 bulk preflight](T-300-2026-11-24-masked-overlap/t290_bulk_edit_preflight.txt) | 28/28 |
| [T-291 masked fill](T-300-2026-11-24-masked-overlap/t291_masked_fill_seed_preflight.txt) | 33/33 |
| [T-293 native fill projection](T-300-2026-11-24-masked-overlap/t293_fill_native_projection.txt) | 41/41 |
| [T-294 bulk projection](T-300-2026-11-24-masked-overlap/t294_bulk_native_projection.txt) | 71/71 |
| [T-295 Brush projection](T-300-2026-11-24-masked-overlap/t295_brush_native_projection.txt) | 50/50 |
| [T-296 Delete projection](T-300-2026-11-24-masked-overlap/t296_clear_native_projection.txt) | 50/50 |
| [T-297 huge Brush candidate](T-300-2026-11-24-masked-overlap/t297_brush_candidate_bounds.txt) | 113/113 |
| [Atlas selection](T-300-2026-11-24-masked-overlap/selection_smoke.txt) | 226/226 |
| **Total** | **652/652** |

A Python CI contract checks the existing **46-step** required workflow, the
exact native marker, the bounded pre-materialization guard and positive/
negative witness coverage. This is **not** a fresh hosted CI pass, owner UX
approval, or full native-authority/performance acceptance.
