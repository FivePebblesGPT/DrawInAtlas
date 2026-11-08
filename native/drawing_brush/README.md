# Optional Hokusai / godot-rust brush prototype (T-095)

This is an **opt-in** Linux x86-64 prototype. It is not the default editor brush
and does not constitute T-095 owner acceptance.

## Offline build and runtime

1. Verify the SHA-256 of the supplied
   `Godot_v4.8b2_bundle6_rust_hokusai.tar.zst`:
   `0886d42efe896cd5ba0dc9c82b684a6b68efa9d3537b833dc0efedd00b0b70b1`.
2. Extract its **contents** to a directory of your choice, using
   `zstd -dc bundle.tar.zst | tar -xf - -C /your/tooling/directory`.
3. Run `tools/build_native_brush.sh /your/tooling/directory` from the
   DrawInAtlas repository. The script sources the bundled Rust environment,
   pins the `Cargo.lock`, points Cargo at the bundled vendored registry and
   compiles **offline**. No globally installed Rust or Cargo is required, but
   the host still needs a normal C compiler/linker and compatible system libs.
4. The build copies `addons/drawing/native/drawing_brush.gdextension` and the
   Linux shared library to the addon. Neither generated binary nor the large
   tooling archive belongs in Git.
5. Run `python3 tools/build_drawing_app.py --in-place` for a standalone
   Drawing stage, or `--output /empty/external/directory` for a clean build.
   Staging includes native files only when **both** manifest and binary exist.
   Check Godot import and distribution/export artifacts separately.

The Rust workspace pins **Hokusai 0.3.0** and **godot-rust 0.5.5**. The
GDExtension is compiled against godot-rust's **Godot 4.7 stable API** and
has been smoke-tested in **Godot 4.8 beta 2** on Linux. This deliberate
compatibility choice must be retested with every target engine and export.
Windows/macOS binaries and release exports are **not** supplied.

## Integration boundary

`DrawingCanvas.brush_backend` selects one of:

- `Legacy` (default): existing exact swept-circle hard Brush/Eraser.
- `NativeHard`: native swept-circle coverage, legacy-style detached RGBA8
  paint, selection, preview, atomic commit, Undo/Redo and eraser semantics.
- `Hokusai`: loads a bundled upstream `.myb` preset with
  `brush_preset = "hard" | "soft" | "ink" | "airbrush"`. Pressure is exposed
  to the native API but the current Canvas mouse path passes constant 1.0.
  Hokusai brush pigment is exported as changed quantized straight RGBA8
  pixels, then composited against immutable original layer pixels by
  `DrawingEditSession`. GDScript still handles clipping, selections, sparse
  signed storage and transaction ownership. Eraser deliberately falls back to
  `NativeHard`.

If the native class or requested preset is unavailable, Canvas emits an
explicit warning and falls back to the legacy path. A missing binary and
manifest must never make the standalone project fail to import. Nothing
rewrites existing sparse document files or edits committed history directly.

For Hokusai pigment output, `DrawingEditSession.paint_path_hokusai()`
prevalidates every transferred coordinate and source tile before mutating
any detached transaction state. The hot loop then composites the validated
straight-alpha pixels against immutable source tiles without constructing
per-pixel rollback journals or per-pixel `DrawingResult` objects. Preview
content generations advance once per touched storage tile **per batch**,
not once per changed pixel. Native `preset_segments` and GDScript staging
CPU measurements are exposed in `Canvas.last_gesture_metrics.hokusai_perf`.
Both paths must remain atomic: invalid later deltas cannot partially alter a
previously valid preview. The dedicated `hokusai_bulk_delta_smoke.gd` test
runs without a native binary and checks the old pixel-at-a-time result.

Hokusai staging now groups prevalidated source deltas by storage-tile key,
updates detached integer-offset preview patches, and defers global `"x,y"`
`_before`/`_after` creation to commit. A counted delta map retains O(1)
`change_count()` while the paint button is held. A mixed edit API forces
materialization before a transactional rollback snapshot; later Hokusai calls
in that session use the original global-key staging route. This reduces
repeated per-dab GDScript allocation but moves some CPU time to release;
[paired Xvfb evidence](../../docs/evidence/T-095-2026-11-08-hokusai-tile-local.md)
documents the regression matrix and the remaining latency deficit.

The native class accumulates source-space points in batches and maintains its
own native tile/dirty state. It reports only changed RGBA8 pixel triples per
batch (rather than repeatedly copying each full 64px surface tile), avoiding
per-pixel GDScript-to-Rust calls. Coordinates, color conversion and opacity
are explicit, not assumed MyPaint/libmypaint raster parity. The presets are
CC0 and accompanied by their upstream licensing file.

## Gesture safety

States are `IDLE → CAPTURING → DRAINING → COMMITTING → IDLE`. Source-space
samples and frozen settings survive wheel zoom, middle-button pan, the Pan
toolbar and programmatic viewport camera changes **after mouse-up**. Another
stroke while the previous transaction drains is **blocked with feedback**.
A held paint gesture that attempts a viewport transform is explicitly
cancelled to avoid combining incompatible transforms. Escape remains an
intentional cancel. Document, layer, selection and snap changes also cancel
rather than publishing an invalid transaction.

## Tests

From a **freshly imported** standalone stage using the bundled Godot wrapper:

```bash
/path/to/tooling/run-godot-headless.sh --path /staged/drawing \
    --script res://tests/hokusai_bulk_delta_smoke.gd
/path/to/tooling/run-godot-headless.sh --path /staged/drawing \
    --script res://tests/native_brush_integration.gd
/path/to/tooling/run-godot-headless.sh --path /staged/drawing \
    --script res://tests/stroke_navigation_native.gd
/path/to/tooling/run-godot-headless.sh --path /staged/drawing \
    --script res://tests/native_brush_fallback.gd
```

To test no-binary fallback, stage from a checkout without
`addons/drawing/native/drawing_brush.gdextension`, import using
`--headless --editor --import --quit`, and rerun `native_brush_fallback.gd`.

`brush_latency_native.gd` accepts
`DRAWING_BRUSH_BACKEND=Legacy|NativeHard|Hokusai` for a software-only
comparison. Reproduction/evidence belongs under
`docs/evidence/T-095-2026-11-08-hokusai.md`.

**Not established:** acceptable 60px responsiveness on owner hardware;
actual input-to-photon timing; libmypaint byte parity; every `.myb` setting;
future textured/custom brushes; complete pressure-device input; reliable
Windows/macOS/export packaging. Do not mark T-095 Done without owner approval.
