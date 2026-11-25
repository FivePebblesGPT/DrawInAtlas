# T-293 — Native flood-fill global signed projection guard

**Checkout:** `sprint/2026-11-23-godot-beta4`, Godot
`4.8.beta4.official.b070e63b1`, with loaded Rust `DrawingNativeTiles`
(confirmed by startup). Remote baseline checked: `bbae76c33a6066582b2cd89e07cc3246fef942ce`.

## Fail-first reproduction

A 16px lazy tile is registered at a permitted ±2⁵² projection endpoint.
The session uses a permitted historical ±(2⁵²+1) anchor, so its **local**
seed at zero is valid but its **global** pixel is invalid for native
publication. A valid local retry moves one pixel back onto the boundary;
on positive X/Y the adjacent out-of-projection pixel occupies the same
registered source tile and has the matching source RGBA8.

The unmodified session returned the wrong failure/no-op for invalid seeds,
called the lazy provider, and could stage the positive-boundary neighbor
before the native commit rejected the legal edge edit. The initial test
failed **18 of 41 checks**: [`fail-first.log`](T-293-2026-11-23-native-fill-projection/fail-first.log).

## Correction and controls

`flood_fill()` now determines whether native publication is required using
the same store/stride/extension condition as `DrawingDocument._publish_edit()`.
When native is required, it checks **global** source and frontier coordinates
against the signed ±2⁵² projection budget before resolving source tiles.
This is in addition to (not a replacement for) T-289/T-292 view-relative
preflights and T-291's selection exclusion. Historical non-native addressing
is not newly restricted.

The corrected real-native test passes **41/41**, including exact committed
RGBA8, native Undo restoring hidden RGB with alpha zero, and Redo:
[`native-green.log`](T-293-2026-11-23-native-fill-projection/native-green.log).
Two deliberate mutation controls reliably break the witness: removing the
seed check fails 18/41; removing the frontier check fails 10/41.

## Reproduce

From repository root, using the supplied toolchain:

```bash
G=/mnt/data/unpacked/drawing-toolchain-linux-x86_64/bin/godot
GODOT_SILENCE_ROOT_WARNING=1 "$G" --headless --audio-driver Dummy \
  --path . --script res://tests/t293_fill_native_projection.gd
python3 -m unittest discover -s tests -p 'test_t293_fill_native_projection_ci.py' -v
python3 tools/validate_ticket_store.py
```

| Neighboring Rust-backed witness | Result |
| --- | ---: |
| T-289 invalid fill seed preflight | 23/23 |
| T-290 bulk-edit preflight | 28/28 |
| T-291 masked seed | 33/33 |
| T-292 signed view-relative frontier | 38/38 |
| T-068 fill frontier | 56/56 |
| T-068 lazy tile cache | 39/39 |
| T-068 verified mixed staging | 36/36 |
| T-068 native publication cache | 30/30 |

All adjacent runs passed **283/283** checks. Raw logs, both mutation-control
logs and baseline are retained under
[`T-293-2026-11-23-native-fill-projection/`](T-293-2026-11-23-native-fill-projection/).
Required CI still has 46 step IDs; this ticket does **not** provide a fresh
hosted CI result, cross-platform hardware benchmarks or T-250 owner approval.
T-068/T-148 remain In Progress.
