# Native Hokusai stroke ABI v1 (T-153; alpha breaking revision)

T-147 introduced the shared stroke ABI; T-153 **removed NativeHard and its
mode selector**. `DrawingNativeBrush` now always parses a MyPaint `.myb`
preset (including `hard_round.myb`) and uses Hokusai/libmypaint. Existing
caller argument arrays with a `mode` are rejected as incompatible.

## Frozen source and transaction lifecycle

At most one active stroke per native object. `begin_stroke` freezes layer ID,
valid `.myb` preset, positive finite width ≤4096, RGBA8 color, nonnegative
revision, and signed local clip. Godot freezes selection, source identity,
world anchor and the source revision in the accompanying `DrawingEditSession`.
Missing native brush/tile classes and invalid brush presets **fail closed**.

| Method | Arguments | Result / semantics |
| --- | --- | --- |
| `stroke_abi_version` | — | `1` |
| `begin_stroke` | `layer:String, preset_text:String, width:float, rgba:int, source_revision:int, clip:Rect2i` | `{ok,handle,abi_version}` or `{ok:false,error}`; no mode argument |
| `append_samples` | `handle,revision,PackedFloat32Array` | 1–4096 signed `(x,y,pressure,delta_seconds)` tuples with finite values, pressure 0–1, delta time (0,1] seconds; validates whole batch before mutation |
| `preview_changes` | `handle,revision` | `{ok,format:"xy_rgba",changes:PackedInt32Array}`; signed local `[x,y,RGBA8]` triples for transitional adapters/test probes |
| `acknowledge_batch` | `handle,revision,accepted:bool` | Accept pending batch, or fully rewind Hokusai stroke state, surface cache/RNG and published pixel cache on rejection |
| `required_tiles` | `handle,revision,stride,anchor_x:i64,anchor_y:i64` | Source tile IDs needed before atomic batch staging; no per-pixel crossing |
| `apply_tile_batch` | `tile_store,handle,revision,transaction,anchor_x,anchor_y,erase:bool` | Atomic native tile staging **and** pending batch acknowledgment/rejection |
| `stroke_stats` | `handle,revision` | `format:"xy_rgba"`, FFI/batch/bytes counters; no renderer mode |
| `commit_tiles` | `tile_store,handle,revision,transaction` | Publish Rust canonical tile/history token exactly once |
| `commit_stroke` | `handle,revision` | Transitional whole-stroke commit with no pending batch |
| `abort_stroke` | `handle` | Discard entire stroke and pending state |

One batch is pending at a time. Invalid handle/revision, overlapping begin,
malformed samples, missing source or masks, premature commit, and stale
layer authorization reject without publishing a partial edit. The production
Canvas uses the **native tile path**, not per-pixel Godot blending or
`preview_changes`. Tile staging uses Hokusai dab alpha and rebases against
immutable source; Eraser decreases source alpha using the *same* MyPaint
pigment alpha and preserves source RGB, including transparent hidden RGB.
Undo/Redo and Save/Open consume canonical tile history/snapshots as described
in [native tile ABI](NATIVE_RASTER_TILES_ABI_V1.md).

## Verification

Rust offline unit tests (22), strict Clippy, `t147_native_stroke_contract`,
`t148_native_tiles_contract`, graphical Canvas and 96px Hard Round
100-event witness all pass on the tested Linux x86-64 Godot 4.8-beta3
software renderer. See [T-153 evidence](evidence/T-153-2026-11-16-hokusai-only.md).
The T-095 owner hardware gate is untouched.

## Original planned tile-buffer contract for T-148 (historical design)

`TileId` is `{layer_id:String, tile_x:i64, tile_y:i64}` with **floor division** of signed global `(anchor + relative)` by configurable `storage_stride:u32` (initially 256 pixels). This is separate from the **64px Hokusai internal** and **128px display/viewport** tile sizes. Each authoritative tile has `format=StraightRGBA8`, channel byte order `[R,G,B,A]`, a bounded positive pixel width/height, `row_stride_bytes >= width*4`, and a length validated against checked `row_stride_bytes*height`. Transparent pixels retain **hidden RGB** exactly; use four byte channels even when alpha is zero. Bulk import/export must supply the source layer and base document revision and must not silently premultiply alpha.

Expose immutable `TileBufferHandle` + generation-scoped byte span and `TilePatch {TileId, base_revision:u64, base_generation:u64, new_generation:u64, dirty_bounds:Rect2i [inclusive start, exclusive end], buffer_handle, byte_offset, byte_len, row_stride_bytes, format}`. Dirty rectangles are tile-local and validated within tile extent; tile coordinates remain 64-bit even when Godot `Rect2i` uses i32 for local bounds. The handle/byte span stays valid until explicit release/acknowledgement or owning transaction abort, **not** after disposal or mutation; UI consumes copies/retained readonly spans, never mutable native pointers. Stale revision, mismatched layer/source generation, invalid span/bounds, memory-budget overflow, locked/hidden source, invalid mask or source read failure make a single atomic transaction error: **zero tile publication** and an entirely retryable original source. Keep bounded per-gesture memory, opaque transaction identity, rollback journal, tile-before/after history or COW snapshots, and bulk persistence semantics native-owned. The source revision is singular and shared with `DrawingDocument` (no parallel conflicting revision counters). The independently tested native tile store and its known consumer gaps are documented in [T-148's actual ABI](NATIVE_RASTER_TILES_ABI_V1.md); `.drawing` Save/Open and live UI display migration remain T-149.

## Historical contract note

The preceding planned buffer contract is retained as T-147-era design history;
the actually implemented and tested production ABI is the Rust `TileStore`
documented in [NATIVE_RASTER_TILES_ABI_V1.md](NATIVE_RASTER_TILES_ABI_V1.md).
The old two-renderer/opaque-pixel assumptions are not active requirements.
