# T-280 — Axis-sweep native publication/Geometry2D evidence (2026-11-23)

## Baseline and scope

- Working branch: `sprint/2026-11-23-godot-beta4`, starting local SHA
  `ccb7e440`; verified remote `main` SHA: `bbae76c33a6066582b2cd89e07cc3246fef942ce`.
- Godot: `/mnt/data/unpacked/drawing-toolchain-linux-x86_64/bin/godot`,
  `4.8.beta4.official.b070e63b1`, with compiled Rust GDExtension registering
  as `godot-rust (API v4.7.stable.official, runtime v4.8.beta4.official)`.
- Scope is strictly the **T-068 axis-sweep validation fixture**. Neither
  production raster/history code nor source fixture pixel geometry changed.

## Reproduction and comparison

From the repository root, with the compiled extension available:

```bash
GODOT=/mnt/data/unpacked/drawing-toolchain-linux-x86_64/bin/godot
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path . \
  --script res://tests/drawing_axis_sweep_smoke.gd
```

| Stage | Exit | Checks | Observation |
| --- | ---: | --- | --- |
| Original `>2^53` signed anchor | 1 | 137, **34 failed** | All 34 native commits rejected, expected under signed projection limits |
| Modify anchor only to `±1125899906842625` | 1 | 239, **34 failed** | Geometry, stage, commit and Undo/Redo pass; only `committed.delta.after == expected` fails: retired per-pixel map |
| Committed-document oracle and full-region Undo/Redo | 0 | **241/241 passed** | All 34 sweeps, original randomized geometric comparison and unsafe-publication negative check |
| Corrupt readback-oracle expected paint to zero | 1 | 241, **68 failed** | Commit and Redo full-region readbacks detect unauthorized changed pixels |
| Bypass selection-mask predicate in oracle | 1 | 241, **6 failed** | Mask clipping mismatch detected by stage-count, committed pixel and Redo checks |

Raw [fail-first](T-280-2026-11-23-axis-native-geometry-raw/fail-first.log),
[legal-anchor only](T-280-2026-11-23-axis-native-geometry-raw/legal-anchor-only.log),
[repaired](T-280-2026-11-23-axis-native-geometry-raw/repaired-axis.log),
[pixel mutant](T-280-2026-11-23-axis-native-geometry-raw/t280-pixel-oracle-mutant.log),
[mask mutant](T-280-2026-11-23-axis-native-geometry-raw/t280-mask-oracle-mutant.log).

The oracle uses the existing independent `Geometry2D.get_closest_point_to_segment`
predicate, `DrawingSelection.allows()` gating and exact `0x80442211` straight
RGBA8. The local stage `change_count()` is checked against that oracle. Every
pixel in the computed bounds **plus a one-pixel border** is read through the
public document API after commit, Undo and Redo. No obsolete native delta
inventory is treated as pixel authority. The 34 original cases comprise
4 widths × (4 directed segments × 2 directions), plus 2 mask cases; the 320
seeded geometry trials are unchanged.

## Neighbor regression matrix

Commands use the same `GODOT` and `--headless --path . --script res://...`
syntax as above. Python contracts use
`python3 -m unittest discover -s tests -p '<pattern>' -v`.

| Native script or Python file | Result |
| --- | --- |
| `tests/drawing_dab_geometry_smoke.gd` | **112/112 pass** |
| `tests/drawing_edit_tile_cache_smoke.gd` | **38/38 pass** |
| `drawing/tests/t158_signed_lazy_tile_bounds.gd` | **24/24 pass** |
| `drawing/tests/t159_signed_replay_publication_bounds.gd` | **39/39 pass** |
| `drawing/tests/t160_direct_raster_publish_bounds.gd` | **46/46 pass** |
| `tests/drawing_fill_frontier_smoke.gd` | **56/56 pass** |
| `tests/drawing_publication_tile_cache_smoke.gd` | **30/30 pass** |
| `tests/drawing_fill_tile_cache_smoke.gd` | **5 failures / 30 checks, red** |
| `tests/drawing_fill_verified_stage_smoke.gd` | **8 failures / 29 checks, red** |
| `test_t068_skia_brush.py` | **9 tests, 2 optional skips, no failures** |
| `test_t068_scalar_rgba8.py` | **5/5 pass** |
| `test_t106_oracle_engine_compat.py` | **2/2 pass** |

All per-suite [raw logs](T-280-2026-11-23-axis-native-geometry-raw/)
are retained. The two independent fill failures include stale per-pixel delta
expectations and historically out-of-projection signed anchors. They are
**not repaired in T-280** and prevent claiming the complete T-068 CI group
has passed. The axis-sweep synthetic benchmark is not the fast-push CI gate
and is not a physical input-to-frame measurement.

## Review boundaries

The fixture checks native pixel exactness but performs no visible UI
inspection and no hardware performance benchmark. T-068, T-106 and T-148
remain In Progress and hosted CI is not proven green. T-250 owner manual
review remains unapproved. Do not treat the successful bounded fixture as
approval of these integration/release gates.
