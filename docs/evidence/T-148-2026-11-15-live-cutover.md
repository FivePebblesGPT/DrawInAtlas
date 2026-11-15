# T-148 — production Canvas native-tile cutover checkpoint

Date: **2026-11-15** · branch `sprint/2026-11-15` · T-148 **In Progress**. See the earlier [native-store foundation evidence](T-148-2026-11-15-native-store.md) and [ABI v1 boundary](../NATIVE_RASTER_TILES_ABI_V1.md). The last verified GitHub branch HEAD was `a83e5055`; prior T-146/T-147/T-148 partial commits exist locally. This checkpoint does **not** authorize T-149 or close the native authority ticket.

## Actual production path now exercised

`DrawingCanvas` opts into `DrawingEditSession.begin_native_stroke(..., use_native_tiles=true, frozen_selection)` for NativeHard, Hokusai, and Eraser. A short-lived `DrawingNativeTiles` store begins at the document's current revision. Source tiles are authorized from `DrawingDocument._resolve_chunk` and imported as whole straight-RGBA8 tiles; a selected gesture imports a tile-wide eligibility mask. The actual brush batch is `append_samples → required_tiles → import_source/mask → apply_tile_batch`. Rust performs resampling/brush blending, selection masking, erasure, draft rollback, and dirtiness, and acknowledges the pending brush batch atomically. **Production** gestures no longer call `preview_changes` or populate GDScript per-pixel preview/history dictionaries. Historical direct-session fixtures still exercise those methods.

Canvas preview reads copied native RGBA8 via `preview_rgba8_tile`; the renderer supports native packed preview and authoritative `DrawingRasterTile` byte-backed source, preserving alpha-zero hidden RGB. On release, the session compares source object identity, layer permission and revision, exports dirty whole tiles, and pairs Rust `commit_tiles` with one `DrawingDocument._publish_native_tile_edit`. That document path validates all sources/coordinates/dimensions/bounds, installs packed source bytes, and records one reversible **whole-tile** document delta. It does not construct a String key per touched pixel. A failed input source, changed selection, stale revision, locked layer or cancellation must leave the native draft unpublished. Direct packed source serialization uses the existing `.drawing` writer.

## Executed verification (real process exit status 0, no script errors)

| Witness | Result | Exercised contract |
| --- | --- | --- |
| `t148_canvas_tile_cutover_x11.gd` (X11/Mesa) | **43 checks, 0 failures** | Real held preview/committed parity; 64² masked hard stroke and selection hole; transparent hidden RGB; independent `.drawing` save/open; packed source and tile-only history; undo/redo; Eraser; cancellation; injected lazy source failure and subsequent retry; selection tampering rejection; reentrant loader locking layer leaves raster unchanged |
| `t148_document_tile_publication.gd` | **55 checks, 0 failures** | Rust transaction → document tile publication; malformed/stale source rejects without mutation; byte-exact persisted file and history; packed renderer; buffer-alias safety |
| `t148_native_tiles_contract.gd` | **312 checks, 0 failures** | Direct store, full 512², signed tile seams, native masks, source and history parity, cancellation, retry |
| `t147_native_stroke_contract.gd` | **35 checks, 0 errors** | Existing single stroke ABI and batch rollback |
| `t095_native_hard_source_atomic.gd` | **113 checks, 0 failures** | Old direct-adapter source regression unaffected |
| `t095_native_pigment_atomic.gd` | **57 checks, 0 failures** | Old Hokusai direct-adapter source regression unaffected |
| `native_brush_integration.gd` (X11) | **32 checks, 0 failures** | Real native Canvas NativeHard, Eraser, Hokusai presets |
| `t095_full_canvas_brush_native.gd` (X11) | **Passed** | NativeHard 96px/512² image coverage and history |
| `t146_hokusai_full_canvas_native.gd` (X11) | **Passed** | Hokusai 96px/512² source RGBA8: 262,144/262,144 covered, 0 transparent holes; translucent source and exact Undo/Redo; native masked hidden RGB |
| Existing headless regression set | **Passed** | `renderer_sparse_layer_smoke` (74/74), `selection_clipboard_smoke`, `standalone_smoke`, `layer_structure_smoke` (63 checks), `image_frame_smoke` |
| `tools/validate_ticket_store.py` | **152 tickets validated** | Kanban, dependency and manual review invariants |

### Measured live transfer and timing (not hardware signoff)

The 64² NativeHard Canvas integration witness reports, for its initial edit, **11 stroke FFI calls**, **10 tile-store FFI calls**, **16,384 imported RGBA8 bytes**, **49,152 exported RGBA8 bytes** (held preview plus commit/other reads), and **0 tile pixel-stream calls**. `native_ffi_stats.exported_ints=1606` is a legacy stroke-internal counter; it is *not* a claim that Rust internally allocates no pixel integers, nor evidence that such triples cross GDScript in the new tile path. The tracked production brush session has empty `_preview_tiles` and `_after` pixel-history maps while held. No source/history mutation occurs until paired commit.

The latest **single cold X11 software-rendered** 512² / 96px trials measured NativeHard **650.672ms** and Hokusai **526.587ms** input-to-settled-postdraw. Both report `target_met=false` against the 100ms target. NativeHard staged CPU **154.659ms** with 24 drain frames; Hokusai staged CPU **138.918ms** with 17 drain frames. Earlier individual runs varied (NativeHard 808ms, Hokusai 536ms). These are **not** calibrated repetitions, input-device-to-photon measurements, or a sound regression comparison against previous process runs. T-095 real-machine/manual review gate remains open.

### Reproduce (using supplied offline development bundle)

```bash
rsync -a --exclude '.godot' addons/drawing/ drawing/addons/drawing/
/mnt/data/dev-bundle/run-godot-headless.sh --path drawing --audio-driver Dummy \
  --script res://tests/t148_document_tile_publication.gd
/mnt/data/dev-bundle/run-godot-headless.sh --path drawing --audio-driver Dummy \
  --script res://tests/t148_native_tiles_contract.gd
DRAWING_BRUSH_BACKEND=NativeHard /mnt/data/dev-bundle/run-x11-test.sh \
  /mnt/data/dev-bundle/run-godot.sh --audio-driver Dummy --path drawing \
  --script res://tests/t148_canvas_tile_cutover_x11.gd
DRAWING_BRUSH_BACKEND=Hokusai T095_FULL_CANVAS_RUNS=1 \
  /mnt/data/dev-bundle/run-x11-test.sh /mnt/data/dev-bundle/run-godot.sh \
  --audio-driver Dummy --path drawing \
  --script res://tests/t146_hokusai_full_canvas_native.gd
python3 tools/validate_ticket_store.py
```

Verbatim successful test-process logs plus SHA-256 hashes and observed exit statuses are under [`T-148-2026-11-15-live-raw/`](T-148-2026-11-15-live-raw/manifest.json). The Rust release extension was compiled and tested in the previous native-store checkpoint (17 Rust tests and strict Clippy pass); this commit changes only the GDScript consumer and documentation, not Rust code.

## Remaining acceptance / why T-148 is not Done

**Native ownership lasts one stroke, not one document.** After commit, `DrawingDocument` holds the packed raster tiles and reversible tile-snapshot Undo events, while the native tile store (including its history) is discarded. The transient Rust revision is initialized at `DrawingDocument.revision` and advances in lockstep for that one gesture, but long-lived canonical content/history and revision are **not** yet Rust-authoritative across mixed tool/tree edits and Atlas/Object consumers. A persistent native tile authority with one durable history protocol and comprehensive failure/rollback handling remains to be implemented and tested before marking T-148 Done. T-149 display/GPU/Atlas/persistence gates stay blocked, and T-095 owner physical responsiveness gate stays untouched.
