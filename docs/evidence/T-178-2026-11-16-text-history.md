# T-178 — Checked native semantic text-history Undo/Redo

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` ·
[T-178](../Tickets/T-178.md) Done locally. Parent T-148 remains In Progress;
T-149 remains Blocked; T-095 remains an independent owner/hardware gate.
No hosted CI green or physical input-to-photon latency is claimed.

## Defect and implementation

`DrawingDocument.commit_text()` already acquired a checked Rust metadata
revision (T-174), but its **local** `text_tree` history replay did not.
`_replay_text_tree()` mutated semantic text creation/deletion and edit states,
then used `_advance_nonraster_revision(false)`. With an active Rust transaction
or a native-ahead revision, this post-mutation helper detached the native
store while the Godot history cursor was advanced. Subsequent Hokusai Brush
edits could therefore lose canonical history authority.

The replay now validates its expected history node/parent and acquires
`_advance_checked_layer_metadata(false)` before touching semantic-only TEXT
nodes. A rejected busy/native-ahead metadata revision leaves the entire
Godot tree, document revision, history cursor, Rust tile bytes (including
hidden RGB), native Undo tokens, and attachment unchanged. An accepted
replay increments native and Godot revisions once, retaining Redo through
`discard_redo=false`. The TEXT↔RASTER path still uses T-154's separate
park/unpark bridge, and native-absent semantic text history stays functional.

## Fail-first and positive control

The **same** `drawing/tests/t178_text_history_native_fence.gd` executed with
a Godot resource import against the original `HEAD` version of
`addons/drawing/document.gd`, copied into the standalone addon temporarily.
It exited **1** with `T178_TEXT_HISTORY_RESULT checks=43 failures=21`.
Failures included accepted busy-native Undo, changed text membership/cursor,
detached Rust source, native-ahead replay and invalid downstream retries.
The patched document was restored before the final matrix; its identical
fixture exited **0**, `T178_TEXT_HISTORY_RESULT checks=43 failures=0` and
`T178_TEXT_HISTORY_PASSED`.

The fixture uses the bundled real Hokusai Hard Round and persistent Rust
`DrawingNativeTiles`, initially with a zero-alpha tile containing nonzero
RGB. It covers busy-native Undo and Redo of text edits and creation, retry
under the same Rust store, independent native-ahead rejection, native-absent
compatibility, later Hokusai Brush Undo/Redo and exact `.drawing` Save/Open.

## Test matrix

| Check | Result |
| --- | --- |
| T-178 real-native regression | **43/43 passed** |
| Identical pre-fix control | **21/43 failed as expected**, exit 1 |
| Offline Rust unit tests | **25/25 passed** |
| rustfmt check, strict Clippy `-D warnings`, offline release build | Passed |
| T-154/T-155 text-raster, T-174/T-175 semantics, T-176/T-177 structure | Passed |
| T-148 persistent store / 312-check tile contract / import / history | Passed |
| Root Drawing text/history, Atlas and Object integrations | Passed |
| Graphical native Canvas tile cutover | **46/46 passed**, software-X11 |
| Strict Hokusai 96px, 100-event, 512² witness | **262,144/262,144 pixels covered** |
| Ticket store / CI YAML | **178 tickets valid** / parsed |

The final corrected matrix contains **33 passing test/build/import invocations**,
with zero process errors and positive markers where applicable; see
[summary.tsv](T-178-2026-11-16-text-history-raw/summary.tsv). The first
matrix invocation of `t148_persistent_native_document.gd` returned **2/44
failures**, because its old fixture expected a lazy callback to lock a layer
during an active native transaction. T-173 already prohibits that lock.
The oracle was updated to require the callback's lock rejection followed by
a valid Brush commit with preserved native authority; the rerun passed
**44/44**. Both original and corrected logs are retained.

The single software-X11 benchmark measured **432.342 ms** down-to-postdraw
and **118.930 ms** native staging CPU. This is a software-only observation;
there is no T-095 hardware signoff or statistical reference-device p95.

Raw process output, strict benchmark JSON, the negative control and the
[SHA-256-verified evidence manifest](T-178-2026-11-16-text-history-raw/SHA256SUMS)
are preserved in
[T-178 raw evidence](T-178-2026-11-16-text-history-raw/).

## Reproduce

```sh
source /mnt/data/archive_unpacked/godot_bundle/setup-rust-env.sh
export CARGO_TARGET_DIR=/mnt/data/work/cargo-target
cd /mnt/data/archive_unpacked/godot_bundle/rust-hokusai
cargo test --offline --locked --manifest-path \
  /mnt/data/work/DrawInAtlas/native/drawing_brush/Cargo.toml
cargo clippy --offline --locked --manifest-path \
  /mnt/data/work/DrawInAtlas/native/drawing_brush/Cargo.toml \
  --all-targets -- -D warnings
cd /mnt/data/work/DrawInAtlas
python3 tools/build_drawing_app.py --in-place
GODOT=/mnt/data/archive_unpacked/godot_bundle/Godot_v4.8-beta3_linux.x86_64
"$GODOT" --headless --editor --path drawing --import --quit
"$GODOT" --headless --audio-driver Dummy --path drawing \
  --script res://tests/t178_text_history_native_fence.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-178-2026-11-16-text-history-raw && sha256sum -c SHA256SUMS)
```
