# T-159 — signed native publication/history projection guards

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` · **Ticket:** [T-159](../Tickets/T-159.md), Done locally. Parent [T-148](../Tickets/T-148.md) remains In Progress. All runtime results are on bundled Godot 4.8 beta3 with its pinned Hokusai/Rust extension; software X11/llvmpipe is not the owner hardware gate.

## Failure and fix

The current `SignedTiles.tile_coordinates_in_projection_range` already validates lazy/manifest source coordinates (T-158). Three downstream authority boundaries in `DrawingDocument` still used `abs(x) > limit` or `abs(y) > limit`:

1. `_publish_native_tile_edit`: native Hokusai tile preflight before document publication;
2. `_replay_native_tile_delta`: native/Atlas detached tile history, before Rust token consumption;
3. `_replay_pixel_delta_native`: historical per-pixel replay before grouping/importing into Rust.

On this Godot version, `abs(-9223372036854775808)` is again `-9223372036854775808`, so the positive-limit comparison is false; signed-minimum inputs could evade the intended early guard. Native publication and history could run later validation or projection work on an invalid coordinate. The two tile-based checks now reuse T-158's signed comparison at `±floor(2^52 / stride)`; the older pixel-map replay uses the newly shared signed pixel comparator at `±2^52`. No Rust ABI, rendering algorithm, persistence payload, valid signed tile range, or owner-review decision changes.

## Fail-first and repaired witness

The **same** `drawing/tests/t159_signed_replay_publication_bounds.gd` ran against a temporary stage of the pre-fix `document.gd` and `signed_tiles.gd`, with their original HEAD bytes. After a successful real native Hokusai stroke, the 39-check test failed **4/39** at the native publication and history replay bounds for `INT64_MIN` in X and Y; exit status **1**, with `T159_SIGNED_REPLAY_RESULT checks=39 failures=4`. It was then restaged with the fix and passed **39/39**, exit **0**, marker `T159_SIGNED_REPLAY_PASSED checks=39 failures=0`.

The test checks both axes at signed 64-bit minimum, maximum, and just outside the tile and pixel projection bounds; failures must return `COORD` *before* source resolution, replay or mutation. It also checks unchanged live Rust store identity/revision/history token and unchanged Hokusai Ink source bytes after each rejected operation. A final Undo/Redo roundtrip restores the identical signed-tile RGBA8 source. The pixel history pre-fix guard happened to reject some extrema downstream; the regression demands rejection at the specific checked boundary instead of accepting arbitrary downstream behavior.

## Final verification

| Test | Observed result |
| --- | --- |
| New signed history/publication regression | **39/39**, exit 0, explicit marker |
| Same fixture against previous source | **4/39 failures**, exit 1 (expected negative control) |
| Rust unit tests | **23/23**, exit 0 |
| rustfmt / strict Clippy / Rust release build | All exit 0 |
| Previously introduced T-154–T-158 checks and native tile contract | All exit 0; tile suite **312/312** |
| Root lazy publish/edit/fill and Atlas/Object/history neighbors | All exit 0 |
| Graphical Canvas X11 | **46/46**, zero tile pixel-stream FFI calls |
| 96px Hokusai software-X11 witness | **262,144/262,144** canvas pixels, full-canvas source and Undo/Redo witness; **339.909 ms** down-to-postdraw for one run, `target_met=false` |
| Ticket store and workflow YAML | 159 valid tickets, CI YAML parsed successfully |

**31/31 recorded final invocations** exited 0 and had no failure markers; the negative-control run is stored separately under `diagnostics/`. There is no remote hosted CI or reference-device input-to-photon acceptance claim. T-095 and other manual-review gates remain unchanged.

## Reproduce

```bash
python3 tools/build_drawing_app.py --in-place
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --editor --import --quit --path drawing
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path drawing \
  --script res://tests/t159_signed_replay_publication_bounds.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-159-2026-11-16-replay-bounds-raw && sha256sum -c SHA256SUMS)
```

[Raw final invocation table](T-159-2026-11-16-replay-bounds-raw/summary.tsv) · [negative control](T-159-2026-11-16-replay-bounds-raw/diagnostics/pre-fix-fail-first.log) · [checksummed logs](T-159-2026-11-16-replay-bounds-raw/SHA256SUMS).
