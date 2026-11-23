# T-301 — bounded true polygon/selection overlap (2026-11-24)

**Checkout:** PR #23 `sprint/2026-11-23-godot-beta4`, remote main
`bbae76c33a6066582b2cd89e07cc3246fef942ce`. Native Godot
`4.8.beta4.official.b070e63b1`, with the Rust Drawing extension loaded.

## Reproduction and correction

- [Negative control](T-301-2026-11-24-polygon-selection/fail-first.txt):
  removed the geometry-specific guard while retaining the T-300 mask-bounds
  guard; **3 failures / 39 checks**. At least one allowed bounding-box pixel
  was outside the polygon, so Brush preview materialized and the next
  masked/boolean case reached unavailable lazy source data. The negative
  control was fully reverted before the committed passing test.
- [Final native witness](T-301-2026-11-24-polygon-selection/passing-final.txt):
  `T301_POLYGON_SELECTION_PASSED checks=39 failures=0`.
  A triangle in a 2×2 candidate rectangle leaves only cells outside the
  polygon eligible under three different selection expressions. All three
  operations return successful no-ops without flattening the pending native
  Brush, touching its preview epoch, or invoking the lazy provider. Commit,
  Undo and Redo restore the Brush and original alpha-zero hidden RGB exactly.
  The positive control selects a real triangle pixel, rejects an unavailable
  provider, retries successfully and verifies committed RGBA8/Undo/Redo.
  The direct guard checks confirm large uncertain, inverted, unrestricted and
  high-vertex cases cannot be skipped by an incomplete or costly proof.

## Neighboring Godot beta4 / native checks

| Witness | Result |
| --- | ---: |
| [T-300 bounded mask overlap](T-301-2026-11-24-polygon-selection/t300_masked_overlap_noop.txt) | 62/62 |
| [T-299 disjoint mask](T-301-2026-11-24-polygon-selection/t299_masked_bulk_noop.txt) | 40/40 |
| [T-290 bulk preflight](T-301-2026-11-24-polygon-selection/t290_bulk_edit_preflight.txt) | 28/28 |
| [T-294 native projection](T-301-2026-11-24-polygon-selection/t294_bulk_native_projection.txt) | 71/71 |
| [T-291 masked fill](T-301-2026-11-24-polygon-selection/t291_masked_fill_seed_preflight.txt) | 33/33 |
| [Atlas polygon](T-301-2026-11-24-polygon-selection/polygon_smoke.txt) | 70/70 |
| [Registered Atlas polygon](T-301-2026-11-24-polygon-selection/t114_polygon_registered_target_smoke.txt) | 43/43 |
| [Atlas selection](T-301-2026-11-24-polygon-selection/selection_smoke.txt) | 226/226 |
| **Total** | **573/573** |

Required CI step `ci_t068_stationary_dab_parity` now executes the native
witness, checks its exact **38-check** marker and uses the strict log checker,
without changing the 46-step required inventory. These local results are not
hosted CI, physical-hardware performance, or owner's acceptance.
