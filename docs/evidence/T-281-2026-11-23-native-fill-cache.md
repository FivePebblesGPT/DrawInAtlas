# T-281 — Native flood-fill source-tile cache witness (2026-11-23)

## Environment and scope

- Local sprint branch `sprint/2026-11-23-godot-beta4`; starting commit
  `3ad49c49`; remote `main` at test time `bbae76c33a6066582b2cd89e07cc3246fef942ce`.
- Executable `/mnt/data/unpacked/drawing-toolchain-linux-x86_64/bin/godot`;
  `4.8.beta4.official.b070e63b1` with native Rust GDExtension initialized
  (`API v4.7.stable.official`, runtime `v4.8.beta4.official`).
- Modified **only** `tests/drawing_fill_tile_cache_smoke.gd` and ticket/evidence
  documentation. No raster algorithm or native history implementation changed.

From repository root:

```bash
GODOT=/mnt/data/unpacked/drawing-toolchain-linux-x86_64/bin/godot
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path . \
  --script res://tests/drawing_fill_tile_cache_smoke.gd
python3 tools/validate_ticket_store.py
```

| Stage | Result | Recorded evidence |
| --- | --- | --- |
| Unchanged baseline | **5/30 failed** | [fail-first](T-281-2026-11-23-native-fill-cache-raw/fail-first.log) |
| Corrected fixture (and final rerun) | **39/39 passed** | [repaired](T-281-2026-11-23-native-fill-cache-raw/repaired.log), [final](T-281-2026-11-23-native-fill-cache-raw/final.log) |
| Replace three expected committed pixels with clear | **2/39 failed** | [pixel mutant](T-281-2026-11-23-native-fill-cache-raw/pixel-mutation.log) |
| Move expected masked pixel from x=16 to x=17 | **2/39 failed** | [mask mutant](T-281-2026-11-23-native-fill-cache-raw/mask-mutation.log) |

## Independent pixel and history assertions

The test still exercises source lazy-reference absence, missing fetch,
corrupt hash/size, repeated resolves and verified cache re-use with exact
fetch counts, failed-fill atomic rollback, transparent hidden RGB, masked
fill, blank seed, bounded candidates, and cancellation. New public
`DrawingDocument.read_pixel()` snapshots cover x=14..19/y=-1..1. Against
an independent fixed expectation, only x=15,16,17 are modified by the
unmasked fill; the masked fill modifies only x=15,16. Each operation now
compares **every pixel in the region** after commit, Undo, and Redo.
The source edit stays on its original revision until native publication
and advances exactly once.

A `9007199254740993` signed public edit may stage three candidate pixels,
but must reject native publication with **no revision or source change**.
A distinct legal anchor `1125899906842625` (`anchor % 16 == 1`) fills
three signed pixels at offsets -2,-1,0, spanning the native 16px tile seam.
Five positions including one-pixel guards are compared with exact 32-bit
straight RGBA8 after commit, Undo and Redo, preserving hidden RGB on Undo.

The two intentionally corrupted test expectations were applied temporarily
and restored before commit. Pixel mutation is caught by commit+Redo, and
selection-mask mutation is caught by commit+Redo; no fixture was blessed
by automatically updating a reference hash.

## Neighbor matrix

Same `GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path . --script
res://<path>` invocation as above.

| Native script | Result |
| --- | --- |
| `tests/drawing_fill_frontier_smoke.gd` | **56/56 passed** |
| `tests/drawing_publication_tile_cache_smoke.gd` | **30/30 passed** |
| `tests/drawing_edit_tile_cache_smoke.gd` | **38/38 passed** |
| `tests/drawing_dab_geometry_smoke.gd` | **112/112 passed** |
| `tests/drawing_axis_sweep_smoke.gd` | **241/241 passed** |
| `drawing/tests/t158_signed_lazy_tile_bounds.gd` | **24/24 passed** |
| `drawing/tests/t159_signed_replay_publication_bounds.gd` | **39/39 passed** |
| `drawing/tests/t160_direct_raster_publish_bounds.gd` | **46/46 passed** |
| `tests/drawing_fill_verified_stage_smoke.gd` | **8/29 failed (still open)** |

The Python contracts also pass: `test_t068_skia_brush.py` (**9 tests,
2 optional skips**), `test_t068_scalar_rgba8.py` (**5/5**), and
`test_t106_oracle_engine_compat.py` (**2/2**). Their raw logs are
[retained together with the Godot matrix](T-281-2026-11-23-native-fill-cache-raw/).
The separate
verified-staging fixture still assumes per-pixel `_before`/`_after` and
`delta.after` on native publication, and attempts a `>2^53` far-world
seed. That work belongs to another ticket; this test does not exercise the
full-editor rendering frame or physical pointer latency.

## Gate status

The T-281 fixture is a bounded, independently passable validation slice.
T-068/T-106/T-148 and hosted CI are **not complete**; no T-250 owner or
physical UX review is inferred. No binary/LFS assets changed for this ticket.
