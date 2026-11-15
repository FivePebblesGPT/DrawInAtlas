# T-148 checkpoint — Object Editor native Brush source lifecycle

**Date:** 2026-11-15 · **Branch:** `sprint/2026-11-15` · **Status:** T-148 **In Progress**. This test-only checkpoint builds on 14 local sprint commits after GitHub's verified `a83e50550bb0c114a41b5c4af25fe2a2061bb1aa` baseline.

## Scope and observed result

New `tests/t148_object_native_source.gd` uses the **real compiled** `DrawingNativeBrush` and `DrawingNativeTiles`, not a native substitute or per-pixel painting helper. It exercises the production `AtlasObjectEditorBridge`, `DrawingObjectEditorSession`, `AtlasObjectLibrary`, `DrawingFileIO`, `DrawingObjectEditorFile`, `AtlasEditHistory` and renderer from one source through an actual Object Editor draft, immutable Save and Save As, registry reload and portable export.

The **38-check fixture passes** on pinned Godot 4.8 beta 3. It verifies:

- 64px packed RGBA8 storage with negative tile coordinates and unmodified transparent hidden RGB; an actual NativeHard gesture creates Rust history, Undo restores original bytes, Redo restores the painted bytes with the same shared revision.
- A private edited Object draft stays invisible to *both* existing placements before publication. Save produces immutable source revision 2, resets the private draft's savepoint, and refreshes both placements; the published bytes are exact after reopening a new draft.
- Editing after Save creates a fresh native transaction. Save As produces a separately identified variant and fresh layer IDs, then rebinds only the selected instance. Atlas global Undo/Redo changes that **binding** without rewriting either published source. Reopening the Object library from disk preserves the original and variant's distinct bytes, versions and identities.
- A stale portable export revision cannot publish any file. A valid `.drawing` Object export preserves its label/version and byte-exact native-authored signed tiles; the exported source can perform and Undo a fresh native gesture.
- A disk-reloaded variant can perform and Undo a new native gesture after source reauthorization. If another draft publishes a newer immutable revision, Save on an older native-edited private tab fails with `STALE_SOURCE`, does not mutate its RGBA8 data and retains its local native Undo/Redo.

Save/Save As intentionally **detach** active Rust history when constructing immutable document snapshots; the next edit reauthorizes the saved source through a new native store. The separate Atlas-owned history command remains tested by `tests/t148_atlas_native_tile_history.gd`. This evidence demonstrates correct integration for the exercised Object paths, **not serializable Rust tokens** or universal native ownership of all raster producers.

## Neighboring verification

Godot native extension: pinned bundle 8, built Rust binary. Software-rendered / headless process exit status and unique success markers were checked. Original smoke's shutdown warnings are preserved verbatim; they are not reported as clean shutdown diagnostics.

| Witness | Result |
| --- | --- |
| New native Object Editor Save/Save As and portable source | **38 checks, 0 failures** |
| Atlas real-native global history and campaign Save/Open | **43 checks, 0 failures** |
| Existing Object Editor / Object asset tests | **45 / 95 checks, 0 failures** (Object Editor emits shutdown leak warnings) |
| Native structural / persistent document revisions | **61 / 44 checks, 0 failures** |
| Native external edit / document tile publication | **28 / 55 checks, 0 failures** |
| Offline Rust tests, fmt, strict Clippy | **23 passed, passed, passed** |
| 512²/96px NativeHard and Hokusai X11 witnesses | **Both source oracles passed** |
| Ticket/board validator | **152 tickets valid** |

The 96px software X11 input-to-settled postdraw single-run numbers were **1,322.948ms NativeHard** and **638.714ms Hokusai**. Both exceed the proposed 100ms threshold. They are not physical input-to-photon measurements and were not designed to compare Object Save latency.

The complete process logs and SHA-256 manifest are in [raw evidence](T-148-2026-11-15-object-native-raw/SHA256SUMS). An initial test-only assertion incorrectly reused the original layer ID across Save As; the fix follows the documented fresh-identity contract and the final 38-check test passes. No product implementation change was needed for the exercised Object source path.

### Reproduction

```bash
cd /mnt/data/DrawInAtlas.sprint_2026-11-15
GODOT_SILENCE_ROOT_WARNING=1 /mnt/data/dev-bundle/Godot_v4.8-beta3_linux.x86_64 \
  --headless --audio-driver Dummy --path . --script res://tests/t148_object_native_source.gd
source /mnt/data/dev-bundle/setup-rust-env.sh
(cd native/drawing_brush && cargo test --offline --locked --lib && \
 cargo fmt --all --check && cargo clippy --offline --locked --all-targets -- -D warnings)
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-148-2026-11-15-object-native-raw && sha256sum -c SHA256SUMS)
```

## Remaining acceptance

T-148 stays **In Progress**. Native raster source bytes and bounded history are not universally owned across all raster producers; older/evicted Atlas history may replay detached Godot snapshots rather than a live Rust token stack. Full revision-authority and per-tile lifecycle/trace acceptance remains. T-149 stays Blocked; T-095's physical owner-review gate remains unchanged.
