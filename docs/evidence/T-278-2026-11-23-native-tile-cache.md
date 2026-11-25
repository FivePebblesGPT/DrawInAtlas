# T-278 — Native source-tile cache CI contract (2026-11-23)

## Reproduction and cause

- Base checkout: `a217a969` on `sprint/2026-11-23-godot-beta4`;
  latest verified remote `main`: `bbae76c33a6066582b2cd89e07cc3246fef942ce`.
- Engine: bundled `Godot 4.8.beta4.official.b070e63b1`, required
  `DrawingNativeTiles` loaded (`godot-rust` API 4.7).
- Unmodified `tests/drawing_edit_tile_cache_smoke.gd` produces
  `T068_TILE_CACHE_FAILED checks=31 failures=3` (exit 1). See
  [fail-first](T-278-2026-11-23-native-tile-cache-raw/fail-first.log).
- Reason 1: native tile commits publish a real source revision/history token
  without populating the retired per-pixel `DrawingDelta.after` map. The
  fixture compared `delta.after.size()` to the staged touched-pixel count,
  even when published raster pixels were correct.
- Reason 2: the historical `+9007199254740993 / -9007199254740993`
  document-space brush anchor is allowed by the broad public gesture
  interface, but cannot be committed by native tile publication (signed
  display/storage projection is bounded to approximately ±2^52 pixels).
  The fixture had incorrectly required successful publication and readback.

## Repair and independent observable checks

1. Snapshot **all 256 straight-RGBA8 pixels** in a 16×16 readback region
   spanning the four negative/positive source tiles. Read each pixel through
   public `DrawingDocument.read_pixel`, independently of the edit's native
   history descriptor. Fail if any read fails.
2. Keep the exact same 8px overlapping native dab, source cache cardinality
   and repeated-path once-per-pixel check. After commit, compare the number
   of actually changed canonical RGBA8 pixels to the staged touched-pixel
   count, assert a one-step revision increment, and compare the **entire**
   original/published snapshots after Undo and Redo (including transparent
   RGB, not merely displayed alpha).
3. Explicitly prove `>2^53` gesture construction may succeed but the
   resulting **publication** is rejected without a revision or pixel change.
   Then commit at the valid signed `±1125899906842625` anchor with nonzero
   low bits and verify exact source pixels after native Undo/Redo.
4. Retain existing lazy-tile digest, transient source failure/retry, cache
   hit, no-op, cancellation and revision-conflict checks. No application or
   native production implementation changed.

## Commands and results

From repo root, with `GODOT` set to the executable bundled in the supplied
`drawing-toolchain-linux-x86_64` directory:

```bash
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path . --script res://tests/drawing_edit_tile_cache_smoke.gd
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path drawing --script res://tests/t158_signed_lazy_tile_bounds.gd
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path drawing --script res://tests/t159_signed_replay_publication_bounds.gd
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path drawing --script res://tests/t160_direct_raster_publish_bounds.gd
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path . --script res://tests/campaign_bundle_smoke.gd
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path . --script res://tests/drawing_t068_skia_brush_oracle.gd -- /tmp/t278-oracle.json
GODOT_SILENCE_ROOT_WARNING=1 T068_GODOT="$GODOT" python3 -m unittest discover -s tests -p test_t068_skia_brush.py -v
python3 -m unittest discover -s tests -p test_t106_oracle_engine_compat.py -v
python3 tools/validate_ticket_store.py
```

| Witness | Outcome |
| --- | --- |
| Existing cache fixture before repair | **31 checks / 3 failures**, exit 1 |
| Repaired native tile-cache fixture | **38/38**, exit 0 |
| T-158 native lazy signed tiles | **24/24**, exit 0 |
| T-159 signed replay | **39/39**, exit 0 |
| T-160 direct raster publication | **46/46**, exit 0 |
| T-066 campaign storage | **97/97**, exit 0 |
| T-068 live Skia pinned oracle | **16/16 cases**, exit 0 |
| T-068 Skia Python contracts (live Godot) | **9 tests, 8 passed; 1 optional Skia-wheel skip** |
| T-106 compatibility | **2/2**, exit 0 |
| Ticket store | Run after ticket/index sync; see final validation below |

[Raw outputs](T-278-2026-11-23-native-tile-cache-raw/) contain the
fail-first, repaired cache, neighboring native and oracle checks. The first
attempts to launch T-160 with a wrong script filename and Skia without its
required output argument were command-invocation errors, not test failures;
the listed corrected commands above passed.

### Scope and remaining work

- The other T-068 required-native `drawing_dab_geometry_smoke.gd` and
  `drawing_axis_sweep_smoke.gd` are **still red** per the T-277 evidence.
  This ticket does not reinterpret their legacy pixel-delta assumptions or
  claim the full T-068 hosted CI group is now passing.
- No production changes, screenshot/UI claims, owner T-250 approval,
  physical Windows/Linux release testing or completed T-148 integration.
