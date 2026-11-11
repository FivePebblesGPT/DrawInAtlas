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

## NativeHard whole-batch preflight

The opt-in `hard_segments` class now validates the complete signed source-space
point batch and the exact clipped candidate rectangles *before* updating the
native once-per-stroke coverage set or previous point. A late invalid point,
unsafe candidate rectangle or batch exceeding **1,048,576 candidate pixels**
returns `ok=false` with no emitted pixels and no cursor/coverage mutation;
retries from the same state remain deterministic. Valid swept-circle coverage
still uses its original geometric predicate. This does not change the default
Legacy brush or imply error rollback inside Hokusai's separate native surface.

After a native build and standalone import, run
`res://tests/t095_native_hard_atomic.gd` to check 28 independent assertions;
its test must **not** be treated as passed without an installed native binary.
The on-demand T-095 workflow builds the native library before running this
fail-closed check. See
[engineering evidence](../../docs/evidence/T-095-2026-11-09-native-hard-preflight.md).

## NativeHard source-read transaction (2026-11-11)

Whole-window preflight is insufficient when Rust returns valid coverage but
a later GDScript source tile fails to load. Canvas selects NativeHard only
when the installed `DrawingNativeBrush` implements `begin_hard_batch`,
`commit_hard_batch` and `rollback_hard_batch`; older binaries explicitly
fall back to Legacy. `DrawingEditSession.paint_path_native_hard()` begins
the transaction before invoking `hard_segments`, rolls back native coverage,
previous endpoint and detached preview on a failed source read, and commits
the native journal only after all GDScript pixels are staged. Native rollback
journals **only newly accepted pixel positions** rather than copying the
whole accumulated coverage set per motion event. Existing direct hard-brush
raster calls without this acknowledgement are not a substitute for the
safe `DrawingEditSession` wrapper.

After a local native release build and cold standalone import, run
`res://tests/t095_native_hard_source_atomic.gd`: **113/113** signed
Brush/Eraser real-native retry/skip and history checks. The original native
binary fails **7/53** Brush checks; a previous binary with no new handshake
still falls back to Legacy. [Evidence](../../docs/evidence/T-095-2026-11-11-native-hard-source-rollback.md).

## NativeHard long-diagonal scanlines (2026-11-11)

After the existing preflight validates the **whole rectangular candidate
budget**, NativeHard now computes a conservative X span per oblique row before
running the unchanged f32 nearest-segment coverage predicate and once-only
set. The span uses double-precision bound arithmetic with a four-pixel safety
margin, and falls back to the original complete rectangle at ≥1M source-space
coordinates or near-horizontal strokes; the budget and rollback handshake are
unchanged. This is an **internal candidate rejection optimization**, not a
stamp/texture brush implementation. Native output order stays y-major/x-major.

The real-extension `t095_native_hard_scanline_smoke.gd` passes 42/42 checks,
with 12 exact original-rectangle oracle cases and an original native
high-coordinate witness. Rust's `hard_scanlines_equal_original_rectangles`
unit test compares exact native f32 results for 11 fixed and 96 additional
sampled segments. The deliberately incorrect narrowed-row control fails the
Godot oracle. The optional `t095_native_hard_scanline_bench.gd` is **native
CPU only**; hardware catch-up and input-to-photon latency remain unverified.
[Evidence](../../docs/evidence/T-095-2026-11-11-native-hard-scanlines.md).

## NativeHard packed RGBA coordinate transfer (2026-11-11)

The native coverage loop now appends accepted signed `(x, y)` coordinates to
one Rust `Vec<i32>`, then converts it into Godot's `PackedInt32Array` in one
allocation/copy. Previously it pushed **two Godot packed-array elements per
pixel**, including 29,175 writes for each coordinate in a 60px diagonal run.
The exact f32 coverage predicate, row bounds, once-only coverage, output order,
whole-batch preflight and GDScript transaction handshake remain unchanged.
A real-extension, independent full-rectangle oracle compares exact ordered
pixels across a large sweep, overlapping and return paths, empty repeated
output, and a rejected/rolled-back batch. It requires the extension and the
`T095_NATIVE_HARD_PACKED_OUTPUT_PASSED` marker; see
[engineering evidence](../../docs/evidence/T-095-2026-11-11-native-hard-packed-output.md).
The opt-in native-call benchmark is not a full Brush/preview/GPU latency test.

## Hokusai packed pigment delta transfer (2026-11-11)

`preset_segments` accumulates exact signed `(x, y, straight-RGBA8)` triples
in a Rust vector, then converts to one Godot `PackedInt32Array` instead of
calling Godot's packed-array `push` three times for every changed pixel.
The sorted dirty-tile order, row-major pixel order, fixed-point-to-RGBA8
quantization, native surface state and GDScript batch acknowledgement are
unchanged. `t095_native_preset_packed_output.gd` hashes the complete exported
stream against all four **pre-change** MyPaint preset binaries and checks
real-native rejected-batch rollback/retry against an uninterrupted reference.
The opt-in `t095_native_preset_packed_bench.gd` measures native calls only;
performance measurements do not prove interactive or hardware acceptance.
[Evidence](../../docs/evidence/T-095-2026-11-11-native-preset-packed-output.md).

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

### 2026-11-09 hot RGBA8 blend checkpoint

The GDScript `DrawingEditSession._blend` keeps the original source-over
float channel expression and rounding but removes per-pixel Array allocation.
The Hokusai tile loop reads already-prevalidated, read-only source pixel
maps via integer local offsets rather than invoking `get_rgba()` per dab.
`drawing/tests/brush_blend_math_smoke.gd` independently preserves the
previous array equation and compares 98,304 RGBA8 pairs exactly; the T-095
on-demand workflow now runs it. Five-stroke Xvfb pointer evidence: Hokusai
stage CPU p95 347.704→281.002 ms; composition per-frame p95
29.247→21.833 ms; release→commit p95 approximately unchanged. See
[control and test evidence](../../docs/evidence/T-095-2026-11-09-blend.md).
This **does not** establish owner GPU input-to-photon responsiveness or
justify setting the default backend to Hokusai.

### 2026-11-09 signed-tile delta preflight checkpoint

Hokusai's spatially clustered output now reuses the last formatted signed
storage-tile key and derives local offsets from its integer origin. Rectangular
clip rejection avoids a per-pixel `Vector2i`; boolean masks remain checked
through the existing selection API. The tile key cache is never used to skip
coordinate validation or source preflight. A two-case RGBA8 blend shortcut
(fully opaque source, transparent destination) keeps all original float math
for other alpha pairs, and normalizes signed packed pigments. The 114,688
old-equation comparisons and expanded 119-check native delta oracle pass.
Paired Xvfb mouse-input Hokusai stage CPU p95 changed
275.158→239.448ms; [evidence and limitations](../../docs/evidence/T-095-2026-11-09-cached-tile-preflight.md).
The Linux prototype remains opt-in: this is not a real-device responsiveness,
pressure, cross-platform export or T-095 owner-approval milestone.

### 2026-11-09 tile-run buffered GDScript staging

The GDScript native-delta preflight now keeps the current Drawing storage
`PackedInt32Array` local until the next storage-tile boundary, instead of
fetching and reassigning it through a Dictionary after **every** pixel.
Packed arrays can detach on mutation after Dictionary retrieval. The
batch still validates **all** coordinates and resolves all required source
tiles before changing detached previews. A return to an earlier tile reloads
its buffer and appends in input order; source alpha, selection and canonical
commit behavior are unchanged. A new full 4,096-pixel tile / alternating
signed-tile oracle is included in the existing 126-check Hokusai test. The
paired software brush witness improves staging p95 235.533→215.324ms;
[measurements](../../docs/evidence/T-095-2026-11-09-tile-run-buffer.md).
Hokusai remains opt-in and slower than Legacy under this workload. Owner
input-to-photon acceptance and cross-platform packaging remain outstanding.


### 2026-11-09 cached raw fixed-point Hokusai export (not owner acceptance)

The native per-stroke dirty exporter now caches each tile's last fix15 4×u16
raw pixels alongside the previously exported u32 RGBA8 buffer. Unchanged
raw pixels skip per-pixel linear→sRGB conversion; a changed raw value only
exports a new triple when the **quantized** RGBA8 differs. Additional memory
is 32 KiB per visited 64×64 native tile. An invalid later input position
or non-finite pressure is rejected before mutating any native brush state;
the existing ABI still signals rejection with an empty output array.

The new `drawing/tests/t095_native_export_cache.gd` fixture hashes the full
batch-delimited stream against frozen old-library output for four real `.myb`
presets and checks that rejected input cannot corrupt a following batch. It
requires the actual native library and pinned Godot 4.8b2; it is not a
binary-free CI test. Two Rust unit oracles independently check full-tile
quantization, changed/unchanged raw bytes, transparent erasure and silent
sub-RGBA8 fixed-point changes. `cargo test` and `cargo clippy --all-targets
-- -D warnings` pass against the vendor archive in offline mode.

Paired five-stroke Xvfb/Mesa evidence shows lower **native exporter** CPU
p95 (35.184→25.035ms) but no improvement in **full gesture** staging p95
(237.346→253.152ms); Legacy is still faster. [Measurements and limitations](../../docs/evidence/T-095-2026-11-09-native-raw-pixel-export.md).
T-095 remains `In Progress` with owner manual review required.

### 2026-11-09 signed native tile preflight (software-only checkpoint)

For common power-of-two Drawing storage tiles, GDScript Hokusai-delta
preflight now uses a signed arithmetic right shift (floor quotient) and
bitmask (nonnegative local remainder) instead of per-delta signed division
and coordinate reconstruction. Non-power-of-two strides retain the original
exact path. An independent **422/422** deterministic oracle in
`drawing/tests/t095_tile_shift_smoke.gd` tests both branches against
original per-pixel staging at signed >32-bit anchors, including selection,
clipping, preview, commit and Undo/Redo. Two paired Xvfb/Mesa 60px pointer
comparisons reduced Hokusai CPU staging p95 201.491→183.443ms and
204.460→186.535ms; Legacy still stages at 167.412ms p95. These software
measurements do **not** establish physical input-to-photon responsiveness,
so Legacy remains the default and T-095's owner gate is open.
[Evidence and reproduction](../../docs/evidence/T-095-2026-11-09-signed-tile-shift.md).
