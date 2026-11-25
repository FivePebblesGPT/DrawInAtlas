# T-290 — bulk raster preflight before lazy materialization

**Date/build:** 2026-11-23, Linux x86-64, Godot 4.8.beta4
`b070e63b1`, required Rust `DrawingNativeTiles` GDExtension loaded,
`sprint/2026-11-23-godot-beta4`. Remote main reference:
`bbae76c33a6066582b2cd89e07cc3246fef942ce`.

## Fail first

A registered lazy source at storage tile `(67108863,0)` covers the final
allowed *view-relative* pixel `1073741823`. A 2×1 request starts on that
pixel and ends at invalid `1073741824`. The original loops resolved the
first lazy tile and staged an edit before the failure. A second session
staged a real deferred hard Brush; invalid colors and the same invalid
rectangle/byte region flattened its preview even though the calls failed.

Before the change, the real Godot witness exited 1, reporting **8 failures
in 24 checks**. All failures are from observed lazy calls or premature
materialization; the positive mixed-edit transactions did not fail. The
unmodified fail-first log is retained alongside the final witnesses.

## Fix and exact evidence

`addons/drawing/edit_session.gd` now rejects invalid bulk-area view-relative
extrema and unsigned colors before materializing any accepted preview.
`paint_polygon()` also checks closed-session and color bounds before changing
preview representation. No rendering or visual layout changed.

```bash
G=/mnt/data/unpacked/drawing-toolchain-linux-x86_64/bin/godot
GODOT_SILENCE_ROOT_WARNING=1 "$G" --headless --path . \
    --script res://tests/t290_bulk_edit_preflight.gd
python3 tools/check_godot_model_log.py /mnt/data/t290-neighbors/t290_bulk_edit_preflight.log \
    --marker T290_BULK_PREFLIGHT_PASSED
python3 -m unittest discover -s tests -p 'test_t290_bulk_edit_preflight_ci.py' -v
python3 tools/validate_ticket_store.py
```

The final witness passes **28/28**: no invalid callback, unchanged deferred
Brush, valid retry with a Brush + rectangle + exact alpha-zero RGBA8 region +
filled polygon in one native publication, and exact Undo/Redo of all modified
pixels. The CI inventory remains 46 required groups and the new native test
is inside `ci_t068_stationary_dab_parity`, with strict exit, marker and
runtime-log rejection.

| Native fixture | Passed |
| --- | ---: |
| T-290 bulk edit preflight | 28/28 |
| T-289 flood-fill early preflight | 23/23 |
| T-068 verified fill staging | 36/36 |
| T-068 lazy fill cache | 39/39 |
| T-068 frontier | 56/56 |
| T-068 edit tile cache | 38/38 |
| T-068 publication tile cache | 30/30 |
| Drawing history | 101/101 |

Raw Godot/CI logs: [`T-290-2026-11-23-bulk-preflight/`](T-290-2026-11-23-bulk-preflight/).

**Limits:** This checks a bounded user-data-integrity invariant, not physical
input latency, general native raster ownership, Windows/Linux release, hosted
CI, or owner T-250 visual approval. None of those gates was changed.
