# T-169 — Failure-atomic native-attached raster subtree import

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` ·
[T-169](../Tickets/T-169.md) completed locally. T-148 remains In Progress,
T-149 Blocked and T-095 owner/hardware-gated. No hosted CI or hardware
acceptance is claimed.

## Defect and implementation

`DrawingDocument.import_subtree` already prepared the entire remapped tree,
but passed raster IDs to `_advance_raster_structure_revision`, a void helper
that incremented the Godot revision even when the bounded Rust
`advance_unreferenced_layers_revision` call failed. An active native edit,
native-ahead revision or >128 imported raster IDs could therefore publish
Godot-only nodes, leaving the canonical Rust tiles and native history at an
older revision. The next gesture's rebase could clear legitimate Undo tokens.

The new raster import boundary validates the attached native revision before
calling the exact bounded unreferenced-layer bridge. If Rust declines, the
import returns `STALE_REVISION` or `NATIVE_STRUCTURE` **before modifying the
Godot tree, dirty tiles, revision or local history**. Accepted imports advance
both stores exactly once and publish the prebuilt detached tree; new raster
source bytes are imported into Rust on their first native edit. Semantic-only
imports and native-absent historical imports keep their prior contracts.

The old T-148 subtree-import fixture expected 129 raster IDs to bypass the
Rust limit through a Godot-only import. That obsolete oracle is now replaced
by a full atomic rejection plus a fresh Hokusai stroke that retains the prior
native token. An over-limit snapshot can still be imported into a document
without a native store, pending Legacy retirement under T-150.

## Fail-first and real-native regression

`drawing/tests/t169_native_import_fence.gd` uses the bundled Godot 4.8 beta3
and compiled Hokusai/Rust GDExtension. It paints an authorized Ink layer,
imports a detached nested raster with transparent hidden RGB, and checks:

- Active Rust transaction refuses raster import; nodes, dirty/history state,
  revision, canonical bytes and native token remain intact.
- Discarding the transaction makes a byte-exact retry succeed; unrelated Ink
  Undo/Redo still works and native/document revisions stay matched.
- Native-ahead revision refuses further raster import, without adding nodes.
- A 129-raster subtree refuses the bounded Rust bridge as one atomic operation.
- Native-absent import of the same hidden-RGB subtree remains supported.

**Patched result:** exit `0`, `T169_IMPORT_RESULT checks=23 failures=0`
with `T169_IMPORT_PASSED`.

**Negative control:** the identical fixture against the pre-change
`document.gd` (same native `.so`) exited `1` with
`T169_IMPORT_RESULT checks=23 failures=10`. The primary failures are a
successful Godot-only import while Rust holds a transaction, and the resulting
divergence. The native version and test fixture did not change between
negative control and positive test.

The updated neighboring `t148_import_subtree_native_revision.gd` passes
**33/33** checks with the new over-limit rejection contract.

## Final local verification

| Check | Result |
| --- | --- |
| New T-169 native fixture | **23/23**, exit 0 |
| Pre-fix control | **10/23 failed as expected**, exit 1 |
| Existing T-148 detached import regression | **33/33**, exit 0 |
| Rust unit tests | **24/24**, exit 0 |
| rustfmt / strict Clippy / release GDExtension | Passed |
| T-147/T-148/T-154–T-168 native source/history and clipboard regressions | Passed |
| Root Atlas/Object/history and lazy-cache regressions | Passed |
| Graphical Canvas | **46/46**, software X11 |
| Hokusai 96px / 512×512 graphical witness | **262,144/262,144 pixels**, software X11 |
| Ticket store and CI YAML | **169 tickets valid**, parsed |

**45/45** recorded final suite invocations had process exit status `0` and
expected successful markers. Raw logs and per-test exits are preserved in
[`T-169 raw evidence`](T-169-2026-11-16-native-import-fence-raw/), including
[`summary.tsv`](T-169-2026-11-16-native-import-fence-raw/summary.tsv),
[`negative-control.tsv`](T-169-2026-11-16-native-import-fence-raw/negative-control.tsv)
and [verified `SHA256SUMS`](T-169-2026-11-16-native-import-fence-raw/SHA256SUMS).

In the single software-X11 96px run, full source coverage was verified with
334.669 ms down-to-post-draw, 110.982 ms staging CPU, and zero tile-to-pixel
FFI stream calls. These are software-run observations, **not** T-095 physical
input-to-photon latency or owner approval.

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
python3 tools/build_drawing_app.py --in-place
GODOT=/mnt/data/archive_unpacked/godot_bundle/Godot_v4.8-beta3_linux.x86_64
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --audio-driver Dummy \
  --path drawing --script res://tests/t169_native_import_fence.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-169-2026-11-16-native-import-fence-raw && sha256sum -c SHA256SUMS)
```

## Remaining scope

This ticket closes **new imported raster subtree publication** when an
attached Rust store rejects its structural revision bridge. It does not make
cross-document `transfer_subtree(..., move=true)` failure-atomic when a later
source removal is rejected, nor does it close host-owned detached history or
unconverted raster producers. T-148 remains In Progress; T-149 is Blocked;
no manual-review gate changed.
