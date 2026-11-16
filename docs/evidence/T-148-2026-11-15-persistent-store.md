# T-148 checkpoint — document-persistent native Brush/Eraser store and tokenized Undo

Date: **2026-11-15** · Branch `sprint/2026-11-15` · **T-148 remains In Progress** (not final acceptance). This report extends the [native-store](T-148-2026-11-15-native-store.md) and [production tile cutover](T-148-2026-11-15-live-cutover.md) evidence. See the updated [ABI contract](../NATIVE_RASTER_TILES_ABI_V1.md).

## Implementation and authority boundaries

- `DrawingDocument` retains a single `DrawingNativeTiles` RefCounted object per document rather than allocating/discarding one for each native Brush/Eraser gesture. A new session requests the store at the document's current revision; a second native stroke reuses already authorized source bytes if, and only if, its tracked Godot source-object identity still matches. An undocumented identity replacement fails closed. The first tested 64² native stroke imported **16,384 RGBA8 bytes**; the second imported **no additional tile bytes**, leaving the store object and two native Undo events resident.
- Rust `commit_tiles` exposes an opaque `history_token`. `DrawingDelta` carries that token and reversible packed tile snapshots. The local document timeline preflights expected source bytes, then uses `has_history_token` and `replay_history_token` for same-store Undo/Redo. Rust and document revisions advance one stamp per committed gesture and per history replay. Wrong, stale, unrelated or unavailable tokens cannot replay a different Rust event.
- When a non-native edit (layer lock/unlock or a real GDScript raster edit) advances the serialized document revision, the next native session calls a **quiescent, strictly monotonic** `rebase_external_revision`. This discards all native cached tiles, authorizations and native Undo/Redo entries and repopulates the needed source from the authoritative document snapshot. Older document history events remain undoable via verified tile deltas; a mixed fallback advances the document stamp, forcing a rebase before another native gesture. Rebase is rejected while an edit is active. This is **not** universal native history authority across mixed edits.
- Commit publication now has a detached two-phase document preflight. Source callbacks may reenter the document and mutate locks, revision, or tile identity; all bounds and bytes are prepared without mutation and their authority is checked *again after all source callbacks*. Rust commits only after that complete check. The preflight result is installed afterward without a second source callback. This closes a real half-commit risk observed by an injected reentrant lock on the third source read: before the final authority recheck, Rust advanced while Godot rejected publication; after the fix the native revision remains unchanged and retry works. A separate witness arms a fourth-read trap and verifies no postcommit resolver callback occurs.
- Godot still holds packed tile consumer snapshots for save/display and mixed raster APIs. Native tile generation and 64-history/256MiB budget rules remain as in the ABI. This checkpoint does **not** claim zero-copy GPU upload, full native-source ownership of Fill/Move/clipboard, or hardware input-to-photon latency.

## Executed tests (all exit code 0)

| Witness | Recorded result | Main coverage |
| --- | --- | --- |
| Rust release unit tests | **18 passed** | Persistence/rebase/token invariants, prior source/mask/seam/rollback tests |
| Rust `cargo clippy --all-targets -- -D warnings` and `cargo fmt --check` | **Passed** | Strict native compilation and style |
| `t148_persistent_native_document.gd` | **44 checks; 0 failures** | Reuse store and source bytes across gestures, exact native token Undo/Redo, real `.drawing` Save/Open, metadata and raster external rebases, mixed history fallback, no-revision tile replacement, provider reentry during preflight, no postcommit callback, failure retry |
| `t148_native_tiles_contract.gd` | **312 checks; 0 failures** | Direct large/signed tile native engine bridge, alpha/masks/history/failures |
| `t148_document_tile_publication.gd` | **55 checks; 0 failures** | Tile delta projection, history, save/import, wrong authority rejection |
| `t148_canvas_tile_cutover_x11.gd` | **46 checks; 0 failures** | Real X11 Canvas NativeHard/eraser persistent history, preview, mask, cancellation, source retry, file roundtrip, source mutation rejection |
| `t147_native_stroke_contract.gd` | **35 checks; 0 errors** | Unified native brush v1 ABI |
| `t095_native_hard_source_atomic.gd` / `t095_native_pigment_atomic.gd` | **Passed both** | Neighboring direct-session rollback fixtures (prior checks: 113 and 57) |
| `t095_full_canvas_brush_native.gd` / `t146_hokusai_full_canvas_native.gd` | **Passed both** | Real 96px / 512² graphical full-canvas source and history witnesses; Hokusai reports 0 holes |
| `renderer_sparse_layer_smoke.gd` / `selection_clipboard_smoke.gd` | **74/74** / **passed** | Neighboring rendering and editing contracts |
| `standalone_smoke.gd` | **42 passed; 0 failed** | Standalone contract; Godot prints shutdown RID/ObjectDB leak diagnostics despite exit code 0 (raw log retained) |
| `python3 tools/validate_ticket_store.py` | **152 tickets validated** | Canonical statuses, dependency and manual-review gates |

Graphical trials use the pinned Godot 4.8 beta 3, X11 and Mesa software renderer. The Canvas live witness reports **10 tile FFI calls**, **16,384 bytes imported** and **49,152 bytes exported** for its initial source/preview/commit path, with **0 pixel-stream FFI calls**. These are diagnostic counters, not evidence of GPU zero-copy or physical latency improvement. Rust release unit tests use bundle 8's offline vendored dependencies. The exact logs and SHA-256 manifest are in [`T-148-2026-11-15-persistent-raw/`](T-148-2026-11-15-persistent-raw/manifest.json).

## Reproduction

```bash
bash tools/build_native_brush.sh /mnt/data/dev-bundle
rsync -a --exclude '.godot' addons/drawing/ drawing/addons/drawing/
/mnt/data/dev-bundle/run-godot-headless.sh --path drawing --audio-driver Dummy --script res://tests/t148_persistent_native_document.gd
/mnt/data/dev-bundle/run-godot-headless.sh --path drawing --audio-driver Dummy --script res://tests/t148_native_tiles_contract.gd
/mnt/data/dev-bundle/run-godot-headless.sh --path drawing --audio-driver Dummy --script res://tests/t148_document_tile_publication.gd
DRAWING_BRUSH_BACKEND=NativeHard /mnt/data/dev-bundle/run-x11-test.sh \
  /mnt/data/dev-bundle/run-godot.sh --audio-driver Dummy --path drawing \
  --script res://tests/t148_canvas_tile_cutover_x11.gd
python3 tools/validate_ticket_store.py
```

The offline Rust build script verifies `cargo fmt`; the raw Clippy/test logs were generated with the same vendored source configuration. Reproducibility assumes the supplied extracted bundle 8 and its prepared native extension import setup, not a system Rust installation.

## Unfinished T-148 acceptance (do not unblock T-149)

The persistent store is now canonical **between native Brush/Eraser gestures** but does not yet own all raster mutations. External Fill/Move/clipboard and some Atlas/Object edits still use `DrawingDocument` pixel paths, and non-brush mutation forces native history invalidation; unified history survives using Godot tile snapshots. The full cross-tool native editing/revision protocol and Atlas/Object persistence acceptance are not yet tested. The T-095 physical-device latency/owner gate remains independent and open. T-148 must remain **In Progress** and T-149 **Blocked**.
