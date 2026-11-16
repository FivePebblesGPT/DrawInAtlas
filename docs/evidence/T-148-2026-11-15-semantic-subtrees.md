# T-148 checkpoint — semantic-only subtree edits keep native raster history

**Date:** 2026-11-15 · **Branch:** `sprint/2026-11-15` · **Status:** In Progress. Extends [metadata revision bridge](T-148-2026-11-15-metadata-revisions.md) on local input HEAD `95928af6` (seven existing local commits since GitHub's verified `a83e5055` branch head). The test runner uses the provided Godot 4.8 beta 3 and the previously built Rust GDExtension. The Rust source is unchanged in this checkpoint.

## Defect and change

`DrawingDocument.remove_subtree()` always incremented its serialized revision without advancing the attached native tile-store revision, even when the removed subtree contained **no raster layers**. Similarly, `_replay_structure` treated removal/creation Undo/Redo as potentially source-changing. A later Brush therefore rebased, throwing away otherwise valid Rust source authorization and native Undo/Redo history. The old 24-check regression explicitly assumed that removing an Objects layer required a rebase.

The document now recursively checks the subtree **before** deletion. When there is no raster node (groups/text/objects only), it applies `_advance_nonraster_revision()` after the structural mutation, using Rust's checked single-step metadata revision bridge and retaining the imported tiles and native Undo. A new semantic change discards Redo consistently with the Godot history branch; semantic structural history replay calls the same bridge with `discard_redo=false`, retaining valid native Redo. `_replay_structure` classifies the saved subtree snapshots rather than inspecting nodes that were already removed.

**Critical guard:** if **any** nested child is a raster node, removal or structural replay stays on the conservative document-revision path. This intentionally leaves the Rust store behind until `_native_store_for_edit()` checks and rebases it. A raster child is treated as source-bearing even if presently empty, because a stable ID may still have authorized native bytes/history. On a stale/active bridge failure, the existing fail-closed helper detaches Rust rather than claiming an aligned revision. No GDScript per-pixel Brush staging has been reintroduced.

## Executed tests

The [raw process logs and SHA-256 manifest](T-148-2026-11-15-semantic-subtree-raw/SHA256SUMS) include all 14 invoked successful test/validation processes. Every retained process exited zero and includes its own passing marker. Bundled tooling: Godot `4.8.beta3.official.c51ff06e8`, Rust 1.99.1 with the offline vendored dependencies, software X11 (`llvmpipe`) for graphical witnesses. Audio was explicitly set to `Dummy` to avoid irrelevant host ALSA errors. The Rust Clippy run required installing the offline vendor configuration in an ephemeral **untracked** `.cargo/config.toml`, deleted immediately after completion. The initial failed Clippy invocation without that config was not used as passing evidence.

| Witness | Outcome |
| --- | --- |
| Expanded `t148_metadata_native_revision.gd` | **35 checks, zero failures**: flat/nested semantic subtree deletion, restore, redo, structural creation undo/redo, native bytes/import counts/tokens, next Brush, nested raster rebase |
| `t148_persistent_native_document.gd` | 44 checks passed |
| `t148_external_raster_adoption.gd` | 28 checks passed |
| `t148_document_tile_publication.gd` | 55 checks passed |
| `t148_native_tiles_contract.gd` | 312 checks passed |
| `native_brush_integration.gd` | 32 checks passed |
| `t095_mixed_edit_rollback_smoke.gd` | 504 checks passed |
| `t148_canvas_tile_cutover_x11.gd` | 46 checks passed; native tile FFI, zero pixel-stream calls |
| `t095_full_canvas_brush_native.gd` (NativeHard) | Passed full 96px source oracle, 866.8ms one-run software time |
| `t146_hokusai_full_canvas_native.gd` (Hokusai) | Passed coverage/history oracle, 570.4ms one-run software time |
| `object_assets_smoke.gd` / `campaign_bundle_smoke.gd` | 95 / 86 checks passed, **separate** consumers, not integrated native-Atlas/Object validation |
| Rust unit suite, strict Clippy, rustfmt check | 20 Rust tests passed; Clippy `-D warnings`, fmt check passed |
| `tools/validate_ticket_store.py` | 152 tickets valid, no owner-review status changes |

Software-X11 timings are *not* physical input-to-photon timings or controlled performance evidence. Neither graphical run met the proposed 100ms responsiveness target.

## Remaining acceptance

T-148 is **still In Progress**. Raster-bearing subtree deletion/restoration/import, text rasterization, detached native-token replay after source rebases/eviction, and bypassing raster mutation producers still require one universal native history/source protocol. Atlas/Object tests above exercise their existing save paths **separately**, not a native Brush → Atlas/Object integrated save/reload. T-149 remains blocked; T-095 retains its hardware/owner review gate. No manual approval was assumed.
