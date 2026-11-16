# T-160 — native-attached direct raster publication bounds

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` · **Ticket:** [T-160](../Tickets/T-160.md), Done locally. Parent [T-148](../Tickets/T-148.md) stays In Progress; T-149 stays Blocked. Godot: bundled 4.8 beta3; Rust: pinned offline Hokusai GDExtension. All results below are local software tests, not hosted CI or T-095 hardware acceptance.

## Failure and implementation

The T-158/T-159 safe signed display/manifest limits already bound native tile publication and detached history, but the **older direct publication** entry points still constructed or installed source tiles from unprojectable signed coordinates after a native Rust owner had attached to the document. `record_history=false` made the divergence especially visible: Godot accepted an out-of-projection tile and advanced its revision/dirty save state, while the persistent Rust tile store and Undo token remained at their old revision. The generic `_publish_edit` path also parsed invalid integer strings before checking they were valid signed decimals.

`_publish_tile_edit` now validates canonical signed tile IDs and, **when a native tile store is attached**, both axes against inclusive `±floor(2^52 / stride)` **before** multiplying by stride, calling a lazy source, or detaching a tile. `_publish_edit` checks valid canonical integer strings, and under the same native-attached condition rejects global pixel coordinates outside inclusive `±2^52` before any source read or staging. The new checks use the sign-safe `SignedTiles` helpers from T-158/T-159; no `abs(INT64_MIN)` call is introduced. This is deliberately a **native-attached** guard: previously supported pure non-native 64-bit direct-session range remains intact until the T-150 Legacy retirement, which is still a separate blocked ticket.

## Fail-first and positive witness

The same `drawing/tests/t160_direct_raster_publish_bounds.gd` was staged with the **original HEAD** `document.gd` and the patched version, with successful Godot editor imports for each. On original source it exited **1** and reported `T160_DIRECT_BOUNDS_RESULT checks=39 failures=31`; failure included revision/dirty writes from invalid tile and global-pixel coordinates, no independent Rust revision advancement, and the skip of downstream valid endpoint tests once corruption was detected. With the fix restored it exited **0** with `T160_DIRECT_BOUNDS_PASSED checks=46 failures=0`.

The fixture begins with a real Hokusai Hard Round gesture and retained Rust history token; it tests tile and global-pixel values on both axes immediately outside the safe bound and at signed 64-bit extrema, plus malformed and noncanonical decimal keys. It asserts no dirty/revision/history/source changes for each failed edit. It then publishes a **valid inclusive positive pixel endpoint** through `_publish_edit` and **valid inclusive negative tile endpoint** through `_publish_tile_edit`; native adoption returns Undo tokens, hidden RGB survives in alpha-zero pixels, paired Undo/Redo restore both sources and original Brush bytes, and `.drawing` Save/Open is byte-accurate. Finally a detached old-style non-native document successfully edits at `±9007199254740993` and replays its own Undo/Redo. No owner review or 100ms latency claim is inferred.

An earlier overbroad unconditional projection guard passed the new native fixture but failed the three **historical non-native** root tile-cache smoke tests, which intentionally use coordinates beyond `2^52`. Its raw failing runner output is retained under `diagnostics/overbroad-guard-matrix.log`. Narrowing to native-attached documents restored all three unchanged historical tests without weakening the new native fail-closed requirements.

## Final verification

| Check | Observed result |
| --- | --- |
| New real-native T-160 regression | **46/46**, exit 0, explicit success marker |
| Pre-fix control with final fixture | **31/39 failures**, exit 1 (expected) |
| Rust unit tests | **23/23**, exit 0 |
| rustfmt / strict Clippy / offline Rust release build | Passed; exit 0 |
| T-154–T-159 neighboring fixtures, native Brush integration, tile contract, revision/history | Passed; tile contract **312/312** |
| Three historical root signed-64-bit cache fixtures | **30/30**, **31/31**, **30/30** (all unchanged) |
| Atlas/Object/detached replay/text neighbors | Passed |
| Graphical X11 Canvas | **46/46**, zero per-pixel tile FFI calls |
| Graphical 96px Hokusai 512² fill | **262,144/262,144** covered; one software-X11 run **319.263 ms** total p95; `target_met=false` |
| Ticket validator and CI YAML | **160** valid tickets; workflow parses |

**32/32 recorded final invocations** have exit code 0 and explicit success markers for model tests (or tool-specific success for compile/import/stage steps); diagnostic failures are retained separately. No hosted CI pass or reference-device input-to-photon result is claimed.

## Reproduction

```bash
python3 tools/build_drawing_app.py --in-place
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --editor --import --quit --path drawing
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --audio-driver Dummy --path drawing \
  --script res://tests/t160_direct_raster_publish_bounds.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-160-2026-11-16-direct-publish-bounds-raw && sha256sum -c SHA256SUMS)
```

[Final 32-invocation table](T-160-2026-11-16-direct-publish-bounds-raw/summary.tsv) · [expected pre-fix negative control](T-160-2026-11-16-direct-publish-bounds-raw/diagnostics/pre-fix-final-fixture.log) · [checksum manifest](T-160-2026-11-16-direct-publish-bounds-raw/SHA256SUMS).
