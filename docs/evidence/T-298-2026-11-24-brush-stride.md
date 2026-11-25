# T-298 — Small-stride Brush publication vs native tile ABI

**Checkout:** `sprint/2026-11-23-godot-beta4` based on remote `main`
`bbae76c33a6066582b2cd89e07cc3246fef942ce`; local Godot
`4.8.beta4.official.b070e63b1` with Rust GDExtension loaded.

## Reproduction

The previous T-095 3px reference test emitted **8 failures in 612 checks**
for Brush and Eraser commit, published RGBA8, Undo and Redo. A diagnostic
instrumentation on the unchanged source showed `NATIVE_TILES` failures:
`Direct tile edit exceeds native transfer budget` (Brush) and
`Native tile bootstrap rejected` (Eraser). The canonical 3px reference
committed correctly. The active test explicitly sets the canonical-reference
publisher off; the fast variant must exercise its *default* publisher.

After strengthening the oracle, temporarily removing the new session guard
produced **10/622 failures** (including explicit publisher-selection checks):
[fail-first log](T-298-2026-11-24-brush-stride/fail-first.log). That injected
mutation was reverted before final testing.

## Verified correction

`DrawingEditSession._init()` disables its tile-fast Brush publisher for
storage strides below 16, leaving such valid documents on their canonical
pixel-key publication path. The T-095 reference test independently compares
full preview, committed RGBA8 and exact Undo/Redo over signed tiles,
selection holes, transparent hidden RGB and lazy read failures. Supported
strides 16, 30, 64 and 255 continue to use the fast native tile path.

| Godot beta4 + Rust test | Checks | Result |
| --- | ---: | --- |
| T-095 tile-reference fast/canonical parity | 632 | Passed |
| T-095 tile-key cache, strides 1/3/16/30/64/255/256/2048 | 33,037 | Passed |
| T-095 signed source tile lookup | 4,193 | Passed |
| T-095 deferred staging | 492 | Passed |
| T-095 cross-batch dabs | 663 | Passed |
| T-095 axis scanline | 278 | Passed |
| T-160 direct raster publication bounds | 46 | Passed |
| T-295 native signed Brush projection | 50 | Passed |

Primary logs: [tile reference](T-298-2026-11-24-brush-stride/tile-reference.log),
[tile key](T-298-2026-11-24-brush-stride/tile-key.log),
[native projection](T-298-2026-11-24-brush-stride/native-projection.log).
The tests use existing required T-095 on-demand CI scripts; they are not
replaced by superficial source assertions. `tests/check_explicit_types.py`
passes. Godot's frame/rendered UI and physical latency were not part of this
nonvisual data-publishing ticket.

## Boundaries

This is an isolated synthetic-stride correctness repair, not a native
performance improvement or acceptance. T-095 remains In Progress and
`manual_review: true`; T-068 and T-148 remain In Progress and T-250 is
not owner-approved. No claim of a fresh hosted CI run is made.
