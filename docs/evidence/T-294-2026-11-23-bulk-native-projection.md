# T-294 — Native bulk region/shape preflight

**Checkout:** `sprint/2026-11-23-godot-beta4`, with Godot
`4.8.beta4.official.b070e63b1` and loaded `DrawingNativeTiles` Rust extension.
Verified remote `main` baseline: `bbae76c33a6066582b2cd89e07cc3246fef942ce`.

## Reproduction and correction

For each of X+/X−/Y+/Y−, register a real lazy 16px source tile at the
last legal ±2⁵² global pixel, start a session at that signed anchor, and
request a **two-pixel** rectangle/byte-region/polygon that crosses into the
unpublishable adjacent pixel. The unmodified edit session stages pixels and
reads lazy sources before native publication rejects them. The original
witness reports **44 failures / 57 checks**:
[fail-first](T-294-2026-11-23-bulk-native-projection/fail-first.log).

The shared `_bulk_area_in_native_projection()` checks the inclusive global
first/last pixels against the canonical native projection *before* either
lazy resolution or deferred Brush/Hokusai materialization. This matches
`DrawingDocument._publish_edit()`'s native-publisher applicability and
retains wider historical signed coordinates without native publication.
The witness now covers four axes/signs and an additional deferred-Brush
transaction, passing **71/71**:
[native-green](T-294-2026-11-23-bulk-native-projection/native-green.log).

Two original T-068 witnesses asserted that invalid native bulk edits could
stage three pixels and would fail only on commit. Both passed on the untouched
T-293 checkout (retained baseline logs); after this safer early-fail contract
those specific expectations were updated. No pixel oracle, history or
performance assertions were removed. Eight affected Rust-backed neighbors
then passed **301/301**:

| Witness | Result |
| --- | ---: |
| T-290 bulk view preflight | 28/28 |
| T-291 selection-excluded fill | 33/33 |
| T-292 signed view frontier | 38/38 |
| T-293 global fill projection | 41/41 |
| T-068 fill frontier | 56/56 |
| T-068 lazy fill tile cache | 39/39 |
| T-068 verified mixed staging | 36/36 |
| T-068 native publication tile cache | 30/30 |

[Retained native logs](T-294-2026-11-23-bulk-native-projection/).

## Reproduce

```bash
G=/mnt/data/unpacked/drawing-toolchain-linux-x86_64/bin/godot
GODOT_SILENCE_ROOT_WARNING=1 "$G" --headless --path . \
  --script res://tests/t294_bulk_native_projection.gd
python3 tools/check_godot_model_log.py \
  docs/evidence/T-294-2026-11-23-bulk-native-projection/native-green.log \
  --marker T294_BULK_PROJECTION_PASSED
python3 -m unittest discover -s tests -p 'test_t29?_*.py' -v
python3 tools/validate_ticket_store.py
```

**Limitations:** Full hosted CI, physical-device latency, standalone export,
Windows testing and T-250 owner UI acceptance have **not** been completed
by this checkpoint. T-068 and T-148 remain In Progress.
