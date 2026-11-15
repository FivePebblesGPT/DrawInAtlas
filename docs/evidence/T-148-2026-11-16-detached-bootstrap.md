# T-148 checkpoint — fail-closed detached native history bootstrap

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` · **Ticket:** T-148 **In Progress** · **GitHub baseline:** `a83e50550bb0c114a41b5c4af25fe2a2061bb1aa` (18 local sprint commits before this checkpoint). T-149 remains Blocked; T-095 remains owner-gated.

## Defect and change

`DrawingDocument._replay_native_tile_delta` previously replayed a detached `DrawingDelta` directly into GDScript's source projection if the document's native tile store was missing or had a different revision. This advanced the document but left any Rust store uninitialized or stale until a later checked source rebase. Its in-sync replay path, implemented earlier, already used Rust atomically.

After all lazy providers have returned and the document has revalidated revision, editable layer, source object identities, full expected RGBA8 bytes and caller-owned delta snapshots, the replay path now **always** requests native acceptance. If the attached store is absent or **behind** the current document revision, it creates a provisional `DrawingNativeTiles` configured with the current stride and revision, imports only the checked 1–128 source tile bytes and invokes `replay_detached_history` with the expected/replacement RGBA8 batch. On native rejection the provisional store is discarded; neither the existing Rust attachment, Godot source, history cursor nor revision is advanced. Only a successful native `r → r+1` transaction replaces the attached store, clears obsolete source identities and installs the already detached display/save projection (no further lazy callbacks). Untouched layers must still be explicitly authorized on their next native gesture. Empty tile source bytes mean authorized blank RGBA8; signed coordinates and hidden RGB are retained.

**Fail-closed refinement:** When Rust's attached revision is **ahead** of the Godot document, replacement would discard more recent native authority. The replay rejects `STALE_REVISION` instead, without changing either store. Matching in-sync stores still use the strict token/payload replay or native detached replay. Missing GDExtension/ABI, source import failure and native transaction refusal also fail closed. There is **no native-free history fallback**.

## Tested behavior

The new `tests/t148_detached_native_bootstrap.gd` exercises real compiled Rust/Godot 4.8 beta 3 code in **34 passing assertions**:

- Native Brush writes signed tiles and transparent hidden RGB; a detached Undo without the store rehydrates exact source and shared revision, then Redo and another Brush reuse the recovered store and Undo/Redo remain valid.
- An older attached store remains unmodified when reauthorizing an externally advanced document; subsequent Redo and Brush use the new owner.
- A Rust store ahead of the document fails closed, then replays successfully once document revision catches up.
- A mismatched source tile fails preflight, changes no attachment/revision/pixels and can be corrected and retried.
- A syntactically valid no-op replacement fails **inside Rust**, after provisional imports, and still leaves the document and attached-store pointer untouched; real history can replay afterward.

**Negative control:** Running the same test against `HEAD:addons/drawing/document.gd` (the previous Godot-only fallback implementation) exits nonzero with **19 failing assertions** (`T148_BOOTSTRAP_RESULT checks=34 failures=19`). Restoring the corrected implementation produces `T148_BOOTSTRAP_PASSED checks=34 failures=0`.

| Process / witness | Verified result |
| --- | ---: |
| Rust `cargo test --offline --locked --lib`, `cargo fmt --all --check`, strict `cargo clippy --offline --locked --all-targets -- -D warnings` | **25 tests passed; fmt/Clippy passed** |
| New detached native bootstrap (root project) | **34 checks, 0 failures** |
| Prior in-sync detached replay; strict history payload; reentrant history replay | **21 / 20 / 25 checks** |
| Atlas global native history; Object native Save/Save As | **43 / 38 checks** |
| Native store bridge; document tile publication; mixed raster adoption; persistent document; metadata revisions | **312 / 55 / 28 / 44 / 61 checks** |
| Real graphical Canvas (X11, software GL) | **46 checks, zero pixel-stream calls** |
| Real 96px NativeHard 512² full-canvas witness | Passed; **688.715ms** input-to-settled-postdraw |
| Real 96px Hokusai 512² full-canvas witness | Passed; **577.814ms**, 262,144/262,144 covered, zero transparent holes |
| Ticket/Kanban validator | **152 tickets valid** |

Every successful Godot process exited code 0 and emitted its expected explicit success marker. Rust/Godot tests used the pinned offline bundle. The two 96px software-rendered single runs do **not** meet the proposed 100ms target and are not physical input-to-photon measurements. No responsiveness improvement is claimed.

## Reproduce

```bash
cd /mnt/data/DrawInAtlas.sprint_2026-11-15
source /mnt/data/dev-bundle/setup-rust-env.sh
(cd native/drawing_brush && cargo test --offline --locked --lib && cargo fmt --all --check && \
  cargo clippy --offline --locked --all-targets -- -D warnings)
GODOT_SILENCE_ROOT_WARNING=1 /mnt/data/dev-bundle/run-godot-headless.sh --path . \
  --script res://tests/t148_detached_native_bootstrap.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-148-2026-11-16-detached-bootstrap-raw && sha256sum -c SHA256SUMS)
```

The [raw process logs and checksum manifest](T-148-2026-11-16-detached-bootstrap-raw/SHA256SUMS) include the **expected-failure negative control**, Rust fmt/Clippy, earlier native regressions, and X11 tests. Log absence or a test failure must not be inferred as a successful run; the negative control is labeled explicitly.

**Remaining T-148 limits:** Host/Godot retains detached history event snapshots and non-native raster producers; this recovery imports only the event's touched tiles, not an entire persisted document. Universal native authority and the T-149 dependency remain open. T-095 manual physical UX acceptance remains with the owner.
