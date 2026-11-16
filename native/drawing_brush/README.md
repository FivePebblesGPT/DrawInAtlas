# Native drawing stroke engine — required Hokusai ABI v1 (T-153)

`DrawingNativeBrush` is the **single** Rust GDExtension Brush/Eraser engine.
Every preset (`hard_round.myb`, `soft.myb`, `ink.myb`, `airbrush.myb`) is
parsed and rasterized by **Hokusai/libmypaint**. Hard Round is **not** a
separate raster kernel. Pressure, timing, overlapping pigment, signed
coordinates and alpha obey the chosen MyPaint preset. Eraser consumes the
**same** MyPaint dab coverage/opacity and decreases source alpha, preserving
source RGB (including RGB hidden at alpha zero); it does not use an opaque
hard-circle shortcut.

`begin_stroke(layer,preset_text,width,rgba,source_revision,clip)` has **no
renderer mode argument**. The handle-based `append_samples →
required_tiles → apply_tile_batch → commit_tiles` transaction stages RGBA8,
selection masks, source authorization and Undo/Redo in the shared Rust tile
store. `preview_changes → acknowledge_batch` is available for test/legacy
adapter consumers, but production Canvas has **no per-pixel Brush/Eraser
staging**. Missing or incompatible native binaries and invalid presets fail
explicitly; no GDScript Brush fallback is selected. The old *separate*
Legacy GDScript algorithm awaits removal in T-150 and is not Canvas-reachable.

ABI: [native strokes](../../docs/NATIVE_STROKE_ABI_V1.md) and
[native tiles](../../docs/NATIVE_RASTER_TILES_ABI_V1.md).

## Make-first build (T-180)

Linux x86-64 builds use `make drawing` with installed Godot/Rust, or
`make drawing TOOLCHAIN=bundle BUNDLE=/path/to/archive.tar.zst` with a pinned
offline archive. `make bundle` now reconstructs that archive on a connected
Linux host directly from `toolchain.lock.toml` plus `Cargo.lock`, without
requiring the older manually assembled bundle. The resulting archive and
per-file manifest are verified before native import. See
[toolchain setup](../../docs/TOOLCHAIN.md).

The historical `Godot_v4.8b3_rust_hokusai_bundle8.tar.zst` remains an
accepted SHA-256 checked input for transition, not the source of truth.
Every normal staged app requires both `libdrawing_brush.so` and
`drawing_brush.gdextension`; missing native binaries fail explicitly.
The tested target is Linux x86-64, Godot 4.8 beta 3, Rust 1.99.1,
Hokusai 0.3.0 and godot-rust 0.5.5 using the Godot 4.7 ABI.

## Regression suite

After compiling and importing the real native binary, run with Godot's
`--script res://tests/<name>.gd`:

- `t147_native_stroke_contract`: one MyPaint preset ABI, invalid preset/handles,
  revision binding, pressure validation and deterministic pigment rollback.
- `t095_native_pigment_atomic`: late source failure, rollback, hidden RGB.
- `t148_native_tiles_contract`: 312 checks for source authorization, signed
  64-bit tile IDs, alpha-preserving Eraser, masks, source histories and 512² fill.
- `native_brush_fallback` (renamed behavior, retained fixture name): required
  native/preset errors fail closed rather than falling back.
- `native_brush_integration`: four bundled preset canvases, Brush/Eraser,
  independent coverage/alpha, Undo/Redo and mask-hole regression.
- `t148_canvas_tile_cutover_x11`: live graphical native source/history,
  lazy-source retry, stale mask, atomic cancellation and Save/Open.
- `t146_hokusai_full_canvas_native` via `tools/run_t146_hokusai_bench.py`:
  96px/512² **100-event** Hokusai Hard Round, alpha histogram, full coverage,
  frame samples, Undo/Redo and failed-source recovery. No comparison backend.

See [T-153 execution evidence](../../docs/evidence/T-153-2026-11-16-hokusai-only.md).
Software-X11 results do **not** approve T-095's physical latency gate.
