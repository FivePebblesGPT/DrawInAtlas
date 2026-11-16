# T-166 — Native-owned save projection fence

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` · **Ticket:**
[T-166](../Tickets/T-166.md), **Done locally**. Parent [T-148](../Tickets/T-148.md)
remains In Progress, T-149 remains Blocked and T-095's physical-device/manual
approval is outstanding. No hosted CI or owner hardware acceptance was run.

## Cause and scope

`DrawingDocument.export_manifest()` previously hashed the resident GDScript
raster tile even if a **Rust-authorized** `DrawingRasterTile` was modified in
place. In-place mutation preserves the object identity and the document's
revision, so a revision-only fence does not establish byte authority. The
standalone `DrawingFileIO.encode()` and sparse `DrawingBundleManifest.encode()`
both use that logical manifest and would accept the unauthorized RGBA8 as the
new canonical source. `mark_published()` could then record the rogue content as
saved and clear the dirty tracking. An attached store with a divergent revision
was also not checked before exporting.

This fix adds a cold, side-effect-free `_native_save_projection_matches()`
preflight at `export_manifest()` and `mark_published()`. With an attached Rust
store, it checks the exact revision and calls the existing source-parity
validator across live authorized tiles: original object identity **and the
entire full-tile canonical RGBA8**, including hidden RGB under alpha zero.
Each mismatch returns `STALE_SOURCE` without touching the native store, history
or dirty state. No lazy provider is called during this check; never-authorized
lazy tiles and native-absent historical saves are unaffected. Savepoint calls
still verify durable blob refs separately. This is a save-boundary guard, not a
migration of the host's raw `snapshot_for_save()` dictionary or global history
ownership; that larger integration remains T-148/T-149 work.

## Fail-first and real-native proof

The **identical** `drawing/tests/t166_native_save_source_fence.gd` fixture was
run against the previous committed GDScript document (the original staged
standalone code) with the pinned compiled Rust/Hokusai extension. The process
exited **1**, with `T166_SAVE_FENCE_RESULT checks=24 failures=7`:
logical/standalone/sparse serializers accepted a mutated hidden-RGB tile,
`mark_published` certified it, and native-ahead export was permitted. Source
hashes, the unmodified log and explicit exit status are in
[raw evidence](T-166-2026-11-16-native-save-fence-raw/).

After the fix, the fixture exited **0**, `T166_SAVE_FENCE_PASSED (24 checks; 0 failed)`.
It performs a real Hokusai gesture and checks a Rust history token and full
canonical tile bytes. It mutates a **previously zero-alpha** projected pixel to
`0x00112233` without changing revision, observes all three exports and savepoint
acknowledgement reject the unauthorized bytes, restores the **same** tile
object byte-exactly, retries valid export and publication, then verifies exact
Undo/Redo. A separate deliberate native-ahead revision rejects all three
encoders and savepoint acknowledgement without advancing the document.

## Final matrix

| Verification | Result |
| --- | --- |
| T-166 real native save fence | **24/24**, exit 0 |
| Pre-fix negative control | **7/24** expected failures, exit 1 |
| Rust unit tests | **24/24**, pass |
| rustfmt, strict Clippy, release GDExtension build | Pass |
| Native tile and prior T-154–T-165 regressions | Pass |
| Standalone Drawing, root Atlas/Object, history and text regressions | Pass |
| Graphical Canvas software-X11 | Pass |
| 96px Hokusai 512×512 software-X11 | 262,144/262,144 pixels covered; **379.055 ms** down-to-postdraw (single trial), **not** reference-device acceptance |
| Ticket store, CI workflow | **166 tickets valid**; YAML parses |

The final suite recorded **41/41** process invocations with exit code zero and
passing markers. Process-by-process command labels, stdout/stderr and exits are
in [summary.tsv](T-166-2026-11-16-native-save-fence-raw/summary.tsv) and their
[SHA-256 manifest](T-166-2026-11-16-native-save-fence-raw/SHA256SUMS).

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
  --path drawing --script res://tests/t166_native_save_source_fence.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-166-2026-11-16-native-save-fence-raw && sha256sum -c SHA256SUMS)
```
