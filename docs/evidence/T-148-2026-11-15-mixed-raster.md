# T-148 checkpoint — atomic external raster adoption into persistent Rust history

**Date:** 2026-11-15 · **Branch:** `sprint/2026-11-15` · **Status:** **In Progress** (not accepted / not T-149 unblock). Input HEAD was `7ce2d49c` (five local commits ahead of GitHub `a83e5055`). This extends the [persistent-store report](T-148-2026-11-15-persistent-store.md) and [native tile ABI](../NATIVE_RASTER_TILES_ABI_V1.md).

## Change and safety boundary

Previously, every GDScript raster publication advanced `DrawingDocument.revision` without advancing a live `DrawingNativeTiles` revision, so the next Brush discarded native source and the entire history stack. Ordinary pixel and tile publishers (`_publish_edit` and `_publish_tile_edit`) now join the native timeline **when the document already has an aligned persistent Rust store and `record_history=true`**:

1. GDScript fully resolves sources, validates old pixels, builds detached new tiles and dirty regions, then rechecks **every touched tile-object identity**, document revision, and layer editability. It prepares its reversible tile history envelope before the Rust call. No lazy provider executes after native acceptance.
2. A **single** `DrawingNativeTiles.adopt_external_edit(layer, expected_revision, Array[Dictionary])` receives up to **128** signed tile IDs and packed whole-tile before/after RGBA8 spans. Rust validates uniqueness, source-byte equality against previously authorized source, full replacement length, nonchange rejection, layer authority, source revision, no concurrent edit, coordinate limits, and conservative 256 MiB budget **before any canonical tile/history mutation**. An empty `before` explicitly authorizes a blank tile; a fully blank `after` is still a full-length span.
3. Success publishes all tiles, creates one Rust history token interleaved with native Brush/Eraser tokens, and advances the checked revision **once**. Godot then installs the already detached save/display projection and records the matching token. Failure publishes nothing. Source imports via the older `import_source` API are not redundantly performed. `external_bytes_received` separately reports packed bytes received from this bridge; the mixed two-tile success transferred **49,152 bytes** and no per-pixel output array.
4. Native Undo/Redo replays the matching token; Godot prevalidates all source bytes before replacing the projection. The new test covers Brush → external two-tile edit → Undo/Redo both → Brush → Undo/Redo, including source-preserved hidden RGB and a negative signed tile, plus two independent raster layers.

The original pixel-map publisher is retained when there is **no native store**, so previous direct-session fixtures still work. This checkpoint does not migrate the entire legacy paint suite; retiring those paths belongs to T-150. Importing whole external tiles can be costly for tiny changes, and no speed claim is made.

## Executed checks

All commands run in the supplied offline Bundle 8 environment (Godot `4.8.beta3`, native API `4.7`, Rust `1.99.1`), from the repository. The CLI was configured to use Bundle 8's vendored source directory; the native release `.so` was rebuilt from this working tree. Every listed test process exited **0**. See raw, independently hashed logs in [T-148-mixed-raw](T-148-2026-11-15-mixed-raw/SHA256SUMS).

| Command / witness | Actual result |
| --- | --- |
| `bash tools/build_native_brush.sh /mnt/data/dev-bundle` | Release native extension built and staged |
| `cargo test --offline --locked --lib` (vendored source config) | **19 Rust tests passed**, including atomic two-tile external adoption, source mismatch, stale revision, duplicate/no-op/malformed tile rejection, signed tile and mixed Undo/Redo |
| `cargo clippy --offline --locked --all-targets -- -D warnings` (vendored config) | Passed, strict warnings |
| `godot --headless --path . --script res://drawing/tests/t148_external_raster_adoption.gd` | **28 checks passed**, 0 failures; two layers, hidden RGB, mixed replay, signed source, invalid second tile, source substitution, `.drawing` Save/Open |
| `drawing/tests/t148_persistent_native_document.gd` | **44 checks passed**; now confirms imported external raster edits preserve current native history |
| `drawing/tests/t148_native_tiles_contract.gd` | **312 checks passed** |
| `drawing/tests/t148_document_tile_publication.gd` | **55 checks passed** |
| `drawing/tests/t095_mixed_edit_rollback_smoke.gd` | **504 checks passed** (native-free direct-session neighbor) |
| `drawing/tests/t148_canvas_tile_cutover_x11.gd` via software Xvfb | **46 checks passed**, zero production `tile_pixel_stream_calls` |
| `t095_full_canvas_brush_native.gd` / `t146_hokusai_full_canvas_native.gd` with explicit `DRAWING_BRUSH_BACKEND` via software Xvfb | Both passed, 512² source/96px/100 events; **816ms NativeHard** and **678ms Hokusai** single-run end-to-postdraw; **both above 100ms target**, not physical latency |
| `res://tests/object_assets_smoke.gd` | **95 checks passed** |
| `res://tests/campaign_bundle_smoke.gd` | **86 checks passed** |
| `python3 tools/validate_ticket_store.py` | **152 tickets valid**, owner manual-review dependency gates preserved |

The graphical X11 logs contain a nonfatal ALSA `ERR_CANT_OPEN` when Godot selects dummy audio under Xvfb; the relevant processes exited 0 with their own `failures=0` markers. This is not a graphics validation failure. These Atlas/Object save tests cover their existing consumers **separately**; they are *not* an integrated native-Brush → Atlas/Object save/reopen proof.

## Still open / next agent boundary

- **T-148 remains In Progress.** Document metadata/tree revisions and raster producers outside the two guarded publishers still advance GDScript's document state without a Rust transaction and may force a checked native-history-clearing rebase. Full universal revision authority and the removal of older event snapshot fallback are unfinished.
- The externally adopted tile bridge currently transports full before+after buffers (not a tile-COW diff or a measured optimal operation). Other tools remain GDScript producers; Brush/Eraser alone meet the no-GDScript-per-painted-pixel hot-path constraint.
- Final integrated source/history/Undo/Redo across Atlas/Object save workflows, multiple editing tools and reentrant invalidations is still required. The Atlas/Object smoke results above do not satisfy that requirement on their own.
- **T-149–T-152 remain Blocked; T-095 remains owner-gated.** Nothing here is a physical input-to-photon or owner acceptance result.
