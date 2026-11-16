# T-168 — Failure-atomic native raster subtree removal

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` · **Ticket:**
[T-168](../Tickets/T-168.md), **Done locally**. Parent [T-148](../Tickets/T-148.md)
remains In Progress, T-149 is Blocked, and T-095 is owner/hardware-gated.
No hosted CI or owner hardware acceptance is claimed.

## Defect and boundary

`DrawingDocument.remove_subtree()` previously attempted to park recorded
native-owned layers or retire unrecorded native-owned layers, but a rejection
(including a source mismatch, active Rust transaction or native-ahead revision)
was followed by unconditional Godot `_erase_subtree()`. It then advanced only
the GDScript revision through the old fallback, stranding Rust canonical
source/Undo authorization until the next checked rebase discarded history.

New removals with any raster descendant and an attached Rust tile store first
verify the exact native revision and byte-for-byte RGBA8 source parity, including
transparent hidden RGB. After detached snapshot preparation, the matching Rust
operation (park for local recorded removal, selective retire for unrecorded or
external-history removal) runs **before** the irreversible Godot tree deletion.
A never-authorized raster subtree may instead pass Rust's bounded
`advance_unreferenced_layers_revision` check; an owned layer or active edit
cannot use that path. If all bridges reject, the API returns `STALE_REVISION`,
`STALE_SOURCE` or `NATIVE_STRUCTURE` and changes **no** nodes, dirty state,
local history, canonical Rust source or revision. Valid recorded structural
Undo/Redo and irreversible unrecorded retirement retain existing semantics.
This is a cold structure edit, not a new Brush algorithm or native host-history
replacement. Native-absent legacy behavior remains until T-150.

## Real compiled-native proof and negative control

The same `drawing/tests/t168_native_subtree_removal_fence.gd` fixture ran under
Godot 4.8 beta3 with the bundled compiled Hokusai Rust GDExtension. It paints
one unrelated Ink layer and a nested raster subtree, then modifies a pixel's
hidden RGB at alpha zero. The changed source must refuse recorded removal
without altering the tree/revision/history, and exact-byte restoration is
retryable. An active native transaction must refuse both recorded park and
unrecorded retirement, with a successful retry after cancellation. Valid
removal/Undo/Redo/repeated Undo preserves canonical RGBA8 and unrelated Ink;
an unreferenced layer can advance both revisions without parking; a
native-ahead revision rejects deletion; and a document without Rust attached
still supports its historical removal path.

- **Patched source:** exit `0`, `T168_SUBTREE_RESULT checks=30 failures=0`
  and `T168_SUBTREE_PASSED`.
- **Pre-fix source** staged into the same standalone project, same native
  binary: exit `1`, `T168_SUBTREE_RESULT checks=30 failures=19`. The first
  failures are acceptance of an unauthorized hidden-RGB modification and
  erasure of Godot nodes despite a failed Rust park. Subsequent failures
  demonstrate that Undo/history and the follow-on removal cannot continue
  correctly after divergence. The fixed source was restored before the
  final matrix.

## Final local verification

| Check | Result |
| --- | --- |
| T-168 native subtree regression | **30/30**, exit 0 |
| Identical pre-fix control | **19/30 failed as expected**, exit 1 |
| Rust unit tests | **24/24**, exit 0 |
| rustfmt, strict Clippy, release GDExtension | Passed |
| T-147/T-148/T-154–T-167 native source/history regressions | Passed |
| Root Atlas/Object/history and lazy-cache regressions | Passed |
| Graphical Canvas native cutover | **46/46**, software X11 |
| Hokusai hard-round 96px / 512×512 witness | **262,144/262,144 source pixels**, software X11 |
| Ticket validator and CI YAML parse | **168 tickets valid**, parsed |

**43/43** final test/build invocations had exit code `0` and their required
passing markers. Raw stdout/stderr and exit/marker status are in
[`T-168 raw evidence`](T-168-2026-11-16-native-subtree-removal-raw/), including
[`summary.tsv`](T-168-2026-11-16-native-subtree-removal-raw/summary.tsv),
[`negative-control.tsv`](T-168-2026-11-16-native-subtree-removal-raw/negative-control.tsv),
and the [`SHA256SUMS`](T-168-2026-11-16-native-subtree-removal-raw/SHA256SUMS)
manifest. The one software-X11 96px run measured **422.829 ms** down to
post-draw and **116.901 ms** staging CPU; it is not a physical input-to-photon
result or owner T-095 acceptance.

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
  --path drawing --script res://tests/t168_native_subtree_removal_fence.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-168-2026-11-16-native-subtree-removal-raw && sha256sum -c SHA256SUMS)
```

## Scope still open

This gate prevents rejected **new** native-attached raster subtree removals
from silently diverging. It does not make general structural Undo/Redo replay,
host-owned detached history, other raster-producing tools, or the Atlas/Object
mixed document timeline universally native authoritative. T-148 remains In
Progress and T-149 remains Blocked; no manual gates were changed.
