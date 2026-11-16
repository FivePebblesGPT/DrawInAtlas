# T-176 — Checked native semantic structural Undo/Redo

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` ·
[T-176](../Tickets/T-176.md) Done locally. Parent T-148 remains In Progress,
T-149 Blocked and T-095 owner/hardware review unchanged. No hosted CI pass
or physical input-to-photon result is claimed.

## Defect and fix

Public semantic layer commands were made fail-closed in T-173, but local
`_replay_structure()` still changed property fields, child order and semantic
node membership before calling `_advance_nonraster_revision(false)`. That
post-mutation bridge could detach a busy or native-ahead Rust store while
local Undo/Redo advanced. This left Godot history no longer synchronized with
canonical Rust tiles and existing Hokusai Undo tokens.

The semantic-only property/reorder/create/remove replay paths now validate
the history target and use `_advance_checked_layer_metadata(false)` **before**
publishing any Godot state. The optional argument preserves native Redo on
history playback; default `true` continues to invalidate branched Redo on
new metadata edits. Rejection returns `NATIVE_METADATA` or `STALE_REVISION`
without moving the local cursor, revision, node tree, dirty state, attached
native store or any Rust tile/history byte. Raster-bearing structural replay,
text conversion and host-owned detached history remain outside this ticket.

## Fail-first and independent positive control

`drawing/tests/t176_structural_history_native_fence.gd` exercises a native
Hokusai-painted 64px Ink tile while recording six separate local structural
operations: rename, visibility, lock, reorder, create semantic layer and
remove a nested semantic subtree. For each, it holds a Rust transaction and
checks rejected Undo, releases it and retries Undo, then repeats for Redo.
It compares full node metadata, parent membership, local history cursor,
revision, dirty/untracked flags, native revision and Undo/Redo stack counts,
and full canonical RGBA8. An initially transparent pixel at (3,4) retains
hidden `11 22 33 00` across every replay.

The same fixture checks a native-ahead revision, native-absent historical
Undo/Redo, a later Hokusai stroke and its exact Undo/Redo, and a real
`.drawing` Save/Open round trip.

- **Pre-fix control:** `drawing/addons/drawing/document.gd` temporarily
  replaced with the unmodified HEAD source, using the same test fixture and
  binary. Process exit **1**; `T176_STRUCTURAL_RESULT checks=81 failures=25`.
  The control stops some scenarios early after a broken Undo, so the count of
  executed assertions is lower than in the fixed test; this is not a
  121-assertion negative run.
- **Fixed:** patched document restored byte-for-byte; process exit **0**;
  `T176_STRUCTURAL_RESULT checks=121 failures=0` and
  `T176_STRUCTURAL_PASSED`.

## Validation matrix

| Checks | Result |
| --- | --- |
| T-176 real-native structural history | **121/121 passed** |
| Pre-fix control | **25/81 failed as expected** |
| Rust unit tests | **25/25 passed** (offline locked) |
| rustfmt, strict Clippy (`-D warnings`), release build | Passed |
| T-173/174/175, T-148 structural/metadata/history | Passed |
| T-154/156/162/165/168/169 and native tile contract | Passed; **312/312** tile checks |
| Atlas transfers/history, Object Editor, root Drawing history/text | Passed |
| Graphical Canvas native tile cutover | **46/46**, exit 0 |
| 96px/100-event Hokusai software-X11 | **262,144/262,144** pixels, exit 0 |
| Ticket validator / workflow YAML | 176 valid tickets / parsed |

All **31 final suite invocations** in
[summary.tsv](T-176-2026-11-16-semantic-history-raw/summary.tsv)
exited 0 with verified markers where relevant. The one software-X11 96px
trial measured **485.179 ms** down-to-postdraw, **141.272 ms** staging CPU.
It does **not** satisfy the T-095 physical-device 100ms gate or owner review.
A first attempt at two text-dependent tests could not load the Lato font;
a real editor `--import` succeeded and both tests then passed. An initial
strict Clippy invocation omitted the pinned vendored Cargo workspace and
failed dependency resolution; the correctly configured offline invocation
passed. Those attempts are setup errors, not regression failures; only
successful final runs appear in `summary.tsv`.

Raw logs, the negative control and the verified SHA-256 manifest are in
[T-176 raw evidence](T-176-2026-11-16-semantic-history-raw/).

## Reproduction

```sh
source /mnt/data/archive_unpacked/godot_bundle/setup-rust-env.sh
export CARGO_TARGET_DIR=/mnt/data/work/cargo-target
# Run Cargo from the bundle's vendored workspace or pass its explicit config.
cd /mnt/data/archive_unpacked/godot_bundle/rust-hokusai
cargo clippy --offline --locked --manifest-path \
  /mnt/data/work/DrawInAtlas/native/drawing_brush/Cargo.toml \
  --all-targets -- -D warnings
cd /mnt/data/work/DrawInAtlas
python3 tools/build_drawing_app.py --in-place
GODOT=/mnt/data/archive_unpacked/godot_bundle/Godot_v4.8-beta3_linux.x86_64
"$GODOT" --headless --editor --path drawing --import --quit
"$GODOT" --headless --audio-driver Dummy --path drawing \
  --script res://tests/t176_structural_history_native_fence.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-176-2026-11-16-semantic-history-raw && sha256sum -c SHA256SUMS)
```
