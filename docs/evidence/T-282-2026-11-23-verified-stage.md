# T-282 — Rust-backed verified-source fill staging, 2026-11-23

## Environment and scope

- Local sprint checkout based on `sprint/2026-11-23-godot-beta4`, starting from
  `a488f997` (T-281). Remote `main` at validation time was
  `bbae76c33a6066582b2cd89e07cc3246fef942ce`.
- Real bundled Godot `4.8.beta4.official.b070e63b1`, with
  `godot-rust` initialized (API `v4.7.stable.official`, runtime `v4.8.beta4`).
- Edited **only** `tests/drawing_fill_verified_stage_smoke.gd` and ticket/evidence
  documentation. This is a validation fixture repair, not a native performance
  improvement or a production raster fix.

Run from the repository root:

```bash
GODOT=/mnt/data/unpacked/drawing-toolchain-linux-x86_64/bin/godot
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path . \
  --script res://tests/drawing_fill_verified_stage_smoke.gd
python3 tools/validate_ticket_store.py
```

## Fail-first and oracle integrity

| Trial | Actual result | Retained log |
| --- | --- | --- |
| Original, unmodified native witness | **8 failures / 29 checks** | [fail-first](T-282-2026-11-23-verified-stage-raw/fail-first.log) |
| Corrected fixture | **36/36 passed** | [repaired](T-282-2026-11-23-verified-stage-raw/repaired.log) |
| Mutate the late mixed-command pixel to the earlier color | **2 failures / 36**, nonzero exit | [local pixel mutation](T-282-2026-11-23-verified-stage-raw/local-pixel-mutant.log) |
| Mutate one far-world seam pixel to the earlier color | **3 failures / 36**, nonzero exit | [far seam mutation](T-282-2026-11-23-verified-stage-raw/far-seam-mutant.log) |

Mutations changed only expected results in the fixture and were restored
immediately afterwards. The mismatch was detected on both commit and Redo;
far-world unsafe-source preservation also detected the corrupted expectation.

## What the independent expectations establish

The primary fixture seeds a 5×3 connected transparent-RGB region, installs an
unequal barrier at (2,0), and stages an earlier edit followed by two attempts
at fill (insufficient budget then valid fill) and a later edit to (1,1). Its
per-session `_before` and `_after` assertions still verify that staging uses
**original immutable source bytes** and later edits can override previews.
The test snapshots every pixel across a (-1,-1) to (5,3) region, including
blank guards, then compares the full region after one native commit, a single
Undo and a single Redo. The original transparent RGB and barrier return on
Undo; Redo restores the complete final fill and late edit.

For far-world behavior, a 16-aligned valid signed anchor
`1125899906842624` makes x=-1/0 cross an actual source-tile boundary.
A selection-masked first fill stages the two left pixels, and an unmasked
second fill stages three original-source pixels including the right neighbor.
Five absolute world positions (three pixels plus guards) are read by the
public document API after stage, commit, Undo and Redo. The >2^53 historical
anchor (`9007199254740993`) still stages through the public 64-bit edit
interface, but native publication rejects it without changing revision,
legal painted pixels, or out-of-projection source bytes. A separate
concurrent revision change continues to reject the detached transaction.

## Neighboring regression matrix

All native scripts ran with the same `--headless --path . --script` invocation.

| Script | Result | Log |
| --- | --- | --- |
| `tests/drawing_fill_tile_cache_smoke.gd` | 39/39 passed | [log](T-282-2026-11-23-verified-stage-raw/drawing_fill_tile_cache_smoke.log) |
| `tests/drawing_fill_frontier_smoke.gd` | 56/56 passed | [log](T-282-2026-11-23-verified-stage-raw/drawing_fill_frontier_smoke.log) |
| `tests/drawing_publication_tile_cache_smoke.gd` | 30/30 passed | [log](T-282-2026-11-23-verified-stage-raw/drawing_publication_tile_cache_smoke.log) |
| `tests/drawing_edit_tile_cache_smoke.gd` | 38/38 passed | [log](T-282-2026-11-23-verified-stage-raw/drawing_edit_tile_cache_smoke.log) |
| `tests/drawing_axis_sweep_smoke.gd` | 241/241 passed | [log](T-282-2026-11-23-verified-stage-raw/drawing_axis_sweep_smoke.log) |
| `tests/drawing_dab_geometry_smoke.gd` | 112/112 passed | [log](T-282-2026-11-23-verified-stage-raw/drawing_dab_geometry_smoke.log) |
| `drawing/tests/t158_signed_lazy_tile_bounds.gd` | 24/24 passed | [log](T-282-2026-11-23-verified-stage-raw/t158_signed_lazy_tile_bounds.log) |
| `drawing/tests/t159_signed_replay_publication_bounds.gd` | 39/39 passed | [log](T-282-2026-11-23-verified-stage-raw/t159_signed_replay_publication_bounds.log) |
| `drawing/tests/t160_direct_raster_publish_bounds.gd` | 46/46 passed | [log](T-282-2026-11-23-verified-stage-raw/t160_direct_raster_publish_bounds.log) |

Python contract suites: `test_t068_skia_brush.py` (9 tests, 2 optional
skips), `test_t068_scalar_rgba8.py` (5/5),
`test_t106_oracle_engine_compat.py` (2/2). Raw
[logs](T-282-2026-11-23-verified-stage-raw/) retained.

## Unclosed gates

This closes a single T-068 CI fixture failure, not the complete T-068
backend/performance/portability milestone. T-106 and T-148 remain In Progress,
and full hosted CI (including other independent failures) was not rerun.
T-250 remains Manual Review without explicit owner approval. No changes
were made to review frontmatter or protected dependent tickets.
