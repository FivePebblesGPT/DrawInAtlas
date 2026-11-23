# T-279 — Stationary-dab native geometry oracle evidence (2026-11-23)

## Scope and environment

- Local baseline: `56c5186d`, branch `sprint/2026-11-23-godot-beta4`.
- Last verified remote `main`: `bbae76c33a6066582b2cd89e07cc3246fef942ce`.
- Required compiled native extension: `DrawingNativeTiles` loaded via godot-rust
  API 4.7 under `Godot 4.8.beta4.official.b070e63b1`.
- Only the T-068 `drawing_dab_geometry_smoke.gd` fixture and ticket/docs
  changed; no production raster/history or oracle pixel geometry changed.

## Fail-first and isolate the cause

Run from repository root, with the toolchain's `godot` executable:

```bash
GODOT=/mnt/data/unpacked/drawing-toolchain-linux-x86_64/bin/godot
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path . \
  --script res://tests/drawing_dab_geometry_smoke.gd
```

1. Unmodified `>2^53` fixture: **125 checks / 75 failures**, exit 1.
   All 15 native commit attempts failed, with downstream geometry/history
   assertions. [Raw log](T-279-2026-11-23-dab-native-geometry-raw/fail-first.log).
2. Alter **only** the anchor to native-publishable `±1125899906842625`:
   **125 checks / 15 failures**, exit 1. All raster geometry and Undo/Redo
   assertions now pass; **only** the `committed.delta.after.size()`
   assertions fail. The delta is intentionally no longer a per-pixel
   inventory under native tile ownership.
   [Raw log](T-279-2026-11-23-dab-native-geometry-raw/legal-anchor-only.log).
3. Replace that obsolete history-map assertion with an independent
   Geometry2D expected-coverage comparison against the stage's touched-pixel
   count. Verify the complete rectangle after commit, blank after Undo and
   exactly restored after Redo using `DrawingDocument.read_pixel()`; retain
   RGBA8/hidden RGB/no-op cases and add a negative `>2^53` publication check.
   Final: **112 checks / 0 failures**, exit 0.
   [Raw log](T-279-2026-11-23-dab-native-geometry-raw/repaired-dab.log).

The reduction in total assertions is from merging the old sample-only
Redo probe into the **stronger full-region** Redo comparison, not removal
of any brush widths, centers or pixel-geometry comparisons. All 15 dab
combinations (five widths × three fractional coordinates) still run.

## Adjacent native and comparator checks

| Command/script | Outcome |
| --- | --- |
| `tests/drawing_edit_tile_cache_smoke.gd` | **38/38** pass |
| `drawing/tests/t158_signed_lazy_tile_bounds.gd` | **24/24** pass |
| `drawing/tests/t159_signed_replay_publication_bounds.gd` | **39/39** pass |
| `drawing/tests/t160_direct_raster_publish_bounds.gd` | **46/46** pass |
| `tests/drawing_t068_skia_brush_oracle.gd -- /tmp/skia.json` | **16/16** immutable fixture cases pass |
| `python -m unittest discover -s tests -p test_t068_skia_brush.py -v` | **9 tests**, 1 optional wheel skip; no failures |
| `python -m unittest discover -s tests -p test_t106_oracle_engine_compat.py -v` | **2/2** pass |
| `python -m unittest discover -s tests -p test_t068_scalar_rgba8.py -v` | **5/5** pass |
| `tests/drawing_axis_sweep_smoke.gd` | **34 failures / 137 checks**, still red (separate work) |

Logs for all commands are retained in
[T-279 raw evidence](T-279-2026-11-23-dab-native-geometry-raw/).
No visual UI approval is claimed for this headless native validation.

## Closure boundaries

T-279 is a bounded fixture repair only. T-068/T-106/T-148 are still
In Progress; the T-068 axis-sweep test and other hosted fast-desktop CI
failures remain. T-250 remains Manual Review without owner approval.
The test is not an assertion of production hard-brush UI performance or
Windows/Linux hardware acceptance.
