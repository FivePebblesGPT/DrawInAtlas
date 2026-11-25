# T-292 — Signed flood-fill frontier preflight

**Build:** sprint/2026-11-23-godot-beta4, Godot
`4.8.beta4.official.b070e63b1` with compiled Rust `DrawingNativeTiles`
loaded (confirmed by Godot startup). Baseline remote `main`:
`bbae76c33a6066582b2cd89e07cc3246fef942ce`.

## Fail first

The original `flood_fill()` validated the seed but enqueued all four neighbors
without a range fence. A new native-backed fixture registers a lazy tile at a
legal positive signed edge and a matching-color *forbidden* neighboring tile;
for the negative edge, the invalid pixel shares the source tile. Four legal
X+/X−/Y+/Y− seeds returned `COORD_RANGE`, with lazy loading of the forbidden
positive neighbors. Baseline exits 1, **10 failures / 22 checks** (the
commit/Undo/Redo checks are not attempted after rejection).

## Fix and real validation

`DrawingEditSession.flood_fill()` now checks the `_stage()` view-relative
±2³⁰ interval **before** a neighboring pixel enters the frontier. The
original seed, color, selection, budget and source preflights remain unchanged;
inside the range the four-connected traversal works as before.

All four boundary cases now succeed with one staged pixel. Positive forbidden
neighbor tile sources remain unresolved; each test commits exact RGBA8, Undo
restores alpha-zero nonzero RGB, and Redo reproduces the new pixel. **38/38
checks** pass. The existing required fast-desktop CI group retains 46 step
IDs and runs this fixture with a strict expected count and log marker.

Run from repository root:

```bash
G=/mnt/data/unpacked/drawing-toolchain-linux-x86_64/bin/godot
GODOT_SILENCE_ROOT_WARNING=1 "$G" --headless --audio-driver Dummy \
  --path . --script res://tests/t292_fill_frontier_bounds.gd
python3 tools/check_godot_model_log.py \
  docs/evidence/T-292-2026-11-23-fill-frontier/t292_fill_frontier_bounds.log \
  --marker T292_FRONTIER_PASSED
python3 -m unittest discover -s tests -p 'test_t29?_*.py' -v
python3 tools/validate_ticket_store.py
```

| Rust-backed neighbor | Passed |
| --- | ---: |
| T-289 invalid seed/color | 23/23 |
| T-290 bulk preflight | 28/28 |
| T-291 masked-out seed | 33/33 |
| T-068 fill frontier | 56/56 |
| T-068 fill tile cache | 39/39 |
| T-068 verified mixed fill | 36/36 |
| T-068 native publication cache | 30/30 |
| T-068 edit tile cache | 38/38 |

Retained raw logs: [test directory](T-292-2026-11-23-fill-frontier/).
The hosted required workflow has **not** been rerun on this commit. This is
not Windows/Linux hardware acceptance, complete Rust raster ownership,
performance signoff, or T-250 owner visual approval.
