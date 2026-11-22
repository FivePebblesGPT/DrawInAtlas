# T-233 — First direct pixel-map edit acquires native raster authority

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
Last verified remote PR #22 head: `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`.
Validation is local Linux x86-64 using bundled Godot 4.8 beta3 and the
bundled native GDExtension; **not** GitHub-hosted CI or owner hardware.

## Before / after

- Fail-first `drawing/tests/t233_pixel_native_bootstrap.gd`: **12 failures of
  30 assertions** with the previous implementation. First direct pixel-map
  transactions produced `tile_stride=0` history and never attached Rust;
  native-absent over-budget edits did not reject before lazy reads.
- After `addons/drawing/document.gd` cutover, expanded T-233 test:
  **37/37**. First direct and mixed EditSession edits, local and host-owned
  Undo/Redo, signed tiles, alpha-zero hidden RGB, untracked then recorded
  history, portable Save/Open, and failed-source/projection/budget attachment
  are covered. No native store is published on rejection.
- The native store accepts strides **16–2048**. The T-095 synthetic 1/2/3
  stride tests keep Godot-only model/replay, while supported 64/255/256/2048
  strides attach native ownership. This is an explicit native-ABI boundary,
  not an extra alternate production painting engine.
- T-100 pixel-oracle tests construct the expected independent pixel deltas
  without assuming the successful *reference publisher* still emits old
  per-pixel history. T-156 and T-230 now explicitly reconstruct historic
  in-memory archive events when testing compatibility. T-160 likewise
  reconstructs a historical out-of-projection pixel document, which new
  direct edits correctly reject.

## Local evidence

| Test / contract | Result |
| --- | --- |
| T-233 fail-first control | 12 expected failures / 30 pre-fix checks |
| T-233 native pixel bootstrap | 37/37 checks passed |
| T-100 independent signed/masked pixel oracle | 197/197 passed |
| T-095 signed stage/tile-lookup oracle | 4,193/4,193 passed |
| T-156 legacy pixel-native replay | 38/38 passed |
| T-160 signed native publication | 46/46 passed |
| T-165 attached revision fence | 51/51 passed |
| T-230 detached historical pixel bootstrap | 33/33 passed |
| T-231 direct transfer bounds | 24/24 passed |
| T-232 tile-local bootstrap | 34/34 passed |
| T-148 native tile ABI | 312/312 passed |
| T-148 Atlas native history | 43/43 passed |
| T-148 Atlas detached bootstrap/replay/payload/reentrancy | 34/34, 21/21, 20/20, 26/26 passed |
| T-148 Object native persistence | 38/38 passed |
| T-221 Atlas selection-delete | Passed |
| T-148 native-X11 Canvas tile cutover | 46/46 passed, no per-pixel tile FFI stream |
| Bundled Rust unit tests | 36/36 passed |

No source or native transfer budget failures were dismissed as harmless:
over-budget requests must avoid lazy callbacks and leave Godot/Rust unmodified.
The expected pre-fix failures are separate from the final passing regression
results. Additional tests are in CI's required-native step with a fixed count.

## Still open

T-148 continues for remaining non-Brush raster producers and fully host-owned
command lifetime, including semantic/structural synchronization. T-149 is
Blocked. Owner hardware UX, Windows portability and the exact-head hosted
GitHub Actions run are not established by these local checks. PR #22 remains
unpushed as of this evidence; no manual-review approval was inferred.
