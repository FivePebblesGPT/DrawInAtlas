# T-296 — Native signed Delete preflight

**Checkout:** `sprint/2026-11-23-godot-beta4`, Godot
`4.8.beta4.official.b070e63b1`, with `DrawingNativeTiles` loaded from
Rust. Verified remote `main` SHA:
`bbae76c33a6066582b2cd89e07cc3246fef942ce`.

## Reproduction and correction

For each X+/X−/Y+/Y− axis, the fixture registers a real lazy 16px source
at the last legal ±2⁵² document pixel and begins a signed native edit.
A two-pixel Delete includes the adjacent unpublishable pixel. On the original
`clear_rect()` implementation, these requests incorrectly succeeded and could
invoke the lazy source, stage a dense clear, and erase visible content.
The mixed-gesture case also flattened a valid tile-local deferred Brush.
The **unchanged implementation** failed **15/50** checks:
[fail-first native log](T-296-2026-11-23-clear-native-projection/fail-first.log).

The change reuses `_bulk_area_in_native_projection()` (already shared by
rectangle, byte-region and polygon publication) after `clear_rect()`'s
existing signed local/public-anchor checks but **before** any Hokusai/Brush
materialization, lazy read or dense/sparse clear mutation. A non-native
configuration keeps its historical wider coordinate behavior, just as the
other bulk APIs do.

The corrected real-Rust witness passes **50/50**. Invalid Deletes return
`COORD_RANGE`, read zero lazy chunks and leave previews and revisions intact.
Valid one-pixel boundary retries commit a clear, restore zero-alpha hidden RGB
on Undo, and clear again on Redo. A rejected Delete following an accepted
deferred Brush leaves that Brush untouched; its commit/Undo/Redo still matches
exact pixels:
[native-green log](T-296-2026-11-23-clear-native-projection/native-green.log).

## Neighboring regressions

| Native Godot beta4 test | Result |
| --- | --- |
| T-253 Atlas dense Delete | Passed |
| T-221 Atlas selection Delete | Passed |
| T-290 bulk edit preflight | 28/28 |
| T-294 native bulk projection | 71/71 |
| T-295 native Brush projection | 50/50 |
| T-293 native fill projection | 41/41 |
| T-068 lazy flood-fill tile cache | 39/39 |
| T-068 verified flood-fill staging | 36/36 |

All eight real native tests exited successfully with expected success markers;
the six numbered tests contributed **265/265 checks**. Their logs are in the
[evidence directory](T-296-2026-11-23-clear-native-projection/). Fourteen
focused T-290–T-296 Python CI contracts pass; the existing fast workflow still
contains 46 checks. Ticket-store validation passes for 296 tickets.

## Reproduce

```bash
G=/mnt/data/unpacked/drawing-toolchain-linux-x86_64/bin/godot
GODOT_SILENCE_ROOT_WARNING=1 "$G" --headless --path . \
  --script res://tests/t296_clear_native_projection.gd
python3 tools/check_godot_model_log.py \
  docs/evidence/T-296-2026-11-23-clear-native-projection/native-green.log \
  --marker T296_CLEAR_PROJECTION_PASSED
python3 -m unittest discover -s tests -p 'test_t29?_*.py' -v
python3 tools/validate_ticket_store.py
```

**Limits:** This verifies a narrow Delete safety boundary, not performance
acceptance, complete Rust ownership, hosted beta4 CI, Windows/Linux physical
acceptance, or T-250 owner UI approval. T-068 and T-148 remain In Progress.
