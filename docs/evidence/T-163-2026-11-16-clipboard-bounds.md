# T-163 — bounded signed clipboard source capture

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` · **Status:** Done locally; integration parent [T-148](../Tickets/T-148.md) remains In Progress. The T-095 physical-input/owner review gate and T-149 dependency block remain unchanged. All runs below used the local Godot **4.8 beta3** bundle, offline Rust/Hokusai build and software-X11; hosted CI was not run.

## Bug and fix

`DrawingClipboard.capture` previously summed a caller-controlled signed-64-bit source origin with signed 32-bit rectangle offsets before validating either. In Godot, `INT64_MAX + 1` wraps to `INT64_MIN`, so an invalid copy could succeed and read an unrelated sparse location. A valid `±2^60` origin with a rectangle extending beyond that bound was also accepted, as were local `Rect2i` source coordinates that would overflow `Vector2i` during subsequent selection/copy handling.

The capture now checks the **input origin before addition**, then calculates the inclusive last local and world pixels using signed 64-bit integers. It rejects an out-of-range local coordinate or either out-of-range world endpoint with `COORD_RANGE`, **before** accessing any source/lazy tile. It reuses `SignedTiles.document_anchor_in_range` (inclusive `±2^60`); valid far-signed and boundary captures remain supported. No Rust ABI or rasterization algorithm is changed; clipboard data stays a detached read-only payload.

## Fail-first regression

The same `drawing/tests/t163_clipboard_capture_signed_bounds.gd` was first run with the **unmodified T-162 clipboard** and the previously built/staged native binary. That invocation exited **1** with `T163_CLIPBOARD_RESULT checks=34 failures=11`: four wrapped 64-bit extrema, four world rectangle/origin bound violations, two 32-bit local-range violations, and an invalid capture of an attached native document were incorrectly accepted. The corrected source was then staged with `python3 tools/build_drawing_app.py --in-place`, and the identical test exited **0** with `T163_CLIPBOARD_PASSED (34 checks; 0 failed)`.

The positive witness additionally confirms valid inclusive positive/negative `±2^60` copy bounds; a signed lazy tile's **alpha-zero hidden RGB** (`0x00123456`) is read unchanged; invalid requests never invoke the lazy loader or `_resolve_chunk` and never change revision or display epoch; a live Hokusai native tile/history token remains intact through rejection; and regular source Copy plus native Undo/Redo continue to work.

## Final matrix

| Check | Result |
| --- | --- |
| New real-native T-163 fixture | **34/34**, exit 0, exact success marker |
| Pre-fix negative control | **11/34 failed** as expected, exit 1 |
| Offline Rust unit tests | **24/24** |
| rustfmt, strict Clippy, release library build | Pass |
| Existing sparse capture, clipboard model, sparse paste | **54/54**, `T088_MODEL_PASSED`, **56/56** |
| Native tile contract | **312/312** |
| Neighbor T-154–T-162, native stroke/history, root Atlas/Object/text/lazy | Pass |
| Graphical software-X11 Canvas tile cutover | **46/46**; no per-pixel tile FFI stream |
| Graphical 96px Hokusai 512² source fill | **262,144/262,144 pixels**, one software trial `total_p95_ms=386.338`, `target_met=false` |
| Ticket-store validator and CI workflow parse | **163 tickets valid**; parses with PyYAML |

**All 38 final test/build invocations** completed with exit code 0 and configured positive markers. See [per-invocation status](T-163-2026-11-16-clipboard-bounds-raw/summary.tsv), [raw logs and negative control](T-163-2026-11-16-clipboard-bounds-raw/), and [SHA-256 checksums](T-163-2026-11-16-clipboard-bounds-raw/SHA256SUMS). Representative commands (the bundled `setup-rust-env.sh` and offline Cargo config were applied for Rust):

```sh
python3 tools/build_drawing_app.py --in-place
GODOT_SILENCE_ROOT_WARNING=1 godot --headless --editor --import --quit --path drawing
GODOT_SILENCE_ROOT_WARNING=1 godot --headless --path drawing --script res://tests/t163_clipboard_capture_signed_bounds.gd
python3 tools/validate_ticket_store.py
```

The local software-X11 386.338 ms is **not** a physical input-to-photon measurement or T-095 acceptance. Neither general native source/history ownership nor hosted CI is claimed by this narrow read-only guard.
