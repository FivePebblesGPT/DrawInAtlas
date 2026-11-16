# T-162 — nonhistorical direct source stays native-authoritative

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` · **Ticket:** [T-162](../Tickets/T-162.md), **Done locally**. Integration parent [T-148](../Tickets/T-148.md) remains **In Progress**. T-149/T-150 and T-095's reference-device owner review remain blocked/unapproved. All execution below is local using Godot **4.8 beta3** and the bundled real Rust/Hokusai `DrawingNativeBrush`/`DrawingNativeTiles` GDExtension, not hosted CI.

## The defect and the boundary

With an already attached, in-sync native store, `DrawingDocument._install_prepared_edit()` gated its native whole-tile adoption on `record_history`. Calling `_publish_edit(..., false)` or `_publish_tile_edit(..., false)` therefore installed new Godot `DrawingRasterTile` pixels at `revision+1` while Rust remained at `revision` with its old canonical source/history. A later Hokusai brush could checked-rebase Rust to the newer Godot document, discarding unrelated native source authorizations and tokens. Suppressing history is **not** authorization to bypass the native owner.

The fix introduces `DrawingNativeTiles.adopt_untracked_edit` and shares its descriptor parser with the existing recorded `adopt_external_edit` ABI. Both validate the source, bounded distinct tile descriptors, exact RGBA8, editability, quiescence, checked revision and memory before a Rust commit. The untracked variant records **no** native history token (`history_token=0`), intentionally clears obsolete Rust Undo/Redo tokens, retains unrelated resident source tiles, and advances the Rust revision exactly once. The document installs its detached display/save projection only after that success. Godot appends **no** local/host history step for an explicitly nonhistorical edit, but marks the new source dirty against its last Save and drops abandoned Redo. Historical nonnative `_publish_edit(..., record_history=false)` replay explicitly skips this new untracked-change bookkeeping to preserve the Undo/Redo cursor. Prior local/host detached deltas remain revalidated on replay rather than trusting retired Rust tokens.

This closes only the **current attached-store, direct publication** gap. The older nonnative path and already-diverged store fallback retain their previous behavior. General native source/history ownership, host timeline redesign, and remaining raster producers stay in T-148; no manual or benchmark acceptance was inferred.

## Fail-first and real-native checks

`drawing/tests/t162_untracked_native_publication.gd` was run against the original T-161 document code with the same current native binary and after a successful Godot editor import. It **exited 1**, reporting `T162_UNTRACKED_RESULT checks=25 failures=11`. Failures exposed the missing Rust revision, absent signed/hidden RGB tile, persistent obsolete token, bad stale validation check, missing second/third adopted source and later Hokusai rebase. The identical fixture after the fix **exited 0**, reporting `T162_UNTRACKED_PASSED checks=25 failures=0`.

The corrected witness verifies a saved/clean baseline after an actual Hard Round gesture, subsequent untracked content becoming dirty without a local Undo entry; nonhistorical direct publication of a negative signed tile carrying alpha-zero hidden RGB; a stale-before-image rejection that leaves revision/dirty state unchanged; update of a **previously authorized** tile without history; a second nonhistorical tile-local publisher; no invented Undo entries/tokens; a later real Hokusai gesture retaining both native source tiles; exact canonical Godot/Rust bytes; new-gesture Undo/Redo; and `.drawing` Save/Open across all affected layers. Rust's added unit test checks invalid descriptor lengths, duplicates, wrong revision, active-transaction refusal, preservation of an unrelated tile and the ability to record subsequent native history.

## Final verification matrix

| Check | Observed |
| --- | --- |
| T-162 real-native regression | **25/25**, process exit 0, success marker |
| Identical pre-fix regression | **11/25 failed** as expected, process exit 1 |
| Rust offline unit tests | **24/24**, process exit 0 |
| Rust format, strict Clippy, release build | Pass |
| Neighbor T-154–T-161 native and lazy-source regressions | Pass |
| Native tile contract, direct external adoption and Hokusai ABI | Pass; **312/312** contract checks |
| Root Atlas/Object, detached source/history, text and lazy-cache regressions | Pass |
| Graphical X11 Canvas cutover | **46/46**; zero per-pixel tile FFI streams |
| 96px Hard Round Hokusai full-canvas graphical witness | **262,144/262,144** pixels; one software-X11 trial `total_p95_ms=366.781`, `target_met=false` |
| Ticket-store validator and CI workflow YAML | **162** tickets valid; YAML parses |

**34/34 final build/test invocations** returned exit code 0 and the configured success markers. Raw stdout/stderr, each invocation exit and check marker, pre-fix test log, editor import logs and source staging logs are retained in [the raw evidence directory](T-162-2026-11-16-untracked-native-raw/summary.tsv), with [SHA-256 checksums](T-162-2026-11-16-untracked-native-raw/SHA256SUMS). The 366.8 ms local software trial is **not** physical input-to-photon p95, does not approve the 100ms responsiveness gate, and does not claim hosted CI success.

## Reproduction

```bash
source /mnt/data/archive_unpacked/godot_bundle/setup-rust-env.sh
export CARGO_TARGET_DIR=/mnt/data/work/cargo-target
cargo test --manifest-path native/drawing_brush/Cargo.toml --locked --offline --lib --config /mnt/data/work/t153-cargo-config.toml
cargo clippy --manifest-path native/drawing_brush/Cargo.toml --all-targets --locked --offline --config /mnt/data/work/t153-cargo-config.toml -- -D warnings
cargo build --manifest-path native/drawing_brush/Cargo.toml --locked --offline --release --config /mnt/data/work/t153-cargo-config.toml
python3 tools/build_drawing_app.py --in-place
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --editor --import --quit --path drawing
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --audio-driver Dummy --path drawing --script res://tests/t162_untracked_native_publication.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-162-2026-11-16-untracked-native-raw && sha256sum -c SHA256SUMS)
```

The `cargo` commands require the supplied vendored/offline config; the Godot binary and native `.so` must be staged from the same build before running the Godot regression.
