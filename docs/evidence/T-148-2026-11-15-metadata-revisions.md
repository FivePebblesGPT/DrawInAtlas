# T-148 checkpoint — preserve native raster history through metadata revisions

**Date:** 2026-11-15 · **Branch:** `sprint/2026-11-15` · **Status:** **In Progress**, not T-149 unblock. Input HEAD `1fd06f3c` (six local commits ahead of verified GitHub `a83e5055`). Builds and tests use the supplied Bundle 8 (Godot 4.8 beta 3, Rust 1.99.1, vendored dependencies). This extends [mixed raster adoption](T-148-2026-11-15-mixed-raster.md) and the [native tile ABI](../NATIVE_RASTER_TILES_ABI_V1.md).

## Revision and failure contract

Previously, a layer rename, visibility/lock change, reorder, new empty layer, text-only commit or semantic-object change advanced Godot's `revision` but left the persistent native mirror on the old stamp. The next Brush gesture called `rebase_external_revision`, clearing native source authorizations and Rust's bounded Undo/Redo stack despite **unchanged raster bytes**.

The new `DrawingNativeTiles.advance_metadata_revision(expected, discard_redo)` advances the Rust mirror exactly one step **without** touching imported RGBA8 or Undo entries. It refuses stale revision, an active tile transaction or a positive 64-bit revision overflow without any tile/history/revision mutation. New metadata edits clear native Redo to match `DrawingDocument._drop_history_redo`; Undo/Redo of metadata-only structural or text events retain native Redo, allowing Brush → Rename → Brush → Undo ×3 → Redo ×3 to stay entirely on Rust's native raster history. The Godot document remains the sole serialized revision authority.

The Godot helper `_advance_nonraster_revision()` is used only where the old operation preserves canonical raster bytes: layer creation, rename/visibility/lock, reorder, pre-content density, add/move semantic object, text-only commit, metadata-only structural replay, text-only replay. On reentrant/stale native rejection, it detaches the old native store and clears its source-object identities; the affected active gesture cannot publish against the newly advanced document revision. The document's detached history snapshots remain available for recovery. It **does not** bridge raster-containing subtree removal/import, text rasterization, or detached byte-changing replay; those can still trigger a checked history-clearing rebase. The extension's preexisting `set_layer_editable` and Godot's `_editable` checks remain necessary for layer permissions.

This bridge is not a second mutable revision authority and does not implement Rust ownership of metadata/tree state. It intentionally lacks source hashes: callers are obliged to use it only when source bytes/identities cannot change. The active-transaction rejection is fail closed by store detachment, rather than pretending that the aborted Rust stroke committed or trying to rollback a GDScript metadata action after the fact.

## Executed checks

Raw process output and SHA-256 checksums: [T-148-metadata-raw](T-148-2026-11-15-metadata-raw/SHA256SUMS). Every listed process exited 0 and the test-specific result marker (where applicable) reports zero failures. `cargo` used the Bundle 8 offline vendor source configuration; the release native extension was rebuilt and staged.

| Witness | Observed result |
| --- | --- |
| Rust `cargo test --offline --locked --lib` | **20 passed**, including stale/active/overflow metadata revision rejection, source preservation and native token order |
| Rust strict Clippy, rustfmt check, release build | Passed |
| `t148_metadata_native_revision.gd` | **24 passed**; live Brush/Rename/Brush/Undo/Redo, native history/bytes/import parity, lock/unlock, semantic objects, redo invalidation, `.drawing` roundtrip, conservative subtree rebase |
| `t148_persistent_native_document.gd` | **44 passed**; previous lock/unlock rebase expectations updated to test preserved native history, reentrant source locks detach active store and can retry |
| `t148_external_raster_adoption.gd` | **28 passed**; packed external tile transaction history and stale-source/rollback |
| `t148_native_tiles_contract.gd` | **312 passed**, direct Rust bridge signed coordinates/masks/eraser/Undo |
| `t148_document_tile_publication.gd` | **55 passed** |
| `t095_mixed_edit_rollback_smoke.gd` | **504 passed** |
| Software-X11 `t148_canvas_tile_cutover_x11.gd` | **46 passed**; tile-only live Canvas, zero pixel-stream calls |
| Software-X11 96px `t095_full_canvas_brush_native.gd` NativeHard | Passed (one run, 1,029.5 ms input → postdraw, above 100ms proposed target) |
| Software-X11 96px `t146_hokusai_full_canvas_native.gd` Hokusai | Passed (one run, 521.4 ms input → postdraw, above target) |
| `object_assets_smoke.gd` / `campaign_bundle_smoke.gd` | **95 / 86 passed**, separate existing save consumers only |
| `tools/validate_ticket_store.py` | **152 tickets valid**, no manual gates changed |

Software X11 times are **not** physical input-to-photon metrics or statistically powered before/after measurements. Existing Object/Atlas smoke tests are **not** a single integrated native Brush → Atlas/Object save/reopen proof.

## Remaining T-148 acceptance

- Source-changing tree operations (`remove_subtree`, `import_subtree`, text rasterization), detached history replay, direct/externally owned mutations without tracked native tile adoption, and native history eviction can still require GDScript detached snapshot fallback plus a checked rebase. The 64-entry Rust Undo cap is unchanged.
- The non-raster tree remains Godot-owned by architectural choice. Universal native raster/revision authority, integrated Atlas/Object native source history and save/reload, and removing shadow fallback remain unproven.
- **T-148 stays In Progress**, T-149 stays Blocked. T-095 hardware responsiveness/owner review remains independent.
