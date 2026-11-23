# T-295 — Native signed Brush per-pixel preflight

**Checkout:** `sprint/2026-11-23-godot-beta4`, Godot
`4.8.beta4.official.b070e63b1`, with `DrawingNativeTiles` loaded from
Rust. Git remote `main` baseline: `bbae76c33a6066582b2cd89e07cc3246fef942ce`.

## Fail-first and correction

A 16px lazy source tile is registered at each legal ±2⁵² document endpoint.
A view-relative one-pixel hard Brush dab lies just beyond the endpoint,
while the anchor itself is valid. Before correction, `_stage()` delegated
straight to tile-local Brush staging without checking the **global** pixel,
which could fetch the source provider, mark a touched pixel and then fail
at publication. A rejected mixed `_stage()` also materialized an accepted
Brush from its fast tile-local representation.

The fail-first real-Rust test reports **30 failures in 50 checks**:
[`fail-first.log`](T-295-2026-11-23-brush-native-projection/fail-first.log).

The corrected `_stage()` validates unsigned RGBA8, local bounds, selection
and native-global projection **before** resolving any tile, materializing
pending Brush/clear or setting coverage. At normal document anchors,
`_check_native_pixel_projection` is calculated false once per session,
so the full four-sided signed projection predicate is reserved for
near-boundary anchors. This matches the publication boundary and preserves
wider non-native coordinates.

The same test now passes **50/50**: no lazy loads or preview/coverage changes
for rejected out-of-projection Brush pixels; accepted retry at the endpoint
commits exact RGBA8, Undo restores transparent hidden RGB, and Redo restores
paint. A mixed-session invalid pixel leaves a previously accepted deferred
Brush untouched before native commit/Undo/Redo:
[`native-green.log`](T-295-2026-11-23-brush-native-projection/native-green.log).

## Neighboring regression results

| Godot beta4/Rust-backed test | Checks | Failures |
| --- | ---: | ---: |
| T-068 stationary dab Geometry2D | 112 | 0 |
| T-068 directional axis sweep | 241 | 0 |
| T-294 native bulk projection | 71 | 0 |
| T-290 mixed bulk preflight | 28 | 0 |
| T-293 native fill projection | 41 | 0 |
| T-227 Atlas embedded Brush, real X11 | 13 | 0 |

The headless attempt for T-227 is **not** acceptance: that witness
requires X11 by design. Its separate `xvfb-run` software-X11 run passed
13/13. The five other neighboring tests passed **493/493**. All raw logs are
in the [evidence directory](T-295-2026-11-23-brush-native-projection/).

## Required CI and reproducibility

The existing `ci_t068_stationary_dab_parity` workflow step now runs the
50-check native witness and checks both its exact marker and strict failure
log. The 46-step fast-desktop CI inventory remains unchanged.

```bash
G=/mnt/data/unpacked/drawing-toolchain-linux-x86_64/bin/godot
GODOT_SILENCE_ROOT_WARNING=1 "$G" --headless --path . \
  --script res://tests/t295_brush_native_projection.gd
python3 -m unittest discover -s tests -p 'test_t29?_*.py' -v
python3 tools/validate_ticket_store.py
```

**Limits:** This proves one per-pixel stage safety contract. It does not
complete T-068 performance/portability, T-148 fully native-owned raster
staging, hosted beta4 CI, physical Windows/Linux review, or T-250 owner
visual acceptance. No approval is inferred.
