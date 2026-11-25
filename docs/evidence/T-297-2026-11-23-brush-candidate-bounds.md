# T-297 — Overflow-safe finite Brush candidate windows

**Checkout:** `sprint/2026-11-23-godot-beta4`; remote `main` basis
`bbae76c33a6066582b2cd89e07cc3246fef942ce`. Running Godot:
`4.8.beta4.official.b070e63b1`, with loaded Rust `DrawingNativeTiles`.

## Reproduction

The test feeds valid finite widths `1e30` and `1e100` into a one-point
hard-Brush path. Previously, `floori`/`ceili` converted extreme floating
bounds *before* clipping or checking the candidate budget. Signed integer
saturation/wrap made `columns <= 0` and the gesture returned success without
pixel changes while remembering the last pointer. The same overflow in
scanline helpers silently dropped a finite-radius 2×2 clipped Brush. The
original unchanged production source failed **48/113 checks** against the
final test: [fail-first log](T-297-2026-11-23-brush-candidate-bounds/fail-first.log).

The correction keeps candidate bounds in floating point through clipping and
safe-coordinate checks, then converts the final bounded rectangle to ints.
Dab, horizontal/vertical and oblique scanline helpers also clamp their
floating subranges before integer conversion. Their original Geometry2D
pixel-center predicates and once-only overlap semantics are unchanged.

## Native acceptance

The corrected witness passes **113/113** checks:
[native-green log](T-297-2026-11-23-brush-candidate-bounds/native-green.log).
It verifies rejected unbounded widths neither stage pixels nor change the
session's last pointer, followed by a valid retry, exact commit, Undo and
Redo. Four 2×2 clipped paths (dab, horizontal, vertical and oblique) paint
all four canonical pixels and no neighboring pixels. Each retains a
transparent stored source with nonzero hidden RGB at (1,1), restores it on
Undo and reproduces the opaque Brush on Redo. The native extension was loaded
and the test exits nonzero on any missing/corrupt marker.

## Neighboring regressions

| Real Godot beta4 witness | Checks | Exit |
| --- | ---: | --- |
| T-068 stationary dab geometry | 112/112 | 0 |
| T-068 axis sweep geometry | 241/241 | 0 |
| T-068 verified fill staging | 36/36 | 0 |
| T-294 bulk signed projection | 71/71 | 0 |
| T-295 Brush signed projection | 50/50 | 0 |
| T-296 Delete signed projection | 50/50 | 0 |
| Atlas Brush smoke | 53/53 | 0 |
| T-290 bulk edit preflight | 28/28 | 0 |
| T-068 lazy fill tile cache | 39/39 | 0 |
| T-095 axis scanline bounds (Drawing) | 278/278 | 0 |
| T-095 oblique geometry (Drawing) | 86/86 | 0 |
| T-095 cross-batch dab (Drawing) | 663/663 | 0 |
| T-095 deferred staging (Drawing) | 492/492 | 0 |
| T-095 coverage oracle (Drawing) | 32/32 | 0 |
| T-095 blend math (Drawing) | 4/4 | 0 |
| T-095 tile-reference cache (Drawing, stride=3) | 604/612 | 1 |

**Pre-existing failure isolated:** the tile-reference cache test's eight
stride-3 commit/Undo/Redo failures reproduce identically on untouched
`HEAD` source (`t095_brush_tile_reference_cache_baseline.log`). They are
not introduced or fixed by T-297, and do not justify closing T-095's owner
performance/review gate. Every other listed witness exits successfully.
Logs are retained in [the evidence directory](T-297-2026-11-23-brush-candidate-bounds/).

**Python and static gates:** 13/13 focused T-290/T-294–T-297 tests pass;
`python3 tests/check_explicit_types.py` passes (606 project scripts and 33
skills); Ruff and Ty pass on the new CI contract (Ty with `tools` as an
explicit search path). `tools/validate_ticket_store.py` validates 297 tickets
and manual-review dependencies.

## Reproduce

```bash
G=/mnt/data/unpacked/drawing-toolchain-linux-x86_64/bin/godot
GODOT_SILENCE_ROOT_WARNING=1 "$G" --headless --path . \
  --script res://tests/t297_brush_candidate_bounds.gd
python3 tools/check_godot_model_log.py \
  docs/evidence/T-297-2026-11-23-brush-candidate-bounds/native-green.log \
  --marker T297_BRUSH_BOUNDS_PASSED
python3 -m unittest tests.test_t297_brush_candidate_bounds_ci -v
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
```

**Limits:** This is a narrow raster-candidate correctness fix. It is not a
hardware 96px latency result, full Rust ownership milestone, hosted beta4 CI
pass, cross-platform packaging validation or T-250 owner UX approval. Keep
T-068, T-095 and T-148 In Progress, and preserve all manual-review gates.
