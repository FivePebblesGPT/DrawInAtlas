# T-165 — attached native publication revision fence

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` ·
**Ticket:** [T-165](../Tickets/T-165.md), **Done locally**. The parent
[T-148](../Tickets/T-148.md) remains **In Progress**. T-149 is blocked
and T-095 still requires reference-device measurements and independent owner
acceptance. All results are local, using Godot 4.8 beta3 and the real bundled
Rust/Hokusai GDExtension; hosted GitHub CI was not run.

## Defect and fix

`DrawingDocument._install_prepared_edit()` previously selected the native
`adopt_external_edit`/`adopt_untracked_edit` path **only** when the attached
Rust tile-store revision equalled the document revision. If the attached
store was **ahead or behind**, the method silently took the historic
Godot-only path, installing raster bytes, advancing document revision, dirty
state and potentially local history while leaving Rust's canonical pixels
and tokens behind. A later Hokusai stroke could trigger a destructive checked
rebase. A revision mismatch must be a failure, never authorization to switch
algorithms or source owners.

The new `_attached_native_revision_matches` fence is called on entry to
`_publish_edit` and `_publish_tile_edit`, **before any lazy-source callback**,
and again by `_install_prepared_edit` after all source callbacks and before
native adoption. When an attached store's revision differs, publication
returns `STALE_REVISION` without a Godot-only write. Existing matched-store
recorded/unrecorded native adoption is unchanged; missing-store historical
publishing is unchanged until T-150. A separate, explicit
`_native_store_for_edit` checked rebase can repair a **behind** store (with
the documented loss of old native authorizations/tokens). Native-ahead
stores cannot be rolled back or overwritten by direct publication.

## Fail-first and positive witness

`drawing/tests/t165_attached_native_revision_fence.gd` was first run using
the previous committed document module and the same native extension. It
exited **1**, reporting `T165_FENCE_RESULT checks=51 failures=18`. In that
control, both the recorded and untracked pixel/tile publishers accepted
stale attachments, changed Godot pixels/revisions, and failed source/history
isolation. A callback that advanced Rust while resolving a valid lazy source
also produced Godot-only publication after preflight. The previous source
was staged from `git show HEAD:addons/drawing/document.gd`; the negative
control log was preserved before restaging the patch.

The identical fixture with the patched document exited **0**, reporting
`T165_FENCE_PASSED (51 checks; 0 failed)`:

- Real Hokusai stroke sets up a persistent native tile, opaque history token
  and canonical full RGBA8 payload for each case.
- Both `native_revision > document_revision` and `native_revision <
  document_revision` reject **recorded and non-historical** direct pixel and
  tile-local edits before installing bytes, dirty regions, history events or
  changing either revision.
- The failure preserves the attached store identity, its history token and
  original Rust RGBA8 bytes, including independent transparent-black pixels.
- A lazy loader that **increments only the native revision during fetch**
  triggers the final preflight fence without publishing the proposed edit.
  The previously loaded lazy-source chunk may remain cached as a read-side
  effect, but no edit, dirty state, or history mutation occurs.
- Explicit checked recovery from a behind store and subsequent direct
  publication succeed; correctly synchronized recorded/unrecorded publishers
  still retain alpha-zero hidden RGB, native token and Undo/Redo. The
  genuinely native-absent historical publisher still works.

## Final test matrix

| Verification | Observed |
| --- | --- |
| T-165 real-native test | **51/51** passed, exit 0 |
| Pre-fix control | **18/51** expected failures, exit 1 |
| Pinned offline Rust unit tests | **24/24**, pass |
| rustfmt, strict Clippy, release build | Pass |
| Native tile contract | **312/312**, pass |
| Previous T-154–T-164, native/semantic/history and lazy-source regressions | Pass |
| Atlas/Object, external history, text and root tile-cache regressions | Pass |
| Graphical Canvas (software X11) | **46/46**, pass |
| Hokusai 96px, 512×512 software-X11 witness | **262,144/262,144** source pixels; `total_p95_ms=381.751` in one trial; `target_met=false` |
| Ticket store and CI YAML | **165 tickets valid**, YAML parses |

**40/40 final suite invocations** exited 0 with passing markers. The summary
of exact commands, per-process exit/marker status, unedited stdout/stderr,
pre-fix failure and restaging logs are in
[the raw evidence directory](T-165-2026-11-16-attached-revision-fence-raw/summary.tsv),
with [SHA-256 checksums](T-165-2026-11-16-attached-revision-fence-raw/SHA256SUMS).
The X11 witness is one software trial, **not** physical input-to-photon
latency or T-095 approval. This fix does not complete universal Rust owner
migration, T-148's general host history gate, or unblock T-149.

## Reproduction

```sh
source /mnt/data/archive_unpacked/godot_bundle/setup-rust-env.sh
export CARGO_TARGET_DIR=/mnt/data/work/cargo-target
cargo test --manifest-path native/drawing_brush/Cargo.toml --locked --offline --lib --config /mnt/data/work/t153-cargo-config.toml
cargo fmt --manifest-path native/drawing_brush/Cargo.toml --all --check
cargo clippy --manifest-path native/drawing_brush/Cargo.toml --all-targets --locked --offline --config /mnt/data/work/t153-cargo-config.toml -- -D warnings
cargo build --manifest-path native/drawing_brush/Cargo.toml --release --locked --offline --config /mnt/data/work/t153-cargo-config.toml
python3 tools/build_drawing_app.py --in-place
GODOT=/mnt/data/archive_unpacked/godot_bundle/Godot_v4.8-beta3_linux.x86_64
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --editor --import --quit --path drawing
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path drawing --script res://tests/t165_attached_native_revision_fence.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-165-2026-11-16-attached-revision-fence-raw && sha256sum -c SHA256SUMS)
```
