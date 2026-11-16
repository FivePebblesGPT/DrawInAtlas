# T-148 checkpoint — native tile deltas in Atlas global history

**Date:** 2026-11-15 · **Branch:** `sprint/2026-11-15` · **Ticket:** T-148 **In Progress**. The verified GitHub branch tip before this work was `a83e50550bb0c114a41b5c4af25fe2a2061bb1aa`; this checkpoint builds on the 13 earlier local sprint commits. T-149 remains Blocked; T-095's manual/physical acceptance gate is unchanged.

## Defect and fix

A production `DrawingEditSession` native Brush/Eraser publishes an already-committed `DrawingDelta` containing **full packed straight-RGBA8 tile before/after snapshots**, a signed storage tile key, tile stride and the persistent Rust `native_history_token`. When Atlas owns the document timeline (`external_history=true`), `AtlasEditHistory.commit_drawing()` wraps this delta in `AtlasDrawingEdit`. Previously its constructor built `DrawingDelta.new(change.layer_id, change.before, change.after)`, discarding **all native tile buffers, stride and token**. For native Brush, the per-pixel maps were empty: global Undo had no tile data and could not restore the painted source. Existing Atlas history smoke covered only per-pixel `apply_region` commits and missed this failure.

`DrawingDelta.detached_copy()` now copies **both** typed representations: the legacy maps plus the full tile stride, token and duplicated RGBA8 packed buffers. `AtlasDrawingEdit` retains this complete detached copy. No additional history is installed in the Drawing document; the Atlas command still owns one chronological entry, and the Rust history token is replayed when available at the top of its bounded history. The before/after tile snapshots are essential for safe historical/evicted-token fallback; the caller's mutable commit result does not alias the command. This is **not** a Rust-owned universal history implementation: detached fallback still reconstructs the GDScript projection, and the next native gesture reauthorizes it through a checked rebase.

## Real-native and Atlas persistence witness

New root Godot test `tests/t148_atlas_native_tile_history.gd` uses the compiled extension, an Atlas campaign/registry D1 Drawing detail, two actual NativeHard strokes on separate signed 64px storage tiles, and a genuine `AtlasGridEdit` inserted between the strokes. All **43 checks** pass:

- The Atlas command retains the exact native tile snapshot, signed tile ID, stride, and opaque history token with **empty** legacy per-pixel delta maps; mutating the original commit result does not alter its saved command.
- Atlas global Undo/Redo traverses Native Brush → Atlas grid → Native Brush in correct order with byte-identical hidden RGB and a matching native revision and history-token stack. The Drawing local history remains empty.
- Silent source substitution/tampering rejects Undo without consuming the Atlas command cursor or Rust history; repairing the source permits replay.
- A **real Atlas campaign generation** (`AtlasCampaignBundle.save` / `load`) lazily reopens the native-authored D1 Drawing document by stable ID with exact signed RGBA8 source tiles. Independent `.drawing` Save/Open, registry index reconstruction, and a fresh native Brush gesture on the reloaded document also pass.
- Simulated native-store detachment falls back to the fully detached RGBA8 snapshots for older Atlas commands. A subsequent live native gesture starts a checked fresh store and can be undone/redone alongside the older detached command without corrupting source bytes.

**Negative control:** running the new witness against the pre-fix `AtlasDrawingEdit` constructor rejected its native-delta assertion and raised a missing tile-key access error, confirming that the test detects the original defect. This negative process is deliberately not counted among successful logs.

## Verified regression matrix

Pinned bundle 8 Godot `4.8.beta3.official.c51ff06e8`, compiled real `DrawingNativeBrush` / `DrawingNativeTiles`, offline Rust 1.99.1. Headless and X11 tests have independent exit-code and success-marker checks. All passing logs are stored with their SHA-256 manifest under [raw evidence](T-148-2026-11-15-atlas-native-raw/SHA256SUMS).

| Witness | Result |
| --- | --- |
| New native Atlas history + campaign generation + detached fallback | **43 checks, 0 failures** |
| Existing Atlas history / editor history | **101 / 16 checks, 0 failures** |
| World mapping / Drawing composition | **125 / 89 checks, 0 failures** |
| Campaign generation / Object assets | **86 / 95 checks, 0 failures** |
| Persistent Drawing native store / mixed external raster edits | **44 / 28 checks, 0 failures** |
| Rust tile bridge / document bulk tile publication | **312 / 55 checks, 0 failures** |
| Graphical native Canvas tile cutover | **46 checks, 0 failures**, `tile_pixel_stream_calls=0` |
| 512²/96px NativeHard / Hokusai graphical witnesses | **Both passed** strict source checks |
| Rust offline unit tests / rustfmt / strict Clippy | **23 passed / pass / pass** |
| Ticket-board validator | **152 tickets valid**; manual gates unchanged |

Latest **single-run software-rendered** 96px times: NativeHard **676.271ms** and Hokusai **556.832ms** for input-to-settled postdraw. Both are above the proposed 100ms target. These are not comparable physical input-to-photon measurements and are **not** a performance improvement claim for the Atlas history change.

### Reproduction

```bash
cd /mnt/data/DrawInAtlas.sprint_2026-11-15
GODOT_SILENCE_ROOT_WARNING=1 /mnt/data/dev-bundle/Godot_v4.8-beta3_linux.x86_64 \
  --headless --audio-driver Dummy --path . \
  --script res://tests/t148_atlas_native_tile_history.gd
python3 tools/build_drawing_app.py --in-place
GODOT_SILENCE_ROOT_WARNING=1 /mnt/data/dev-bundle/Godot_v4.8-beta3_linux.x86_64 \
  --headless --audio-driver Dummy --path drawing \
  --script res://tests/t148_persistent_native_document.gd
source /mnt/data/dev-bundle/setup-rust-env.sh
(cd native/drawing_brush && cargo test --offline --locked --lib && \
  cargo fmt --all --check && cargo clippy --offline --locked --all-targets -- -D warnings)
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-148-2026-11-15-atlas-native-raw && sha256sum -c SHA256SUMS)
```

## Remaining T-148 acceptance

The Atlas command now faithfully carries native history and the integrated Atlas **campaign-generation raster source** roundtrip is witnessed. Native history itself is still **not serialized**; eviction/detachment falls back to Godot's tile snapshots, and unrelated raster producers and previously native-owned text conversion can still trigger a rebase. The new Atlas source test does not validate **Object editing against the same active native store**; the Object smoke is a separate regression. These remain T-148 blockers to universal native source/history authority and integrated Atlas/Object acceptance. Do not unblock T-149 or close T-148 based on this checkpoint.
