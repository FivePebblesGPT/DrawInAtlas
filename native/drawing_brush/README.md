# Native drawing stroke engine — experimental alpha ABI v1 (T-147)

`DrawingNativeBrush` is a **single** optional godot-rust GDExtension with two internal raster strategies:

- **NativeHard** — deterministic, once-per-gesture hard-circle swept coverage, opaque Brush/Eraser and signed-coordinate clipping.
- **Hokusai** — MyPaint `.myb` pigment brush presets, pressure/time dynamics, native surface/RNG state and translucent RGBA8 export; not pixel-equivalent to NativeHard or Legacy.

Both use exactly the same `begin_stroke → append_samples → preview_changes → acknowledge_batch → commit_stroke/abort_stroke` **versioned, handle-based transaction ABI**. Source revision and brush state are frozen at start; invalid handles, source revisions, malformed samples and unacknowledged overlapping batches are rejected. No old mode-specific native transaction methods are retained.

**Authoritative interface and tile-buffer design:** [docs/NATIVE_STROKE_ABI_V1.md](../../docs/NATIVE_STROKE_ABI_V1.md). The current GDScript `DrawingEditSession` adapter still does source authorization, blending, mask and per-pixel staging; T-148 replaces the pixel-change stream with native-owned authoritative tile buffers and Undo transactions. Canvas NativeHard and Hokusai share the single v1 dispatch. The test directory contains *test-only* historical fixture adapters, not shipped native compatibility APIs. Legacy is present until T-150 as a temporary alpha fallback.

## Pinned offline build

Use the supplied `Godot_v4.8b3_rust_hokusai_bundle8.tar.zst` with SHA-256 `f486c8d13fb4005b864e9c6ba3af4fcf83f512deb1b871b794295f5704dcdeaa`. Extract its contents to `/your/tooling/directory`, verify with `./verify.sh --quick`, then from the project root execute:

```bash
./tools/build_native_brush.sh /your/tooling/directory
```

The build uses the bundle's vendored Cargo registry/lockfile offline, Hokusai 0.3.0 and godot-rust 0.5.5 built against the Godot 4.7 stable API for testing on Godot 4.8 beta 3. The generated `.so` binary and tool archive are **not** source-controlled. Linux x86-64 only; other platform release exports require separate testing. For standalone stage: `python3 tools/build_drawing_app.py --in-place`, followed by Godot import; in this beta, bundle's `prepare-godot-example.sh /staged/project res://addons/drawing/native/drawing_brush.gdextension` permits early script class loading.

## Regression suite

After compiling and importing the real native binary, run via Godot's `--script res://tests/<name>.gd`:

- `t147_native_stroke_contract`: v1 state machine, pressure, invalid handles, source-revision rejection, exact hard/pigment rollback, packed-transfer metrics.
- `t095_native_hard_source_atomic`, `t095_native_pigment_atomic`: actual late source failure, retry/skip, transparent hidden RGB, signed 64-bit anchored storage, source/history parity.
- `native_brush_integration`: actual GUI Canvas gestures for native hard/eraser, four Hokusai presets and masked selection, pixel/Undo oracles.
- `t095_full_canvas_native`, `t146_hokusai_full_canvas_native`: separate **96px, 512²** graphical witnesses using software X11, which do **not** assert cross-backend pixel equality.

See [T-147 evidence](../../docs/evidence/T-147-2026-11-15-unified-stroke.md), [T-146 baseline](../../docs/evidence/T-146-2026-11-15-hokusai-benchmark.md), and [T-095 historical source-rollback evidence](../../docs/evidence/T-095-2026-11-11-native-hard-source-rollback.md). None of this closes T-095 owner hardware review or proves the input-to-photon latency target.
