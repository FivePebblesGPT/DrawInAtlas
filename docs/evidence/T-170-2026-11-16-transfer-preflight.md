# T-170 — Check native retirement before cross-document raster move

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` ·
[T-170](../Tickets/T-170.md) completed locally. Parent T-148 remains In
Progress; T-149 is Blocked, and T-095 still needs owner/hardware acceptance.
No hosted CI or physical-device latency signoff is claimed.

## Defect and fix

The static `DrawingDocument.transfer_subtree(..., move=true)` and
`AtlasDrawingTransfer.apply()` both imported a detached subtree into the
**destination before** attempting source `remove_subtree`. With an active
source Rust transaction, stale revision or tampered alpha-zero RGB, the
source's checked retirement could reject the removal after the target had
already advanced. The standalone helper even returned the target's successful
import result without checking source deletion. Atlas attempted to compensate,
but that is a second fallible native structure operation, not a source-side
precondition.

The new `DrawingNativeTiles.can_retire_layers_revision(revision, layer_ids)`
is a **read-only** check sharing exact validation with the Rust
`retire_layers_revision` mutator: quiescent revision, no active edit, bounded
unique IDs and no parked layers. Its GDScript counterpart,
`DrawingDocument.preflight_unrecorded_subtree_removal(node_id)`, also checks
editable source tree, exact native revision, authorized tile-object identities
and full Rust/Godot RGBA8 parity, including hidden RGB beneath zero alpha.
Neither preflight resolves lazy providers or changes either document.

After a detached source export, both transfer APIs run that check **before**
publishing destination nodes. The static API also rechecks both revisions
after export and handles an unexpected late source removal error explicitly,
retaining the destination rollback as a last-resort safeguard. Atlas still
uses one host-owned command with Undo/Redo. A copy skips retirement preflight;
the source remains independently editable. This does not implement a general
two-phase transaction for arbitrarily reentrant code across two documents.

The earlier `t148_unrecorded_retire_native_revision.gd` test expected a
Godot-only fallback on native source tampering. That oracle contradicted the
already-completed T-168 removal fence; its two assertions now require atomic
rejection, byte restoration and preservation of unrelated Rust history.

## Fail-first and positive witness

`tests/t170_cross_document_move_preflight.gd` uses Godot 4.8 beta3, the
actual rebuilt Rust/Hokusai extension, native-painted source and destination
raster layers, and both the static and Atlas transfer APIs. It verifies:

- A held Rust source transaction refuses a move **without adding destination
  nodes or advancing either revision**, source bytes or either native timeline.
- Atlas rejects that same busy source with no command appended.
- A source mutated at alpha zero refuses import even though its Godot tile
  object is the same, and exact-byte restoration allows retry.
- A valid Atlas move retires its original native source, imports full detached
  RGBA8, retains unrelated source/destination bytes and native history, then
  survives global Undo and Redo at stable layer IDs.
- Native-source Copy succeeds while the source has a held transaction, because
  it does not retire that source; a later static Move succeeds after release.

**Patched:** process exit `0`, `T170_TRANSFER_RESULT checks=30 failures=0`,
`T170_TRANSFER_PASSED`.

**Fail-first:** with the prior `transfer_subtree` and
`AtlasDrawingTransfer.apply` caller bodies restored from the local base
commit (same fixture and new Rust binary), process exit `1`,
`T170_TRANSFER_RESULT checks=30 failures=9`. The original static function
reported success and mutated the destination while removal was refused;
Atlas's subsequent compensation did not preserve the original destination
revision and native history. The new read-only source preflight stayed in
place for the control so the fixture's direct API assertion remained valid.
The patched caller bodies were restored and retested afterward.

## Final local verification

| Check | Result |
| --- | --- |
| T-170 real-native cross-document witness | **30/30**, exit 0 |
| Pre-fix control (previous transfer callers) | **9/30 failed as expected**, exit 1 |
| Rust `cargo test --lib --offline --locked` | **25/25**, exit 0 |
| `cargo fmt --check`, strict Clippy and release build | Passed |
| Native tile, import, retirement, Hokusai and history regressions | Passed |
| Root Atlas history and Object Editor | Passed |
| Graphical Canvas tile cutover (software X11) | **46/46**, exit 0 |
| 96px Hard Round full-canvas witness (software X11) | **262,144/262,144 pixels covered**, exit 0 |
| Ticket validator and CI YAML parse | **170 tickets valid**, parsed |

All **22 final matrix invocations** recorded exit code 0 and the appropriate
success marker (or successful zero-output rustfmt). The initial discovery
matrix also identified a stale T-148 retirement fixture and missing Godot font
import; they were resolved before the final matrix, not counted as passes.

The single software-X11 96px witness reported **356.978 ms**
down-to-post-draw, **109.435 ms** native stage CPU and
`tile_pixel_stream_calls=0`. These are **not** a hardware input-to-photon
benchmark, a 100ms acceptance claim or owner signoff.

Raw logs: [T-170 raw evidence](T-170-2026-11-16-transfer-preflight-raw/),
including [`summary.tsv`](T-170-2026-11-16-transfer-preflight-raw/summary.tsv),
[`negative-control.log`](T-170-2026-11-16-transfer-preflight-raw/negative-control.log)
and verified [`SHA256SUMS`](T-170-2026-11-16-transfer-preflight-raw/SHA256SUMS).

## Reproduce

```sh
source /mnt/data/archive_unpacked/godot_bundle/setup-rust-env.sh
export CARGO_TARGET_DIR=/mnt/data/work/cargo-target
cargo test --manifest-path native/drawing_brush/Cargo.toml --offline --locked \
  --lib --config /mnt/data/work/t153-cargo-config.toml
cargo fmt --manifest-path native/drawing_brush/Cargo.toml --all --check
cargo clippy --manifest-path native/drawing_brush/Cargo.toml --offline --locked \
  --all-targets --config /mnt/data/work/t153-cargo-config.toml -- -D warnings
cargo build --manifest-path native/drawing_brush/Cargo.toml --offline --locked \
  --release --config /mnt/data/work/t153-cargo-config.toml
cp /mnt/data/work/cargo-target/release/libdrawing_brush.so addons/drawing/native/bin/
python3 tools/build_drawing_app.py --in-place
GODOT=/mnt/data/archive_unpacked/godot_bundle/Godot_v4.8-beta3_linux.x86_64
"$GODOT" --headless --editor --path . --import --quit
"$GODOT" --headless --audio-driver Dummy --path . \
  --script res://tests/t170_cross_document_move_preflight.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-170-2026-11-16-transfer-preflight-raw && sha256sum -c SHA256SUMS)
```

## Remaining work

T-170 closes the **ordinary native-source retirement rejection** window in
cross-document moves. It does not provide a distributed two-phase commit if
external callbacks can mutate either document between preflight and commit,
or complete the general host-owned detached history ownership gate. T-148
remains In Progress. T-149 and downstream Legacy removal remain blocked.
