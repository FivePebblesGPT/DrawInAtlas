# T-221 — measured selection Delete slowdown and sparse clear

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`. **Baseline verified GitHub PR #22 head:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`. **Owner report:** selection deletion feels slow; user did not identify whether the command was Delete pixels or Deselect. This document separates those actions without claiming to reproduce the owner's hardware behavior.

## Reproduction and attribution

Identical headless fixtures: 512×512 view selection, eight nonzero RGBA8 source pixels (including alpha-0 hidden RGB) across signed 32px tile boundaries, seven independent trials. `Delete` is a detached session `clear_rect()` plus atomic `commit()`; `Deselect` clears the `DrawingSelection` only. Time measured with `Time.get_ticks_usec()` per operation. The **before** suite was run with `edit_session.gd` restored to the actual remote baseline, then the same fixture with the fix. Percentiles use nearest-rank p50/p95 (n=7; p95 is maximum).

| Headless measured operation | Baseline p50 / p95 | After p50 / p95 |
| --- | ---: | ---: |
| Delete source scan and detached staging | **1,126,683 / 1,155,883 µs** | **83 / 99 µs** |
| Delete atomic journal/commit | 661 / 1,188 µs | 90 / 108 µs |
| Deselect selection-only | 9 / 47 µs | 3 / 9 µs |

A second after-fix model run measured Delete stage p50/p95 **75/96 µs**, commit **95/111 µs**, Deselect **3/9 µs**. The long stall originated in `clear_rect()`'s previous delegation to `fill_rect(area, 0, ...)`: it visited all 262,144 bounding-rectangle positions even though only eight pixels were stored. The commit phase was not the cause; Deselect does not touch document content or history.

## Real user-key event to native framebuffer completion

Godot `4.8.beta3.official.c51ff06e8` (Rust GDExtension reports API v4.7), Linux x86_64, `xvfb-run` X11 via `--display-driver x11 --rendering-method gl_compatibility`, 1010×720 viewport, 400% zoom, 512×512 image, two `process_frame` waits and `RenderingServer.frame_post_draw` before framebuffer read, seven Delete/Undo and Ctrl+D loops. Environment is a **virtual X11 display**, not physical GPU, compositor, owner machine or physical scanout. Renderer model was not independently established; do not infer GPU speed or VRAM values.

| Input → two render frames + framebuffer read | Baseline p50 / p95 | After p50 / p95 |
| --- | ---: | ---: |
| **Delete key** | **1,212,533 / 1,281,130 µs** | **21,277 / 22,599 µs** |
| **Ctrl+D (Deselect)** | **14,430 / 14,873 µs** | **15,509 / 25,583 µs** |

The Delete median falls about **57×**; it does not defer the stall to commit, Undo or frame rendering in the measured fixture. Independent repeated after-fix native-X11 run: Delete **24,197/30,620 µs**, Deselect **13,824/23,383 µs** p50/p95. These are short seven-sample software observations, not guarantees for dense multi-megapixel selections or p95 owner hardware targets. Framebuffer comparison checks visible content change after Delete and exact restored pixels after Undo; Ctrl+D preserves both document revision and pixels. The screenshot `t221-selection-native.png` was captured from the X11 harness; it is a test image, not an owner approval.

## Implementation and safety

- In the shared `addons/drawing/edit_session.gd`, `clear_rect()` now uses `DrawingDocument.tile_keys()` to inspect only overlapping occupied or pending source tiles. Tile-local `sparse_pixels()` yields all nonzero canonical RGBA8 values, **including zero-alpha hidden RGB**. Exact `DrawingSelection.allows()` applies holes/islands/inversion per candidate; a selected pending tile resolves through the existing guarded source loader, while an excluded one does not fetch.
- The 1,048,576 default candidate limit remains a bound on actual source pixels processed (including unpublished staged candidates), not on empty selection area. A 131,072×131,072 marquee with seven stored pixels does not allocate or iterate per marquee pixel. Dense edits still hit a bound, and invalid coordinates or closed sessions fail before publication. Detached snapshots roll back `_before`, `_after` and display previews on an error.
- A second pass clears pixels already staged in the current mixed Brush/shape/clipboard edit but not yet present in source tiles. The change does **not** alter the native Hokusai stroke ABI, Brush raster blend, Rust tile-history ownership, canonical tile bytes or the Atlas host history bridge.
- `drawing/tests/t221_selection_delete_regression.gd` verifies signed seams, hidden RGB, mask holes, enabled-empty selection, lazy corrupt sources, preview/budget rollback, mixed detached changes, signed 64-bit Atlas origins, exact Undo/Redo, locked/hidden layer restrictions, and standalone `.drawing` Save/Open (62/62 checks).
- `drawing/tests/t221_selection_delete_native.gd` sends native X11 keyboard shortcuts to a real standalone workspace, samples the actual framebuffer before/after Delete, verifies seven Undo cycles and seven non-dirty Ctrl+D cycles (25/25 checks). Existing `selection_clipboard_native.gd` covers the linked pointer/selection interaction (52/52 checks).
- `tests/t221_atlas_selection_delete.gd` uses a real native Brush stroke and external Atlas host history, an occupied signed source tile with a protected hidden-RGB mask hole, sparse Delete, exact Atlas Undo/Redo, and generation Save/Open. It checks native tile SHA-256 before and after as well as full byte equality (19/19 checks).

## Validation commands and results

```sh
GODOT=/mnt/data/unpacked/toolchain/bin/godot
$GODOT --headless --path drawing --script res://tests/t221_selection_delete_regression.gd
$GODOT --headless --path drawing --script res://tests/t221_selection_delete_benchmark.gd
xvfb-run -a $GODOT --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t221_selection_delete_native.gd
$GODOT --headless --path . --script res://tests/t221_atlas_selection_delete.gd
python3 tools/validate_ticket_store.py
git diff --check
```

Results: **62/62 model**, **25/25 native-X11**, **19/19 Atlas**, and **0 failures** in the following existing suites:

| Existing suite | Result |
| --- | --- |
| `selection_large_smoke.gd` | T-096 model passed |
| `selection_clipboard_smoke.gd` | T-088 model passed |
| `selection_sparse_paste_smoke.gd` | 56/56 |
| `selection_sparse_capture_smoke.gd` | 54/54 |
| `t130_pending_source_context_smoke.gd` | 34/34 |
| `selection_large_native.gd` | 34/34 native X11 |
| `selection_clipboard_native.gd` | 52/52 native X11 |
| `t148_atlas_native_tile_history.gd` | 43/43 |
| `drawing_composition_smoke.gd` | 89/89 |

The optimized Rust GDExtension was built offline with the bundled toolchain; Godot editor imports were performed for both projects. The complete `make build` invocation reached the native-ready marker but stalled in a subsequent integration smoke, so **do not count the overall Make target as passing**. The pre-existing GitHub PR #22 fast-desktop CI failures (strict export staging directory and stale T-083 dependency assertion) were **not** repaired or rerun here; their resolution belongs to separate CI work.

## Explicit owner/manual gate

T-221 has `manual_review: false` and its verified software performance scope is complete. The owner should recheck **Delete pixels** and **Deselect** separately on their actual hardware with the intended large sparse selection, reporting responsiveness and any long frame. T-088/T-059 (and T-148/T-149 native authority) remain **In Progress/Blocked** as recorded in the Kanban; no hardware, owner UX, or hosted CI approval is inferred here.
