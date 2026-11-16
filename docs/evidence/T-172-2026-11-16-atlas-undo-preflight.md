# T-172 — Atomic rejection of Atlas transfer Undo when target Rust refuses retirement

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` ·
[T-172](../Tickets/T-172.md) completed locally. T-148 remains In Progress,
T-149 is Blocked, and the T-095 owner/physical-hardware gate remains open.
No hosted CI or physical-device acceptance is claimed.

## Defect and fix

`AtlasDrawingTransfer.revert()` restored the moved subtree in its source
**before** calling `target.remove_subtree(target_node_id)`. If the target had
an active Rust edit or a divergent native revision, Rust refused retirement
and Undo returned failure. The compensating source removal was another
fallible native transaction and could advance document/native revisions
without advancing the Atlas history cursor. A later retry then encountered
invalid host revision expectations.

Now the host calls the already-available, read-only
`target.preflight_unrecorded_subtree_removal(target_node_id)` before restoring
the source. This reuses T-170's native retirement eligibility checks and
T-168's attached canonical byte-identity checks, without creating a new
history token, resolving lazy providers, or mutating either document.
Copy Undo uses the same target validation, although Copy does not restore a
source. The existing source-side preflight on **apply** remains unchanged.

This closes the ordinary target-retirement rejection window; it does not
provide distributed two-phase commit under arbitrary reentrant callbacks.

## Fail-first control and positive regression

`tests/t172_atlas_transfer_undo_preflight.gd` runs against actual Godot 4.8
beta3 and the rebuilt Rust/Hokusai GDExtension. It covers:

- A native-painted group moving from Atlas-owned source to destination,
  retaining unrelated Rust tiles and history tokens in both documents.
- A held native edit on the **destination** during Atlas Move Undo: the
  failure leaves both trees, revisions, native source bytes and history
  counts unchanged, retaining the host cursor. Releasing the edit makes
  Undo and Redo succeed with the same identity and exact RGBA8 bytes.
- Atlas Copy Undo under a held target native edit, without altering the
  copied source; successful Copy Undo/Redo after the edit is discarded.
- An injected native-ahead destination revision on Move Undo: the host
  rejects without restoring source nodes or rebasing the newer Rust store.

**Patched:** exit `0`, `T172_UNDO_RESULT checks=30 failures=0`,
`T172_UNDO_PASSED`.

**Fail-first:** with the `AtlasDrawingTransfer.revert()` guard removed,
against the *same* fixture and native binary: exit `1`,
`T172_UNDO_RESULT checks=30 failures=4`. The old implementation modified
source/native revisions after rejected Undo and left subsequent retry
without valid revision continuity. The guard was restored and tested again.

## Final local matrix

| Verification | Result |
| --- | --- |
| T-172 native/Atlas transfer Undo fixture | **30/30**, exit 0 |
| Pre-fix control | **4/30 failed as expected**, exit 1 |
| Rust unit tests | **25/25**, exit 0 |
| rustfmt, strict Clippy, release rebuild | Passed |
| Root + Drawing import | Passed |
| T-170/T-171 transfer/export and T-148 native history tests | Passed |
| Atlas global history + Object Editor | Passed |
| T-154/T-156/T-162/T-165/T-168/T-169 native neighbors | Passed |
| Graphical Canvas tile cutover | **46/46**, exit 0 |
| Hokusai 96px/512×512 full-canvas software-X11 | **262,144/262,144 covered**, exit 0 |
| Ticket dependency validation and native CI YAML | **172 tickets valid**, parsed |

**All 24 final test/build/import invocations exited 0 and met the required
log markers.** One software-X11 96px trial reported 367.080 ms down-to-postdraw,
109.901 ms staging CPU, and zero tile per-pixel FFI stream calls. This is
not a hardware input-to-photon measurement or T-095 acceptance.

Raw logs: [T-172 raw evidence](T-172-2026-11-16-atlas-undo-preflight-raw/),
including [summary.tsv](T-172-2026-11-16-atlas-undo-preflight-raw/summary.tsv),
[negative-control.log](T-172-2026-11-16-atlas-undo-preflight-raw/negative-control.log),
and verified [SHA256SUMS](T-172-2026-11-16-atlas-undo-preflight-raw/SHA256SUMS).

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
  --script res://tests/t172_atlas_transfer_undo_preflight.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-172-2026-11-16-atlas-undo-preflight-raw && sha256sum -c SHA256SUMS)
```

## Remaining boundary

T-172 closes **Atlas Undo's** expected busy/native-ahead destination
retirement refusal. It does not make all host-owned detached history records
Rust-authoritative or guarantee atomic cross-document mutation across
arbitrary external callbacks. T-148 is still In Progress; T-149 remains
Blocked; T-095 requires physical owner/hardware acceptance.
