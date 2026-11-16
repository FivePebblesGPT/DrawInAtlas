# T-167 — Checked low-level native dirty snapshot

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` · **Ticket:**
[T-167](../Tickets/T-167.md), **Done locally**. Parent [T-148](../Tickets/T-148.md)
remains In Progress; T-149 remains Blocked and T-095's owner/manual
hardware acceptance is outstanding. Neither hosted CI nor owner testing ran.

## Failure and fix

`DrawingDocument.snapshot_for_save()` returned raw Godot `dirty_rgba8`
without validating the current persistent Rust authority. Unlike T-166's
logical/standalone/sparse manifest and saved-revision fences, the low-level
snapshot accepted an in-place modification of projected RGBA8 (including
invisible RGB with zero alpha) and a native-ahead revision. A consumer of this
dictionary could then treat the result as authoritative persistence data.

The API now returns `DrawingResult`. It checks `_native_save_projection_matches()`
**before** constructing any tree or dirty bytes and returns `STALE_SOURCE` on
mismatch. Successful `.value` retains the prior dictionary fields and detached
RGBA8 payload; call sites must check `.ok`. The preflight invokes no lazy
provider and leaves native history, document cursor/revision and dirty tiles
unchanged on refusal. This is a cold export/serialization boundary, not a
migration of host-owned Atlas history or a different Brush algorithm.

## Positive and fail-first proof

The identical `drawing/tests/t167_checked_native_dirty_snapshot.gd` test
passes **25/25** after the fix (exit 0, marker `T167_SNAPSHOT_PASSED`). It
paints a real Hokusai Hard Round path into a persistent `DrawingNativeTiles`
store, checks the full native RGBA8, snapshots dirty bytes, mutates the same
Godot tile to hidden RGB `0x00112233` with zero alpha, and verifies that the
snapshot rejects it. After restoring the same tile object byte-for-byte, a
new snapshot succeeds; mutating that snapshot's detached bytes does not mutate
canonical source. Native Undo/Redo works after the rejection, and a separately
advanced Rust revision is rejected without a new savepoint. A never-native
historical document still receives a successful empty snapshot.

To prove the regression, the same test ran with the previous committed
`addons/drawing/document.gd` staged into the standalone project while the
same compiled Hokusai GDExtension was loaded. The old path exits 1 and
reports `T167_SNAPSHOT_RESULT checks=25 failures=11`; notably it accepts
modified bytes and native-ahead source instead of returning `STALE_SOURCE`.
The source file was restored before the final full matrix, and neither the
negative control nor the temporary copy is part of the finished source tree.

## Final local verification

| Check | Result |
| --- | --- |
| Focused T-167 Godot witness | **25/25**, exit 0 |
| Previous-version fail-first | **11/25 failed as expected**, exit 1 |
| Rust unit tests | **24/24**, exit 0 |
| rustfmt, strict Clippy, release GDExtension | Passed |
| T-148, T-154–T-166 native tile/history and persistence regressions | Passed |
| Root Atlas/Object native history and lazy-source regressions | Passed |
| Graphical Canvas tile cutover | **46/46**, passed under software X11 |
| 96px/512×512 Hokusai witness | **262,144/262,144** pixels covered; **350.357 ms** down-to-postdraw (one software-X11 run) |
| Ticket validator, CI YAML | **167 tickets valid**, parses |

All **42/42** final test/build invocations completed with exit code 0 and
passing markers. Their stdout/stderr and statuses are retained in
[raw evidence](T-167-2026-11-16-checked-dirty-snapshot-raw/):
[`summary.tsv`](T-167-2026-11-16-checked-dirty-snapshot-raw/summary.tsv),
[`negative-control.tsv`](T-167-2026-11-16-checked-dirty-snapshot-raw/negative-control.tsv),
[`SHA256SUMS`](T-167-2026-11-16-checked-dirty-snapshot-raw/SHA256SUMS).
The 350.357 ms software-X11 result is **not** a reference-device p95 or
physical input-to-photon measurement; T-095 remains owner-gated.

## Reproduce

```sh
source /mnt/data/archive_unpacked/godot_bundle/setup-rust-env.sh
export CARGO_TARGET_DIR=/mnt/data/work/cargo-target
cargo test --manifest-path native/drawing_brush/Cargo.toml --offline --locked --lib \
  --config /mnt/data/work/t153-cargo-config.toml
cargo fmt --manifest-path native/drawing_brush/Cargo.toml --all --check
cargo clippy --manifest-path native/drawing_brush/Cargo.toml --offline --locked \
  --all-targets --config /mnt/data/work/t153-cargo-config.toml -- -D warnings
cargo build --manifest-path native/drawing_brush/Cargo.toml --offline --locked \
  --release --config /mnt/data/work/t153-cargo-config.toml
python3 tools/build_drawing_app.py --in-place
GODOT=/mnt/data/archive_unpacked/godot_bundle/Godot_v4.8-beta3_linux.x86_64
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --audio-driver Dummy \
  --path drawing --script res://tests/t167_checked_native_dirty_snapshot.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-167-2026-11-16-checked-dirty-snapshot-raw && sha256sum -c SHA256SUMS)
```
