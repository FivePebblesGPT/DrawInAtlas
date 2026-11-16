# T-148 checkpoint — checked structural revision for never-imported raster layers

**Date:** 2026-11-15 · **Branch:** `sprint/2026-11-15` · **Ticket status:** In Progress. This change builds on local `5e05301d` (eight sprint commits beyond the verified GitHub `a83e5055` baseline); no owner/manual gate is self-approved.

## Defect and change

The previous semantic-subtree guard treated **every** raster child as potentially Rust-owned. Removing or restoring a newly created raster layer that had **never been imported into Rust** therefore advanced only the Godot revision. The next native Brush would drop unrelated, valid Rust tile authorizations and reversible raster history through `rebase_external_revision`, even when the removed raster source was wholly absent from Rust.

`DrawingNativeTiles.advance_unreferenced_layers_revision(expected, affected_ids, discard_redo)` now verifies **all** 1–128 distinct affected raster layer IDs, transaction quiescence and the exact revision, before committing a metadata-equivalent `r → r+1`. It rejects resident tile bytes, explicitly authorized blank tiles, and native Undo/Redo entries referencing **any** affected layer, even if the edit would clear redo. Source/history/revision are unchanged on rejection. New edits discard redo, while structural Undo/Redo preserves the existing redo branch. `remove_subtree` gathers raster descendants before deletion; structural history replay consults the saved IDs. When Rust rejects a truly owned raster subtree, the document continues its existing conservative stale-revision/rebase flow. No native pixels are deleted through this API.

The expanded Godot regression covers nested never-imported raster children, a deferred signed tile with hidden RGB, remove/Undo/Redo/Undo, an unrelated native Brush without byte reimport or history loss, and actual `.drawing` Save/Open. Its negative case first *paints* the nested raster with Rust; subsequent subtree removal is correctly rejected as a metadata-only native revision. Rust unit tests additionally verify rejection of imported transparent tiles, duplicate/empty/oversized IDs, stale revisions, active transactions and native history/redo while preserving unrelated tokens and byte counts.

## Reproduction and results

Pinned tooling: Godot `4.8.beta3.official.c51ff06e8`, Rust/Cargo 1.99.1, offline vendor store from bundle 8; Linux Xvfb llvmpipe. Use the bundle's `setup-rust-env.sh`; configure an **ephemeral, untracked** `native/drawing_brush/.cargo/config.toml` pointing to `dev-bundle/rust-hokusai/vendor`, then run `cargo test --offline --locked --lib`, `cargo fmt --all --check`, `cargo clippy --offline --locked --all-targets -- -D warnings`, and `cargo build --offline --locked --release`. For Godot, run `python3 tools/build_drawing_app.py --in-place`, install the built release `.so` in ignored `drawing/addons/drawing/native/bin/`, then use the exact beta3 executable:

```bash
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --audio-driver Dummy --path drawing \
  --script res://tests/t148_metadata_native_revision.gd
GODOT_SILENCE_ROOT_WARNING=1 timeout 130s xvfb-run -a -s '-screen 0 1280x900x24' \
  "$GODOT" --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing --script res://tests/t148_canvas_tile_cutover_x11.gd
python3 tools/validate_ticket_store.py
```

All successful process exits and test markers were checked; [raw logs and SHA-256 manifest](T-148-2026-11-15-unreferenced-raster-raw/SHA256SUMS) contain **17** retained checks, including the ticket validator and all Rust toolchain passes:

| Witness | Result |
| --- | --- |
| Rust unit suite / rustfmt / strict Clippy / release build | **21 tests** / pass / pass / pass |
| Expanded `t148_metadata_native_revision.gd` | **45 checks, 0 failures** |
| Persistent native document / external raster adoption | **44 / 28** checks, 0 failures |
| Native tile contract / document tile publication | **312 / 55** checks, 0 failures |
| Mixed-edit rollback / native brush integration | **504 / 32** checks, 0 failures |
| Live graphical Canvas tile cutover | **46** checks, 0 failures; tile pixel-stream calls = 0 |
| 96px full-canvas NativeHard | Exact source oracle passed, 262,144 source pixels; **811.767ms** software-rendered one-run gesture |
| 96px full-canvas Hokusai | Full 262,144 source coverage, byte-exact redo, **617.270ms** software-rendered one-run gesture |
| Object assets / Atlas campaign bundle smoke | **95 / 86** checks passed, separately (not integrated native-source persistence) |
| Ticket Kanban validator | **152 tickets** valid, no manual status changes |

The graphical gesture times are **single-run software/Xvfb results**, not physical latency or a performance acceptance. Both remain above the proposed 100ms target. An initial incorrect test invocation used the stale staged Drawing addon and was discarded; rebuilding the standalone stage from canonical sources resolved it. A first Object smoke invocation targeted the standalone Drawing project instead of the repository root; the corrected invocation exited zero. Neither failed setup attempt is treated as a successful test.

## Remaining ticket acceptance

Native-authorized raster subtree deletion/restore and structural history, text rasterization, detached token replay after evictions and other raster producers still need the universal canonical native source and revision contract. The passing standalone `.drawing` Save/Open is **not** a combined native Brush → Atlas/Object save-history acceptance. T-148 remains In Progress; T-149 stays Blocked; T-095 remains owner-gated.
