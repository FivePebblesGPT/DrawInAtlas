# T-277 — Native Skia live-oracle parity correction (2026-11-23)

## Source / failure evidence

- Worktree start `4ee92465`, compared to remote `main` `bbae76c33a6066582b2cd89e07cc3246fef942ce`.
- Host: bundled Godot `4.8.beta4.official.b070e63b1`, built native
  `DrawingNativeTiles` loaded (`godot-rust` API 4.7; runtime beta4).
- Existing live oracle command fails at the first case:
  `ERROR: T068_SKIA_BRUSH_ORACLE_FAILED: stationary_dab`, exit 1.
- The original fixture `tools/benchmarks/t068_skia_brush_oracle.json`
  retains `anchor_x=9007199254740993`, `anchor_y=-9007199254740993`
  and the Godot beta2 engine label. These historical coordinates now exceed
  the native tile publication bound, demonstrated independently in T-158,
  T-160 and T-276. A valid native-range anchor makes the original generator
  run, but reading `committed.delta.after` then returns **zero changed
  indices** for 15 painted/erased cases despite nonempty coverage; native
  history does not expose the retired legacy per-pixel delta map.

## Repair and strict parity

- The **live** generator now uses precisely `+1125899906842625`,
  `-1125899906842625`, with nonzero low bits and safely within native
  signed projection. Historical pinned JSON is **not rewritten**.
- After a successful commit (or explicit cancel for zero-alpha no-op), it
  reconstructs the 32×32, straight RGBA8 raster from public
  `DrawingDocument.read_pixel` results; failures abort generation. It
  compares every channel to the original seed to derive changed indices.
- `require_native_brush_matches_pinned_beta2` permits **only** this exact
  anchor substitution plus the existing engine-label substitution before
  delegating to the full equality check. All 16 case dictionaries, source
  SHA-256, geometry, coverage, changes, after SHA-256, transform/view path,
  and ordering must match the immutable beta2 fixture exactly.
- A separate T-106 regression mutates both anchor components, digest,
  coverage, changed pixels and case order. Every mutation is rejected.

Reproduce from the repository root:

```bash
GODOT=/mnt/data/unpacked/drawing-toolchain-linux-x86_64/bin/godot
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path . \
  --script res://tests/drawing_t068_skia_brush_oracle.gd -- /tmp/t277-native-brush.json
GODOT_SILENCE_ROOT_WARNING=1 T068_GODOT="$GODOT" \
  python3 -m unittest discover -s tests -p test_t068_skia_brush.py -v
python3 -m unittest discover -s tests -p test_t106_oracle_engine_compat.py -v
python3 -m unittest discover -s tests -p test_t068_matched_brush.py -v
python3 -m unittest discover -s tests -p test_t068_skia_cpu.py -v
python3 -m unittest discover -s tests -p test_t068_scalar_rgba8.py -v
python3 tools/validate_ticket_store.py
```

| Witness | Local result |
| --- | --- |
| Original live beta4 oracle | Failed first `stationary_dab` case, exit 1 |
| Corrected live beta4 oracle | **16/16** cases, exit 0; all historical raster fields equal |
| T-068 Skia brush Python | 9 tests, **0 failures**, 1 optional live Skia-wheel skip |
| T-106 oracle engine compatibility | 2 tests, **0 failures**, including mutation rejection |
| T-068 matched brush | 4 tests, 0 failures, 1 optional Blend2D runtime skip |
| T-068 Skia CPU | 3 tests, 0 failures, 1 optional Skia-wheel skip |
| T-068 scalar RGBA8 | 5 tests, **0 failures** |

### Important remaining failures outside this ticket

The untouched native-required T-068 CI group still includes these
independently red historical Godot scripts under beta4:

- `tests/drawing_dab_geometry_smoke.gd` — **75/125 failures**, including
  legacy stationary dab commit and Undo/Redo expectations.
- `tests/drawing_axis_sweep_smoke.gd` — **34/137 failures**, primarily
  legacy swept path commits.
- `tests/drawing_edit_tile_cache_smoke.gd` — **3/31 failures** concerning
  touched-pixel delta counts and out-of-projection signed coordinates.

They must be reviewed against the current required-native history contract
in separate work, not hidden, skipped, or changed within this Skia-oracle
repair. Full fast-desktop CI, physical benchmarks, owner UX gate T-250,
T-068 research gates and T-106 hosted acceptance **are not complete**.
