# T-229 — Stride-dependent native history transfer budget

**Date:** 2026-11-22 · **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
Remote PR #22 baseline when inspected: `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`.
Working tree includes previously completed local T-221–T-228 commits.
Godot: bundled 4.8 beta3; Rust toolchain: bundled offline cargo; X11: llvmpipe Mesa.

## Reproduction and correction

The pre-fix `drawing/tests/t229_native_history_budget.gd` failed **three
checks** (`checks=16 failures=3`, exit 1): the document failed to return
`HISTORY_TARGET` for an oversized envelope, and both independent Rust
history entry points failed to return an early memory-budget error. The
old path proceeded into source/buffer validation and could allocate or fetch
unnecessarily. This is a bounded allocation/atomicity regression, **not** a
measured end-to-end performance benchmark.

Godot `DrawingDocument._replay_native_tile_delta` now preflights
`count * tile_stride² * 4 * 3 <= 256 MiB` before resolving any tile.
Rust's `history_transfer_within_budget` uses `checked_mul`, validates
configured stride and caps both `replay_detached_history` and
`replay_history_token` **before** duplicating inbound RGBA8 into vectors.
The existing per-transaction 128-tile cap, exact source/token guards and
256 MiB resident store checks are retained. A 2048px six-tile envelope now
fails, while 128 256px tiles remain within this conservative envelope.

The final 18-check Godot regression also registers a pending lazy source
with a callback counter, verifies zero callbacks and unchanged pending
identity on rejection, checks both Rust entry points independently,
and exercises successful signed 64px detached replay, hidden-RGB tile
parity against Rust, Undo/Redo and `.drawing` Save/Open.

## Local validation

| Test | Verified result |
| --- | --- |
| `drawing/tests/t229_native_history_budget.gd` (post-fix) | 18/18 headless native checks |
| Bundled `tools/build_native_brush.sh --test` | 36/36 Rust unit tests |
| `drawing/tests/t148_native_tiles_contract.gd` | 312/312 checks |
| `drawing/tests/t148_external_raster_adoption.gd` | 28/28 checks |
| `drawing/tests/t156_legacy_pixel_native_replay.gd` | 37/37 checks |
| `drawing/tests/t157_lazy_source_reentrant_guard.gd` | 23/23 checks |
| `tests/t148_detached_native_bootstrap.gd` | 34/34 checks |
| `tests/t148_native_history_payload_guard.gd` | 20/20 checks |
| `tests/t148_detached_native_replay.gd` | 21/21 checks |
| `tests/t148_atlas_native_tile_history.gd` | 43/43 checks |
| `drawing/tests/t148_canvas_tile_cutover_x11.gd` under `xvfb-run` | 46/46 native-X11 checks, zero tile pixel-stream FFI calls |
| `cargo check` (offline vendor) and release build + `cargo fmt --check` | Passed |
| `cargo clippy --all-targets -- -D warnings -A clippy::chunks_exact_to_as_chunks -A clippy::collapsible_if` | Passed with **two pre-existing lint categories explicitly suppressed** under bundled Rust 1.99.1 |

All listed Godot tests ran against the compiled Rust GDExtension. The 9
headless Godot fixtures total **536 checks**, including T-229. The hosted
required-native workflow now includes the T-229 marker and assertion count,
but GitHub has **not** run this local commit.

## Not claimed

The envelope budget is conservative and independent of existing resident
history; it is **not** a process-RSS bound or a complete native-memory proof.
It does not migrate Atlas's host-owned snapshot timeline or the remaining
non-Brush raster producers to native authority. T-148 remains In Progress,
T-149 Blocked, and T-095 owner hardware/physical acceptance open. No owner
review was inferred from the local software tests.
