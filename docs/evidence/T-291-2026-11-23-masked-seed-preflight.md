# T-291 — selection-excluded fill seed preflight

**Build:** `sprint/2026-11-23-godot-beta4` on Linux x86-64, Godot
`4.8.beta4.official.b070e63b1`, required compiled Rust `DrawingNativeTiles`
GDExtension loaded (startup confirms godot-rust). Remote baseline main:
`bbae76c33a6066582b2cd89e07cc3246fef942ce`.

## Fail first and fix

The new Godot fixture stages a native-backed deferred Brush on a separate
storage tile, then attempts four `flood_fill()` calls at a seed whose source
is lazy and deliberately unavailable. Each seed is excluded by a different
selection mode (outside rectangular bounds, active empty, pixel-mask hole,
inversion). The historical path reads the lazy source before discovering the
seed cannot be painted, and materializes the deferred Brush if the loader
succeeds. The revised fixture without the new guard exits **1**, with **10
failures / 33 checks**. The original early 30-check fixture produced 12
failures, recorded separately during diagnosis.

The correction checks mask authorization after the existing budget, session,
coordinate and color checks but before `_fill_source_pixel()`. The successful
no-op returns the current change count without modifying the preview. The
same session then allows the seed, resolves one lazy tile and publishes exact
RGBA8 for one fill plus the prior Brush; native Undo/Redo restore both and
retain alpha-zero hidden RGB. Invalid color/coordinate precedence remains
unchanged. Final fixture passes **33/33**.

## Commands and evidence

From the repository root, with the provided Godot beta4/Rust toolchain:

```bash
G=/mnt/data/unpacked/drawing-toolchain-linux-x86_64/bin/godot
GODOT_SILENCE_ROOT_WARNING=1 "$G" --headless --audio-driver Dummy \
  --path . --script res://tests/t291_masked_fill_seed_preflight.gd
python3 tools/check_godot_model_log.py \
  docs/evidence/T-291-2026-11-23-masked-fill/native-green.log \
  --marker T291_MASKED_FILL_PASSED
python3 -m unittest discover -s tests -p 'test_t291_masked_fill_seed_ci.py' -v
python3 tools/validate_ticket_store.py
```

| Native witness | Passing checks |
| --- | ---: |
| T-291 masked seed and deferred Brush | 33/33 |
| T-289 invalid seed/color preflight | 23/23 |
| T-290 bulk region preflight | 28/28 |
| T-068 fill frontier | 56/56 |
| T-068 lazy tile-cache fill | 39/39 |
| T-068 verified fill staging | 36/36 |
| T-068 publication cache | 30/30 |
| T-068 edit tile cache | 38/38 |

Raw logs (including fail-first): [T-291 log directory](T-291-2026-11-23-masked-fill/).
All scripts exited 0 in the final runs and printed their expected success
markers; no source-only appearance assertions are introduced. The new test
runs within the existing `ci_t068_stationary_dab_parity` required CI group,
not a new untracked job.

**Remaining gates:** This does not establish full native tile authority for
fill, broad T-068 benchmark and device results, hosted beta4 CI, Windows
packaging or T-250 owner visual approval. T-148 and T-068 remain In Progress.
